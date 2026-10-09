"""Clone a prepared Tart image, run the native probe in its GUI session, and discard it."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from native import build_metadata_environment


class Guest:
    def __init__(self, image, name, tart, environment, log_path):
        if image == name:
            raise ValueError("The disposable guest must differ from its prepared image")
        self.image, self.name, self.tart = image, name, tart
        self.environment, self.log_path = environment, Path(log_path)
        self.process = None
        self.cleanup_errors = []

    def command(self, *arguments, timeout=30, check=True):
        return subprocess.run([self.tart, *arguments], env=self.environment, stdout=self.log,
                              stderr=subprocess.STDOUT, timeout=timeout, check=check)

    def __enter__(self):
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self.log = self.log_path.open("w")
        try:
            self.command("clone", self.image, self.name, timeout=120)
        except BaseException:
            self.cleanup()
            raise
        return self

    def boot(self):
        self.process = subprocess.Popen([self.tart, "run", "--no-graphics", self.name],
                                        env=self.environment, stdout=self.log, stderr=subprocess.STDOUT)

    def cleanup(self):
        try:
            try:
                self.command("stop", self.name, timeout=15, check=False)
            except (OSError, subprocess.SubprocessError) as error:
                self.cleanup_errors.append("Guest stop failed: " + str(error))
            if self.process is not None:
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.terminate()
                    try:
                        self.process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        self.process.kill()
                        self.process.wait(timeout=5)
        except (OSError, subprocess.SubprocessError) as error:
            self.cleanup_errors.append("Guest process termination failed: " + str(error))
        finally:
            try:
                self.command("delete", self.name, timeout=30)
            except (OSError, subprocess.SubprocessError) as error:
                self.cleanup_errors.append("Guest deletion failed: " + str(error))
            finally:
                try:
                    self.log.write("\n" + "\n".join(self.cleanup_errors))
                finally:
                    self.log.close()

    def __exit__(self, error_type, error, traceback):
        self.cleanup()
        if self.cleanup_errors and error is None:
            raise RuntimeError("Guest cleanup failed: " + "; ".join(self.cleanup_errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default=os.environ.get("STRATOSPHERE_VM_IMAGE"), help="Stopped, prepared local image name")
    parser.add_argument("--user", default="admin")
    parser.add_argument("--ssh-key", type=Path, required=True, help="Dedicated guest SSH key")
    parser.add_argument("--tart-home", type=Path, default=Path(os.environ.get("TART_HOME", ROOT / ".local/tart")))
    parser.add_argument("--artifacts", type=Path, default=ROOT / ".local/build")
    parser.add_argument("--output", type=Path, default=ROOT / ".local/results" / uuid.uuid4().hex,
                        help="New run directory; existing paths are rejected to preserve earlier evidence")
    options = parser.parse_args()
    if not options.image or "/" in options.image or ":" in options.image:
        parser.error("Select a prepared local Tart image with --image; image downloads are a separate preparation step")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]*", options.user):
        parser.error("Guest user must be a local macOS account name")
    if not options.ssh_key.is_file():
        parser.error("Dedicated guest SSH key not found")
    artifacts = options.artifacts.resolve()
    if not (artifacts / "EnvironmentProbe").is_file() or not (artifacts / "FixtureApp.app").is_dir():
        parser.error("Build the native probe and fixture before launching a guest")
    tart = shutil.which("tart")
    if tart is None:
        parser.error("Tart is unavailable; enter nix develop")
    try:
        options.output.mkdir(parents=True, exist_ok=False)
    except OSError as error:
        parser.error("Select a new --output run directory; cannot create " + str(options.output) + ": " + str(error))
    output = options.output.resolve()
    run_id = uuid.uuid4().hex
    name = "stratosphere-test-" + run_id
    environment = {**os.environ, "TART_HOME": str(options.tart_home.resolve())}
    summary = {"status": "setup-failed", "image": options.image, "guest": name, "run": run_id}
    guest = Guest(options.image, name, tart, environment, output / "tart.log")
    status = 2
    try:
        with guest:
            guest.boot()
            deadline = time.monotonic() + 180
            address = ""
            while time.monotonic() < deadline:
                if guest.process.poll() is not None:
                    raise RuntimeError("Tart exited before the guest was ready")
                result = subprocess.run([tart, "ip", name], env=environment, capture_output=True, text=True, timeout=10)
                if result.returncode == 0 and re.fullmatch(r"[0-9a-fA-F:.]+", result.stdout.strip()):
                    address = result.stdout.strip()
                    break
                time.sleep(1)
            if not address:
                raise RuntimeError("Guest networking did not become ready")
            connection = ["-i", str(options.ssh_key.resolve()), "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                          "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=" + str(output / "known_hosts")]
            destination = options.user + "@" + address

            def ssh(*arguments, check=True):
                return subprocess.run(["ssh", *connection, destination, shlex.join(arguments)],
                                      capture_output=True, text=True, check=check, timeout=15)

            while time.monotonic() < deadline:
                result = ssh("id", "-u", check=False)
                if result.returncode == 0:
                    break
                time.sleep(1)
            else:
                raise RuntimeError("Guest SSH did not become ready using the dedicated key")
            uid = result.stdout.strip()
            if not uid.isdigit():
                raise RuntimeError("Guest UID could not be established")
            ssh("launchctl", "print", "gui/" + uid)
            remote = "/Users/" + options.user + "/.local/stratosphere-e2e/" + run_id
            remote_tools = "/Users/" + options.user + "/.local/stratosphere-test-tools"
            ssh("mkdir", "-p", remote_tools, remote)
            # Replace the owned fixture bundle so changed builds leave no stale signed resources.
            ssh("rm", "-rf", remote_tools + "/FixtureApp.app")
            subprocess.run(["scp", *connection, "-r", str(artifacts / "FixtureApp.app"), str(artifacts / "EnvironmentProbe"),
                            destination + ":" + remote_tools + "/"], check=True, timeout=60)
            label = "dev.stratosphere.qualification." + run_id
            job = {
                "Label": label, "RunAtLoad": True,
                "ProgramArguments": [remote_tools + "/EnvironmentProbe", "--profile", "guest", "--fixture", remote_tools + "/FixtureApp.app", "--output", remote + "/qualification.json"],
                "EnvironmentVariables": {"STRATOSPHERE_GUEST": "1"},
                "StandardOutPath": remote + "/probe.log", "StandardErrorPath": remote + "/probe.log",
            }
            job["EnvironmentVariables"].update(build_metadata_environment(artifacts))
            job["EnvironmentVariables"]["STRATOSPHERE_IMAGE_IDENTITY"] = options.image
            job_file = output / "probe.plist"
            job_file.write_bytes(plistlib.dumps(job))
            subprocess.run(["scp", *connection, str(job_file), destination + ":" + remote + "/probe.plist"], check=True, timeout=30)
            ssh("launchctl", "bootstrap", "gui/" + uid, remote + "/probe.plist")
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                # Stream partial logs out so discarding a stuck guest does not lose all evidence.
                log = ssh("cat", remote + "/probe.log", check=False)
                (output / "probe.log").write_text(log.stdout + log.stderr)
                if ssh("test", "-f", remote + "/qualification.json", check=False).returncode == 0:
                    data = ssh("cat", remote + "/qualification.json").stdout
                    (output / "qualification.json").write_text(data)
                    result = json.loads(data)
                    status = 0 if result.get("status") == "passed" else 2
                    summary["probeStatus"] = result.get("status", "setup-failed")
                    summary["status"] = summary["probeStatus"]
                    break
                time.sleep(1)
            else:
                raise RuntimeError("Guest qualification exceeded its deadline")
            ssh("launchctl", "bootout", "gui/" + uid + "/" + label, check=False)
    except KeyboardInterrupt:
        status = 130
        summary.update(status="interrupted", error="User interrupted the run")
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        status = 2
        summary.update(status="setup-failed", error=str(error))
    finally:
        summary["cleanupErrors"] = guest.cleanup_errors
        (output / "run.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("Guest evidence: " + str(output))
    return status


if __name__ == "__main__":
    sys.exit(main())
