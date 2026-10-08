import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[2] / "E2E" / "native.py"
spec = importlib.util.spec_from_file_location("native", MODULE)
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class IsolationTests(unittest.TestCase):
    def test_personal_mac_cannot_opt_into_guest_with_marker_alone(self):
        errors = native.isolation_errors("guest", {"STRATOSPHERE_GUEST": "1"}, "Mac14,6")
        self.assertTrue(errors)

    def test_guest_requires_both_guest_hardware_and_explicit_profile(self):
        self.assertFalse(native.isolation_errors("guest", {"STRATOSPHERE_GUEST": "1"}, "VirtualMac2,1"))
        self.assertTrue(native.isolation_errors("guest", {}, "VirtualMac2,1"))

    def test_hosted_profile_rejects_self_hosted_personal_runner(self):
        self.assertTrue(native.isolation_errors("hosted", {
            "GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "RUNNER_ENVIRONMENT": "self-hosted"
        }, "Mac14,6"))
        self.assertFalse(native.isolation_errors("hosted", {
            "GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "RUNNER_ENVIRONMENT": "github-hosted"
        }, "Mac14,6"))


if __name__ == "__main__":
    unittest.main()
