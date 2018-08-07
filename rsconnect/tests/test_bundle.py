
import json
import sys
import tarfile

from unittest import TestCase
from os.path import dirname, exists, join

from rsconnect.environment import detect_environment
from rsconnect.bundle import make_bundle


class TestBundle(TestCase):
    def get_dir(self, name):
        path = join(dirname(__file__), 'data', name)
        self.assertTrue(exists(path))
        return path

    def python_version(self):
        return '.'.join(map(str, sys.version_info[:3]))

    def test_bundle1(self):
        self.maxDiff = 5000
        dir = self.get_dir('pip1')
        nb_path = join(dir, 'dummy.ipynb')

        environment = detect_environment(dir)
        bundle = make_bundle(nb_path, environment)

        tar = tarfile.open(mode='r:gz', fileobj=bundle)

        try:
            names = sorted(tar.getnames())
            self.assertEqual(names, [
                'dummy.ipynb',
                'manifest.json',
                'requirements.txt',
            ])

            reqs = tar.extractfile('requirements.txt').read()
            self.assertEqual(reqs, b'numpy\npandas\nmatplotlib\n')

            manifest = json.load(tar.extractfile('manifest.json'))
            self.assertEqual(manifest, {
                "version": 1,
                "metadata": {
                    "appmode": "jupyter-static",
                    "entrypoint": "dummy.ipynb"
                },
                "python": {
                    "version": self.python_version(),
                    "package_manager": {
                        "name": "pip",
                        "version": "10.0.1",
                        "package_file": "requirements.txt"
                    }
                },
                "files": {
                    "dummy.ipynb": {
                        "checksum": "d41d8cd98f00b204e9800998ecf8427e"
                    },
                    "requirements.txt": {
                        "checksum": "5f2a5e862fe7afe3def4a57bb5cfb214"
                    }
                }
            })
        finally:
            tar.close()
            bundle.close()
