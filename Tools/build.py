"""Build the native foundation with an explicit compiler and SDK."""

import argparse
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

from bundle import assemble
from signing import keychain_scope, sign_artifact

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".local" / "build"


def capture(command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs).strip()


def toolchain():
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("The foundation requires Apple Silicon macOS 26+")
    os_version = capture(["/usr/bin/sw_vers", "-productVersion"])
    if int(os_version.split(".")[0]) < 26:
        raise RuntimeError("macOS 26+ is required")
    swift = os.environ.get("STRATOSPHERE_SWIFT") or capture(["/usr/bin/xcrun", "--find", "swift"])
    sdk = os.environ.get("STRATOSPHERE_SDK") or capture(["/usr/bin/xcrun", "--show-sdk-path"])
    version = capture([swift, "--version"])
    match = re.search(r"Swift version (\d+)\.(\d+)", version)
    if not match or int(match[1]) < 6:
        raise RuntimeError("Swift 6+ is required; selected compiler: " + version)
    sdk_version = json.loads((Path(sdk) / "SDKSettings.json").read_text())["Version"]
    if int(sdk_version.split(".")[0]) < 26:
        raise RuntimeError("A macOS 26+ SDK is required")
    try:
        developer = capture(["/usr/bin/xcode-select", "-p"], stderr=subprocess.DEVNULL)
        xcodebuild = Path(developer) / "usr/bin/xcodebuild"
        xcode_version = capture([str(xcodebuild), "-version"], stderr=subprocess.DEVNULL) if xcodebuild.is_file() else "unavailable"
    except (OSError, subprocess.CalledProcessError):
        xcode_version = "unavailable"
    revision = capture(["git", "-C", str(ROOT), "rev-parse", "HEAD"])
    dirty = bool(capture(["git", "-C", str(ROOT), "status", "--porcelain"]))
    return swift, sdk, {"compiler": version, "sdk": sdk_version, "sdkPath": sdk, "macOS": os_version,
                        "sourceRevision": revision + ("-dirty" if dirty else ""), "xcode": xcode_version}


def swift_command(swift, verb, configuration):
    cache = OUTPUT / "cache"
    return [swift, verb, "--package-path", str(ROOT), "--scratch-path", str(OUTPUT / "swift"),
            "--cache-path", str(cache / "packages"), "--config-path", str(cache / "config"),
            "--security-path", str(cache / "security"), "--disable-sandbox", "-c", configuration]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["build", "test", "stories", "qualify"])
    parser.add_argument("--configuration", choices=["debug", "release"], default="debug")
    parser.add_argument("--sign-identity", default=os.environ.get("STRATOSPHERE_SIGN_IDENTITY"))
    parser.add_argument("--sign-keychain", type=Path, default=os.environ.get("STRATOSPHERE_SIGN_KEYCHAIN") or None, help="Existing signing keychain; temporarily included during artifact signing")
    options, remaining = parser.parse_known_args()
    if options.action == "qualify":
        subprocess.run([sys.executable, str(ROOT / "E2E/native.py"), *remaining], check=True)
        return
    if remaining:
        parser.error("Unexpected arguments: " + " ".join(remaining))
    if options.sign_keychain and not options.sign_identity:
        parser.error("--sign-keychain requires --sign-identity")
    swift, sdk, metadata = toolchain()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.update({
        "SDKROOT": sdk, "MACOSX_DEPLOYMENT_TARGET": "26.0",
        "CLANG_MODULE_CACHE_PATH": str(OUTPUT / "cache" / "clang"),
        "SWIFT_MODULECACHE_PATH": str(OUTPUT / "cache" / "swift"),
    })
    (OUTPUT / "toolchain.json").write_text(json.dumps(metadata, indent=2) + "\n")
    command = swift_command(swift, "test" if options.action == "test" else "build", options.configuration)
    if options.action == "test":
        command.append("--disable-xctest")
    subprocess.run(command, check=True, env=environment)
    if options.action == "test":
        subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", str(ROOT / "Tests/ToolTests")], check=True)
        subprocess.run([sys.executable, str(ROOT / "Tools/check-docs.py")], check=True)
        return
    binaries = Path(capture([*swift_command(swift, "build", options.configuration), "--show-bin-path"], env=environment))
    with keychain_scope(options.sign_keychain if options.sign_identity else None) as selected_keychain:
        for name, identifier in [("StoryCatalog", "dev.stratosphere.catalog"), ("FixtureApp", "dev.stratosphere.fixture")]:
            assemble(binaries / name, OUTPUT / (name + ".app"), identifier, name, identity=options.sign_identity, keychain=selected_keychain)
        import shutil
        shutil.copy2(binaries / "EnvironmentProbe", OUTPUT / "EnvironmentProbe")
        if options.sign_identity:
            sign_artifact(OUTPUT / "EnvironmentProbe", options.sign_identity, selected_keychain, "dev.stratosphere.environment-probe")
    print("Artifacts: " + str(OUTPUT))
    if options.action == "stories":
        subprocess.run(["/usr/bin/open", str(OUTPUT / "StoryCatalog.app")], check=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
