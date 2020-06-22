NB_UID := $(shell id -u)
NB_GID := $(shell id -g)

IMAGE := rstudio/rsconnect-jupyter-py
VERSION := $(shell pipenv run python setup.py --version)
BDIST_WHEEL := dist/rsconnect_jupyter-$(VERSION)-py2.py3-none-any.whl
S3_PREFIX := s3://rstudio-connect-downloads/connect/rsconnect-jupyter
PORT := $(shell printenv PORT || echo 9999)

# NOTE: See the `dist` target for why this exists.
SOURCE_DATE_EPOCH := $(shell date +%s)
export SOURCE_DATE_EPOCH

.PHONY: clean
clean:
	rm -rf build/ dist/ docs/out/ rsconnect_jupyter.egg-info/

.PHONY: all-images
all-images: image2.7 image3.5 image3.6 image3.7 image3.8

image%:
	docker build \
		--tag $(IMAGE)$* \
		--file Dockerfile \
		--build-arg BASE_IMAGE=continuumio/miniconda:4.4.10 \
		--build-arg NB_UID=$(NB_UID) \
		--build-arg NB_GID=$(NB_GID) \
		--build-arg PY_VERSION=$* \
		.

.PHONY: launch
launch:
	docker run --rm -i -t \
		-v $(CURDIR)/notebooks$(PY_VERSION):/notebooks \
		-v $(CURDIR):/rsconnect_jupyter \
		-e NB_UID=$(NB_UID) \
		-e NB_GID=$(NB_GID) \
		-e PY_VERSION=$(PY_VERSION) \
		-p :$(PORT):9999 \
		$(DOCKER_IMAGE) \
		/rsconnect_jupyter/run.sh $(TARGET)


notebook%:
	make DOCKER_IMAGE=$(IMAGE)$* PY_VERSION=$* TARGET=run launch

.PHONY: all-tests
all-tests: test2.7 test3.5 test3.6 test3.7 test3.8

.PHONY: test
test: version-frontend
	pipenv run python -V
	pipenv run python -Wi setup.py test

test%: version-frontend
	make DOCKER_IMAGE=rstudio/rsconnect-jupyter-py$* PY_VERSION=$* TARGET=test launch

.PHONY: test-selenium
test-selenium:
	$(MAKE) -C selenium clean test-env-up jupyter-up test || EXITCODE=$$? ; \
	$(MAKE) -C selenium jupyter-down || true ; \
	$(MAKE) -C selenium test-env-down || true ; \
	exit $$EXITCODE

# NOTE: Wheels won't get built if _any_ file it tries to touch has a timestamp
# before 1980 (system files) so the $(SOURCE_DATE_EPOCH) current timestamp is
# exported as a point of reference instead.
.PHONY: dist
dist: version-frontend
	pipenv run python setup.py bdist_wheel
	pipenv run twine check $(BDIST_WHEEL)
	rm -vf dist/*.egg
	@echo "::set-output name=whl::$(BDIST_WHEEL)"
	@echo "::set-output name=whl_basename::$(notdir $(BDIST_WHEEL))"

.PHONY: run
run: install
	pipenv run jupyter-notebook -y --notebook-dir=/notebooks --ip='0.0.0.0' --port=9999 --no-browser --NotebookApp.token=''

.PHONY: install
install:
	pipenv install --dev
	pipenv run jupyter-nbextension install --symlink --user --py rsconnect_jupyter
	pipenv run jupyter-nbextension enable --py rsconnect_jupyter
	pipenv run jupyter-serverextension enable --py rsconnect_jupyter

build/mock-connect/bin/flask:
	bash -c '\
		mkdir -p build && \
		virtualenv build/mock-connect && \
		. build/mock-connect/bin/activate && \
		pip install flask'

.PHONY: mock-server
mock-server: build/mock-connect/bin/flask
	bash -c '\
		. build/mock-connect/bin/activate && \
		FLASK_APP=mock_connect.py flask run --host=0.0.0.0'

.PHONY: yarn
yarn:
	yarn install

.PHONY: lint
lint: lint-js

.PHONY: lint-js
lint-js:
	npm run lint

## Specify that Docker runs with the calling user's uid/gid to avoid file
## permission issues on Linux dev hosts.
DOCKER_RUN_AS =
ifeq (Linux,$(shell uname))
	DOCKER_RUN_AS = -u $(shell id -u):$(shell id -g)
endif

DOCS_IMAGE := rsconnect-jupyter-docs:local
BUILD_DOC := docker run --rm=true $(DOCKER_RUN_AS) \
	-e VERSION=$(VERSION) \
	$(DOCKER_ARGS) \
	-v $(CURDIR):/rsconnect_jupyter \
	-w /rsconnect_jupyter \
	$(DOCS_IMAGE) docs/build-doc.sh

.PHONY: docs-image
docs-image:
	docker build -t $(DOCS_IMAGE) ./docs

.PHONY: docs-build
docs-build: docs/out
	$(BUILD_DOC)

docs/out:
	mkdir -p $@

dist/rsconnect-jupyter-$(VERSION).pdf: docs/README.md docs/*.gif docs/out
	$(BUILD_DOC)

.PHONY: version-frontend
version-frontend:
	printf '{"version":"%s"}\n' $(VERSION) >rsconnect_jupyter/static/version.json

.PHONY: sync-latest-to-s3
sync-latest-to-s3:
	aws s3 cp --acl bucket-owner-full-control \
		$(BDIST_WHEEL) \
		$(S3_PREFIX)/latest/rsconnect_jupyter-latest-py2.py3-none-any.whl
