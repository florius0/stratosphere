import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


def load_runner(name):
    path = Path(__file__).resolve().parents[2] / "E2E" / (name + ".py")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


native = load_runner("native")
vm = load_runner("vm")


def executable(path, source):
    path.write_text("#!" + sys.executable + "\n" + source)
    path.chmod(0o755)


def artifacts(root, source):
    directory = root / "artifacts"
    directory.mkdir()
    (directory / "FixtureApp.app").mkdir()
    executable(directory / "EnvironmentProbe", source)
    (directory / "toolchain.json").write_text('{"sourceRevision": "test-revision"}')
    return directory


class NativeEvidenceTests(unittest.TestCase):
    def invoke(self, build, output, timeout=5):
        environment = {"GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "RUNNER_ENVIRONMENT": "github-hosted"}
        arguments = ["native.py", "--profile", "hosted", "--artifacts", str(build), "--output", str(output), "--timeout", str(timeout)]
        with patch.object(sys, "argv", arguments), patch.dict(os.environ, environment), \
                patch.object(native.subprocess, "check_output", return_value="Mac14,6"), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as diagnostic:
            try:
                status = native.main()
            except SystemExit as error:
                status = error.code
            except OSError as error:
                self.fail("Runner must report launch failure in current evidence: " + str(error))
            return status, diagnostic.getvalue()

    def test_reused_output_is_rejected_before_missing_result_can_accept_old_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = artifacts(root, "import pathlib\npathlib.Path(__file__).with_name('launched').touch()\n")
            output = root / "results"
            output.mkdir()
            previous = '{"status": "passed", "run": "previous"}\n'
            (output / "qualification.json").write_text(previous)
            status, diagnostic = self.invoke(build, output)
            self.assertNotEqual(status, 0)
            self.assertIn("new", diagnostic.lower())
            self.assertFalse((build / "launched").exists())
            self.assertEqual((output / "qualification.json").read_text(), previous)

    def test_reused_output_is_rejected_before_launch_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = artifacts(root, "pass\n")
            (build / "EnvironmentProbe").chmod(0o644)
            output = root / "results"
            output.mkdir()
            (output / "qualification.json").write_text('{"status": "passed"}')
            status, diagnostic = self.invoke(build, output)
            self.assertNotEqual(status, 0)
            self.assertIn("new", diagnostic.lower())

    def test_launch_failure_has_current_setup_failure_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = artifacts(root, "pass\n")
            (build / "EnvironmentProbe").chmod(0o644)
            output = root / "results"
            status, _ = self.invoke(build, output)
            self.assertNotEqual(status, 0)
            self.assertTrue((output / "run.json").is_file(), "Current wrapper evidence is required")
            summary = json.loads((output / "run.json").read_text())
            self.assertEqual(summary["status"], "setup-failed")
            self.assertIsNone(summary["probeExitCode"])
            self.assertTrue(summary["error"])
            self.assertFalse((output / "qualification.json").exists())

    def test_zero_exit_without_result_is_setup_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = artifacts(root, "pass\n")
            output = root / "results"
            status, _ = self.invoke(build, output)
            self.assertNotEqual(status, 0)
            self.assertTrue((output / "run.json").is_file(), "Current wrapper evidence is required")
            summary = json.loads((output / "run.json").read_text())
            self.assertEqual(summary["status"], "setup-failed")
            self.assertEqual(summary["probeExitCode"], 0)
            self.assertIn("no result", summary["error"].lower())

    def test_deadline_preserves_probe_evidence_with_failed_wrapper_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = artifacts(root, """import json, os, pathlib, sys, time
output = pathlib.Path(sys.argv[sys.argv.index('--output') + 1])
output.write_text(json.dumps({'status': 'passed', 'sourceRevision': os.environ['STRATOSPHERE_SOURCE_REVISION']}))
time.sleep(30)
""")
            output = root / "results"
            status, _ = self.invoke(build, output, timeout=1)
            self.assertNotEqual(status, 0)
            self.assertTrue((output / "run.json").is_file(), "Current wrapper evidence is required")
            summary = json.loads((output / "run.json").read_text())
            self.assertEqual(summary["status"], "setup-failed")
            self.assertTrue(summary["timedOut"])
            self.assertEqual(summary["probeStatus"], "passed")
            self.assertNotEqual(summary["probeExitCode"], 0)
            self.assertEqual(json.loads((output / "qualification.json").read_text())["sourceRevision"], "test-revision")

    def test_owned_probe_ignoring_term_is_reaped_after_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = artifacts(root, """import signal, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
time.sleep(30)
""")
            output = root / "results"
            status, _ = self.invoke(build, output, timeout=1)
            self.assertNotEqual(status, 0)
            summary = json.loads((output / "run.json").read_text())
            self.assertEqual(summary["status"], "setup-failed")
            self.assertTrue(summary["timedOut"])
            self.assertEqual(summary["probeExitCode"], -signal.SIGKILL)

    def test_success_preserves_current_probe_and_source_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = artifacts(root, """import json, os, pathlib, sys
output = pathlib.Path(sys.argv[sys.argv.index('--output') + 1])
output.write_text(json.dumps({'status': 'passed', 'sourceRevision': os.environ['STRATOSPHERE_SOURCE_REVISION']}))
""")
            output = root / "results"
            status, _ = self.invoke(build, output)
            self.assertEqual(status, 0)
            summary = json.loads((output / "run.json").read_text())
            self.assertEqual(summary["status"], "passed")
            self.assertEqual(summary["probeExitCode"], 0)
            self.assertEqual(json.loads((output / "qualification.json").read_text())["sourceRevision"], "test-revision")


class VMOrchestrationTests(unittest.TestCase):
    def run_guest(self, root, failure, reused=False):
        build = artifacts(root, "pass\n")
        tools = root / "tools"
        tools.mkdir()
        home = root / "images"
        home.mkdir()
        (home / "prepared").mkdir()
        executable(tools / "tart", """import os, pathlib, shutil, signal, sys, time
home = pathlib.Path(os.environ['TART_HOME'])
action, *args = sys.argv[1:]
if action == 'clone':
    (home / args[1]).mkdir()
elif action == 'run':
    (home / args[-1] / 'pid').write_text(str(os.getpid()))
    time.sleep(30)
elif action == 'ip':
    if not (home / args[0] / 'pid').exists():
        sys.exit(1)
    print('127.0.0.1')
elif action == 'stop':
    pid = home / args[0] / 'pid'
    if pid.exists():
        os.kill(int(pid.read_text()), signal.SIGTERM)
elif action == 'delete':
    if os.environ.get('TEST_GUEST_FAILURE') == 'delete':
        sys.exit(9)
    shutil.rmtree(home / args[0])
""")
        executable(tools / "ssh", """import json, os, pathlib, shlex, sys
with pathlib.Path(os.environ['TEST_COMMAND_LOG']).open('a') as log:
    log.write(json.dumps({'tool': 'ssh', 'arguments': sys.argv[1:]}) + '\\n')
command = shlex.split(sys.argv[-1])
if command == ['id', '-u']:
    print('502')
elif command[0] == 'cat' and command[1].endswith('qualification.json'):
    print(json.dumps({'status': 'passed', 'evidence': 'current-guest'}))
elif command[0] == 'cat':
    print('current guest log')
""")
        executable(tools / "scp", """import json, os, pathlib, sys
with pathlib.Path(os.environ['TEST_COMMAND_LOG']).open('a') as log:
    log.write(json.dumps({'tool': 'scp', 'arguments': sys.argv[1:]}) + '\\n')
""")
        key = root / "ssh-key"
        key.touch()
        output = root / "results"
        if reused:
            output.mkdir()
            (output / "qualification.json").write_text('{"status": "passed", "run": "previous"}')
        arguments = ["vm.py", "--image", "prepared", "--ssh-key", str(key), "--tart-home", str(home), "--artifacts", str(build), "--output", str(output)]
        run = subprocess.run

        def controlled_run(command, **keywords):
            if failure == "bootout" and command[0] == "ssh" and "bootout" in command[-1]:
                raise subprocess.TimeoutExpired(command, keywords["timeout"])
            return run(command, **keywords)

        environment = {"PATH": str(tools) + os.pathsep + os.environ["PATH"], "TEST_GUEST_FAILURE": failure,
                       "TEST_COMMAND_LOG": str(root / "commands.jsonl")}
        with patch.object(sys, "argv", arguments), patch.dict(os.environ, environment), \
                patch.object(vm.subprocess, "run", side_effect=controlled_run), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            try:
                status = vm.main()
            except SystemExit as error:
                status = error.code
        return status, output, home

    def test_reused_output_is_rejected_before_guest_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            status, output, home = self.run_guest(Path(directory), "none", reused=True)
            self.assertNotEqual(status, 0)
            self.assertEqual(json.loads((output / "qualification.json").read_text())["run"], "previous")
            self.assertEqual([path.name for path in home.iterdir()], ["prepared"])
            self.assertFalse((output / "tart.log").exists())

    def test_passing_probe_then_failed_deletion_is_setup_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            status, output, home = self.run_guest(Path(directory), "delete")
            self.assertNotEqual(status, 0)
            summary = json.loads((output / "run.json").read_text())
            self.assertEqual(summary["status"], "setup-failed")
            self.assertEqual(summary["probeStatus"], "passed")
            self.assertTrue(summary["cleanupErrors"])
            self.assertEqual(json.loads((output / "qualification.json").read_text())["evidence"], "current-guest")
            self.assertTrue((home / "prepared").is_dir())

    def test_passing_probe_then_bootout_timeout_is_setup_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            status, output, home = self.run_guest(Path(directory), "bootout")
            self.assertNotEqual(status, 0)
            summary = json.loads((output / "run.json").read_text())
            self.assertEqual(summary["status"], "setup-failed")
            self.assertEqual(summary["probeStatus"], "passed")
            self.assertEqual([path.name for path in home.iterdir()], ["prepared"])
            self.assertEqual(json.loads((output / "qualification.json").read_text())["evidence"], "current-guest")

    def test_success_discards_clone_and_preserves_launch_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            status, output, home = self.run_guest(Path(directory), "none")
            self.assertEqual(status, 0)
            summary = json.loads((output / "run.json").read_text())
            self.assertEqual(summary["status"], "passed")
            self.assertEqual([path.name for path in home.iterdir()], ["prepared"])
            job = plistlib.loads((output / "probe.plist").read_bytes())
            metadata = job["EnvironmentVariables"].pop("STRATOSPHERE_BUILD_METADATA")
            self.assertEqual(json.loads(metadata), {"sourceRevision": "test-revision"})
            self.assertEqual(job["EnvironmentVariables"], {
                "STRATOSPHERE_GUEST": "1", "STRATOSPHERE_SOURCE_REVISION": "test-revision",
                "STRATOSPHERE_IMAGE_IDENTITY": "prepared",
            })


if __name__ == "__main__":
    unittest.main()
