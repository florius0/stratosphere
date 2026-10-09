"""Assemble a native app without maintaining a second source build graph."""

from pathlib import Path
import argparse
import os
import plistlib
import shutil
import tempfile
import uuid

try:
    from Tools.signing import sign_artifact
except ModuleNotFoundError:
    from signing import sign_artifact


def assemble(executable, output, identifier, name, resources=None, identity=None, keychain=None):
    executable, output = Path(executable), Path(output)
    if not executable.is_file():
        raise FileNotFoundError(executable)
    if output.is_symlink() or output.suffix != ".app":
        raise ValueError("Output must be a regular .app directory, not a symlink")
    if not name or Path(name).name != name or name in (".", ".."):
        raise ValueError("Executable name must be a single path component")
    if resources is not None and not Path(resources).is_dir():
        raise FileNotFoundError(resources)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bundle-", dir=output.parent) as staging:
        app = Path(staging) / output.name
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        shutil.copy2(executable, contents / "MacOS" / name)
        os.chmod(contents / "MacOS" / name, 0o755)
        metadata = {
            "CFBundleExecutable": name,
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "26.0",
            "NSHighResolutionCapable": True,
            "NSPrincipalClass": "NSApplication",
        }
        (contents / "Info.plist").write_bytes(plistlib.dumps(metadata, sort_keys=True))
        destination = contents / "Resources"
        if resources is None:
            destination.mkdir()
        else:
            shutil.copytree(resources, destination)
        if identity:
            sign_artifact(app, identity, keychain)
        backup = output.parent / (".previous-" + uuid.uuid4().hex)
        replaced = output.exists()
        if replaced:
            output.rename(backup)
        try:
            app.rename(output)
        except BaseException:
            if replaced:
                backup.rename(output)
            raise
        if replaced:
            shutil.rmtree(backup)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--identifier", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--resources", type=Path)
    parser.add_argument("--identity", help="Persistent development or Developer ID identity; '-' is ad hoc")
    parser.add_argument("--keychain", type=Path, default=os.environ.get("STRATOSPHERE_SIGN_KEYCHAIN") or None, help="Existing signing keychain; temporarily included only during signing")
    options = parser.parse_args()
    if options.keychain and not options.identity:
        parser.error("--keychain requires --identity")
    assemble(options.executable, options.output, options.identifier, options.name, options.resources, options.identity, options.keychain)


if __name__ == "__main__":
    main()
