"""Run real qualification probes only in an explicitly isolated test OS."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]


def isolation_errors(profile, environment, hardware_model):
    if profile == "hosted":
        if any(environment.get(key) != value for key, value in {
            "GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "RUNNER_ENVIRONMENT": "github-hosted"
        }.items()):
            return ["The hosted profile requires a GitHub-hosted macOS runner"]
    elif profile == "guest":
        if environment.get("STRATOSPHERE_GUEST") != "1" or not hardware_model.startswith("VirtualMac"):
            return ["The guest profile requires an explicitly marked macOS virtual machine"]
    else:
        return ["An isolated hosted or guest profile is required"]
    return []


def stop_group(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["hosted", "guest"], required=True)
    parser.add_argument("--artifacts", type=Path, default=ROOT / ".local/build")
    parser.add_argument("--output", type=Path, default=ROOT / ".local/results" / uuid.uuid4().hex,
                        help="New run directory; existing paths are rejected to preserve earlier evidence")
    parser.add_argument("--timeout", type=int, default=120)
    options = parser.parse_args()
    if options.timeout <= 0:
        parser.error("Timeout must be positive")
    try:
        options.output.mkdir(parents=True, exist_ok=False)
    except OSError as error:
        parser.error("Select a new --output run directory; cannot create " + str(options.output) + ": " + str(error))
    result_file = options.output / "qualification.json"
    summary = {"status": "setup-failed", "profile": options.profile,
               "timestamp": datetime.now(timezone.utc).isoformat(), "probeExitCode": None, "timedOut": False}
    status = 2
    try:
        try:
            hardware = subprocess.check_output(["/usr/sbin/sysctl", "-n", "hw.model"], text=True).strip()
        except (OSError, subprocess.CalledProcessError):
            hardware = "unavailable"
        summary["hardware"] = hardware
        errors = isolation_errors(options.profile, os.environ, hardware)
        probe = options.artifacts.resolve() / "EnvironmentProbe"
        fixture = options.artifacts.resolve() / "FixtureApp.app"
        if not probe.is_file() or not fixture.is_dir():
            errors.append("Build EnvironmentProbe and FixtureApp.app before qualification")
        if errors:
            raise RuntimeError("\n".join(errors))
        command = [str(probe), "--profile", options.profile, "--fixture", str(fixture), "--output", str(result_file.resolve())]
        environment = os.environ.copy()
        metadata_file = options.artifacts.resolve() / "toolchain.json"
        if metadata_file.is_file():
            metadata = json.loads(metadata_file.read_text())
            if not isinstance(metadata, dict):
                raise ValueError("Toolchain metadata must be a JSON object")
            if metadata.get("sourceRevision"):
                environment["STRATOSPHERE_SOURCE_REVISION"] = metadata["sourceRevision"]
        with (options.output / "probe.log").open("w") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True, env=environment)
            try:
                status = process.wait(timeout=options.timeout)
            except subprocess.TimeoutExpired:
                summary.update(timedOut=True, error="Probe exceeded its deadline")
                log.write("\nProbe exceeded its deadline. Owned process group stopped.\n")
            except KeyboardInterrupt:
                status = 130
                summary.update(status="interrupted", error="User interrupted the run")
                log.write("\nRun interrupted. Owned process group stopped.\n")
            finally:
                try:
                    stop_group(process)
                finally:
                    summary["probeExitCode"] = process.returncode
        if result_file.is_file():
            result = json.loads(result_file.read_text())
            if not isinstance(result, dict):
                raise ValueError("Probe result must be a JSON object")
            summary["probeStatus"] = result.get("status", "setup-failed")
            if "error" not in summary:
                if status == 0 and summary["probeStatus"] == "passed":
                    summary["status"] = "passed"
                elif summary["probeStatus"] == "passed":
                    raise RuntimeError("Probe exited unsuccessfully with code " + str(status))
                else:
                    status = 2
                    summary["status"] = summary["probeStatus"]
        elif "error" not in summary:
            raise RuntimeError("Probe produced no result")
    except KeyboardInterrupt:
        status = 130
        summary.update(status="interrupted", error="User interrupted the run")
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        status = 2
        summary.update(status="setup-failed", error=str(error))
    finally:
        summary["exitCode"] = status
        (options.output / "run.json").write_text(json.dumps(summary, indent=2) + "\n")
    if "error" in summary:
        print(summary["error"], file=sys.stderr)
    print("Qualification evidence: " + str(options.output.resolve()))
    return status


if __name__ == "__main__":
    sys.exit(main())
