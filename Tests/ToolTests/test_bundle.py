import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[2] / "Tools" / "bundle.py"
spec = importlib.util.spec_from_file_location("bundle", MODULE)
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class BundleTests(unittest.TestCase):
    def test_assembled_app_preserves_executable_and_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "fixture"
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o755)
            resources = root / "resources"
            resources.mkdir()
            (resources / "sample.json").write_text('{"synthetic": true}')
            output = root / "Catalog.app"
            bundle.assemble(executable, output, "dev.stratosphere.catalog", "Catalog", resources)
            metadata = plistlib.loads((output / "Contents/Info.plist").read_bytes())
            self.assertEqual(metadata["CFBundleIdentifier"], "dev.stratosphere.catalog")
            self.assertEqual(metadata["LSMinimumSystemVersion"], "26.0")
            binary = output / "Contents/MacOS/Catalog"
            self.assertEqual(binary.read_bytes(), executable.read_bytes())
            self.assertTrue(binary.stat().st_mode & 0o111)
            self.assertEqual((output / "Contents/Resources/sample.json").read_bytes(), (resources / "sample.json").read_bytes())

    def test_missing_binary_does_not_replace_existing_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "Catalog.app"
            output.mkdir()
            (output / "evidence").write_text("keep")
            with self.assertRaises(FileNotFoundError):
                bundle.assemble(root / "missing", output, "dev.stratosphere.catalog", "Catalog")
            self.assertEqual((output / "evidence").read_text(), "keep")

    def test_refuses_output_symlink_and_path_traversal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "fixture"
            executable.write_text("fixture")
            target = root / "target"
            target.mkdir()
            link = root / "Catalog.app"
            link.symlink_to(target, target_is_directory=True)
            with self.assertRaises(ValueError):
                bundle.assemble(executable, link, "dev.stratosphere.catalog", "Catalog")
            with self.assertRaises(ValueError):
                bundle.assemble(executable, root / "Other.app", "dev.stratosphere.catalog", "../escape")
            self.assertFalse((root / "escape").exists())


if __name__ == "__main__":
    unittest.main()
