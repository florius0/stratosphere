import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("vm_refit_cases", Path(__file__).with_name("test_runner_failures.py"))
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

class VMDisplayConfigTests(unittest.TestCase):
    def test_clone_disables_refit_before_boot_and_preserves_prepared_image(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            status, output, home = cases.VMOrchestrationTests().run_guest(root, "none")
            self.assertEqual(status, 0)
            summary = json.loads((output / "run.json").read_text())
            commands = [json.loads(line)["arguments"] for line in (root / "commands.jsonl").read_text().splitlines() if json.loads(line)["tool"] == "tart"]
            configuration = ["set", summary["guest"], "--no-display-refit"]
            self.assertIn(configuration, commands)
            run = next(command for command in commands if command[0] == "run")
            self.assertLess(commands.index(configuration), commands.index(run))
            self.assertEqual([path.name for path in home.iterdir()], ["prepared"])

    def test_config_failure_stops_before_boot_and_cleans_owned_clone(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            status, output, home = cases.VMOrchestrationTests().run_guest(root, "refit")
            self.assertNotEqual(status, 0)
            summary = json.loads((output / "run.json").read_text())
            self.assertEqual(summary["status"], "setup-failed")
            commands = [json.loads(line)["arguments"] for line in (root / "commands.jsonl").read_text().splitlines() if json.loads(line)["tool"] == "tart"]
            self.assertFalse(any(command[0] == "run" for command in commands))
            self.assertEqual([path.name for path in home.iterdir()], ["prepared"])
