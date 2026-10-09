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


def build_metadata_environment(artifacts):
    """Forward artifact build provenance, without host paths or arbitrary fields."""
    fields = ("compiler", "sdk", "macOS", "sourceRevision", "xcode")
    path = Path(artifacts) / "toolchain.json"
    metadata = {}
    try:
        if path.exists():
            if path.stat().st_size > 32768:
                raise ValueError("Oversized build metadata")
            value = json.loads(path.read_text())
            if not isinstance(value, dict):
                raise ValueError("Build metadata must be an object")
            for field in fields:
                if field not in value:
                    continue
                text = value[field]
                if not isinstance(text, str) or not text.strip() or len(text.encode()) > 4096 or any(ord(character) < 32 and character not in "\n\t" for character in text):
                    raise ValueError("Invalid build metadata field")
                metadata[field] = text
    except (OSError, ValueError, UnicodeError):
        metadata = {"compiler": None}
    payload = json.dumps(metadata, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    if len(payload.encode("utf-8")) > 32768:
        metadata = {"compiler": None}
        payload = json.dumps(metadata, ensure_ascii=False)
    result = {"STRATOSPHERE_BUILD_METADATA": payload}
    if isinstance(metadata.get("sourceRevision"), str):
        result["STRATOSPHERE_SOURCE_REVISION"] = metadata["sourceRevision"]
    return result


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
        environment.pop("STRATOSPHERE_SOURCE_REVISION", None)
        environment.update(build_metadata_environment(options.artifacts.resolve()))
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
