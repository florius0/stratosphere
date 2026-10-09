import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runner_cases", Path(__file__).with_name("test_runner_failures.py"))
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)


class BuildMetadataForwardingTests(unittest.TestCase):
    def native_run(self, root, metadata):
        build = cases.artifacts(root, """import json, os, pathlib, sys
output = pathlib.Path(sys.argv[sys.argv.index('--output') + 1])
output.write_text(json.dumps({'status': 'passed', 'buildMetadata': os.environ.get('STRATOSPHERE_BUILD_METADATA')}))
""")
        if metadata is None:
            (build / "toolchain.json").unlink()
        else:
            (build / "toolchain.json").write_text(metadata)
        output = root / "results"
        status, _ = cases.NativeEvidenceTests().invoke(build, output)
        self.assertEqual(status, 0)
        raw = json.loads((output / "qualification.json").read_text())["buildMetadata"]
        self.assertIsNotNone(raw, "The real native wrapper must forward an explicit metadata contract")
        return json.loads(raw)

    def test_native_wrapper_forwards_only_build_versions_and_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            actual = self.native_run(Path(directory), json.dumps({
                "compiler": "Swift 6.3.3", "sdk": "26.5", "macOS": "26.5", "sourceRevision": "test-revision",
                "xcode": "Xcode 26.5", "sdkPath": "/private/host/sdk", "secret": "discard",
            }))
            self.assertEqual(actual, {"compiler": "Swift 6.3.3", "sdk": "26.5", "macOS": "26.5", "sourceRevision": "test-revision", "xcode": "Xcode 26.5"})

    def test_unicode_field_boundary_stays_within_probe_utf8_payload_bound(self):
        fields = ("compiler", "sdk", "macOS", "sourceRevision", "xcode")
        for count in (2048, 2049):
            with self.subTest(characters=count), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                metadata = {field: "é" * count for field in fields}
                raw = json.dumps(metadata, ensure_ascii=False)
                self.assertLessEqual(len(raw.encode("utf-8")), 32768)
                (root / "toolchain.json").write_text(raw, encoding="utf-8")
                environment = cases.native.build_metadata_environment(root)
                payload = environment["STRATOSPHERE_BUILD_METADATA"]
                self.assertLessEqual(len(payload.encode("utf-8")), 32768)
                if count == 2048:
                    self.assertEqual(json.loads(payload), metadata)
                    self.assertEqual(environment["STRATOSPHERE_SOURCE_REVISION"], metadata["sourceRevision"])
                else:
                    self.assertEqual(json.loads(payload), {"compiler": None})
                    self.assertNotIn("STRATOSPHERE_SOURCE_REVISION", environment)

    def test_missing_metadata_overrides_stale_parent_metadata(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"STRATOSPHERE_BUILD_METADATA": '{"sdk":"fake-parent"}'}):
            self.assertEqual(self.native_run(Path(directory), None), {})

    def test_malformed_metadata_reaches_probe_as_explicit_invalid_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(self.native_run(Path(directory), "["), {"compiler": None})

    def test_vm_wrapper_forwards_metadata_to_gui_job(self):
        with tempfile.TemporaryDirectory() as directory:
            status, output, _ = cases.VMOrchestrationTests().run_guest(Path(directory), "none")
            self.assertEqual(status, 0)
            import plistlib
            environment = plistlib.loads((output / "probe.plist").read_bytes())["EnvironmentVariables"]
            self.assertIn("STRATOSPHERE_BUILD_METADATA", environment)
            self.assertEqual(json.loads(environment["STRATOSPHERE_BUILD_METADATA"]), {"sourceRevision": "test-revision"})
            self.assertEqual(environment["STRATOSPHERE_SOURCE_REVISION"], "test-revision")


if __name__ == "__main__":
    unittest.main()
