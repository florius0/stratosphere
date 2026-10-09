import importlib.util
import json
from pathlib import Path
import plistlib
import shlex
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("vm_path_cases", Path(__file__).with_name("test_runner_failures.py"))
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)


class StableVMToolPathTests(unittest.TestCase):
    def test_two_runs_copy_and_launch_stable_tools_with_distinct_evidence_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            records = []
            for index in range(2):
                root = Path(directory).resolve() / str(index)
                root.mkdir()
                status, output, home = cases.VMOrchestrationTests().run_guest(root, "none")
                self.assertEqual(status, 0)
                self.assertEqual([path.name for path in home.iterdir()], ["prepared"])
                records.append((json.loads((output / "run.json").read_text()),
                                plistlib.loads((output / "probe.plist").read_bytes()),
                                [json.loads(line) for line in (root / "commands.jsonl").read_text().splitlines()], root))
            self.assertNotEqual(records[0][0]["run"], records[1][0]["run"])
            tools = "/Users/admin/.local/stratosphere-test-tools"
            for summary, job, commands, root in records:
                remote = "/Users/admin/.local/stratosphere-e2e/" + summary["run"]
                copies = [command["arguments"] for command in commands if command["tool"] == "scp"]
                self.assertEqual(copies[0][-3:], [str(root / "artifacts/FixtureApp.app"), str(root / "artifacts/EnvironmentProbe"), "admin@127.0.0.1:" + tools + "/"])
                self.assertEqual(copies[1][-1], "admin@127.0.0.1:" + remote + "/probe.plist")
                arguments = job["ProgramArguments"]
                self.assertEqual(arguments[0], tools + "/EnvironmentProbe")
                self.assertEqual(arguments[arguments.index("--fixture") + 1], tools + "/FixtureApp.app")
                self.assertEqual(arguments[arguments.index("--output") + 1], remote + "/qualification.json")
                self.assertEqual(job["StandardOutPath"], remote + "/probe.log")
                self.assertEqual(job["StandardErrorPath"], remote + "/probe.log")
                remote_commands = [shlex.split(command["arguments"][-1]) for command in commands if command["tool"] == "ssh"]
                self.assertIn(["mkdir", "-p", tools, remote], remote_commands)
                self.assertIn(["rm", "-rf", tools + "/FixtureApp.app"], remote_commands)
                self.assertIn(["launchctl", "bootstrap", "gui/502", remote + "/probe.plist"], remote_commands)
                self.assertIn(["cat", remote + "/qualification.json"], remote_commands)
                self.assertFalse(any(command[0] in {"codesign", "security"} for command in remote_commands))
            self.assertEqual(records[0][1]["ProgramArguments"][0], records[1][1]["ProgramArguments"][0])
            self.assertNotEqual(records[0][1]["StandardOutPath"], records[1][1]["StandardOutPath"])


if __name__ == "__main__":
    unittest.main()
