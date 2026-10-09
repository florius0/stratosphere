import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("bundle_signing_cases", ROOT / "Tools/bundle.py")
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)
from Tools.signing import keychain_scope, sign_artifact


class SigningBoundary:
    def __init__(self, original, keychain=None, fail=False):
        self.original = list(original)
        self.search_list = list(original)
        self.keychain = str(keychain) if keychain else None
        self.fail = fail
        self.commands = []

    def check_output(self, command, **kwargs):
        self.commands.append(list(command))
        if command != ["/usr/bin/security", "list-keychains", "-d", "user"]:
            raise AssertionError("Unexpected external command: " + repr(command))
        return "\n".join(json.dumps(path) for path in self.search_list)

    def run(self, command, **kwargs):
        command = list(command)
        self.commands.append(command)
        if command[:5] == ["/usr/bin/security", "list-keychains", "-d", "user", "-s"]:
            self.search_list = command[5:]
        elif command[0] == "/usr/bin/codesign":
            if self.keychain:
                if self.keychain not in self.search_list:
                    raise AssertionError("Selected keychain was not present during signing")
                if "--keychain" not in command or command[command.index("--keychain") + 1] != self.keychain:
                    raise AssertionError("Signer did not select the requested keychain")
            if self.fail:
                raise subprocess.CalledProcessError(1, command, stderr="synthetic signing failure")
        else:
            raise AssertionError("Unexpected external command: " + repr(command))
        return subprocess.CompletedProcess(command, 0)


class LocalSigningTests(unittest.TestCase):
    def invoke_bundle(self, root, boundary, use_keychain=True, via_environment=False):
        source = root / "Fixture"
        source.write_bytes(b"synthetic executable")
        source.chmod(0o755)
        arguments = ["bundle.py", str(source), str(root / "Fixture.app"), "--identifier", "dev.stratosphere.fixture",
                     "--name", "Fixture", "--identity", "Synthetic Test Identity"]
        if use_keychain and not via_environment:
            arguments += ["--keychain", boundary.keychain]
        with patch.dict(os.environ), patch.object(sys, "argv", arguments), patch.object(subprocess, "check_output", side_effect=boundary.check_output), \
                patch.object(subprocess, "run", side_effect=boundary.run), contextlib.redirect_stderr(io.StringIO()):
            os.environ.pop("STRATOSPHERE_SIGN_KEYCHAIN", None)
            if via_environment:
                os.environ["STRATOSPHERE_SIGN_KEYCHAIN"] = boundary.keychain
            try:
                bundle.main()
            except SystemExit as error:
                self.fail("Bundle CLI rejected keychain selection: " + str(error.code))
        return source

    def test_cli_selects_existing_keychain_then_restores_ordered_search_list(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            keychain = root / "Local Test.keychain-db"
            keychain.touch()
            boundary = SigningBoundary([str(root / "Original Keychain.keychain-db"), str(root / "Other.keychain-db")], keychain)
            source = self.invoke_bundle(root, boundary)
            self.assertEqual(boundary.search_list, boundary.original)
            self.assertEqual(source.read_bytes(), b"synthetic executable")
            self.assertEqual((root / "Fixture.app/Contents/MacOS/Fixture").read_bytes(), source.read_bytes())
            sign = next(command for command in boundary.commands if command[0] == "/usr/bin/codesign")
            self.assertEqual(sign[sign.index("--sign") + 1], "Synthetic Test Identity")
            self.assertEqual(boundary.commands[-1], ["/usr/bin/security", "list-keychains", "-d", "user", "-s", *boundary.original])

    def test_search_list_restored_and_previous_bundle_retained_after_signing_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            keychain = root / "Test.keychain-db"
            keychain.touch()
            output = root / "Fixture.app"
            output.mkdir()
            (output / "previous").write_text("preserve")
            boundary = SigningBoundary([str(root / "Original Keychain.keychain-db")], keychain, fail=True)
            with self.assertRaises(subprocess.CalledProcessError):
                self.invoke_bundle(root, boundary)
            self.assertEqual(boundary.search_list, boundary.original)
            self.assertEqual((output / "previous").read_text(), "preserve")
            self.assertEqual(boundary.commands[-1], ["/usr/bin/security", "list-keychains", "-d", "user", "-s", *boundary.original])

    def test_environment_selects_existing_keychain_without_cli_flag(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            keychain = root / "Test.keychain-db"
            keychain.touch()
            boundary = SigningBoundary([str(root / "Original.keychain-db")], keychain)
            self.invoke_bundle(root, boundary, via_environment=True)
            self.assertEqual(boundary.search_list, boundary.original)

    def test_missing_keychain_is_refused_before_search_list_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            boundary = SigningBoundary([], root / "missing.keychain-db")
            with self.assertRaisesRegex(RuntimeError, "does not exist"):
                self.invoke_bundle(root, boundary)
            self.assertEqual(boundary.commands, [])

    def test_batch_context_restores_search_list_after_later_artifact_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            keychain = root / "Test.keychain-db"
            keychain.touch()
            boundary = SigningBoundary([str(root / "Original.keychain-db")], keychain)
            source = root / "Source"
            source.write_bytes(b"synthetic")
            with patch.object(subprocess, "check_output", side_effect=boundary.check_output), patch.object(subprocess, "run", side_effect=boundary.run):
                with self.assertRaises(subprocess.CalledProcessError):
                    with keychain_scope(keychain) as selected:
                        bundle.assemble(source, root / "StoryCatalog.app", "dev.stratosphere.catalog", "StoryCatalog", identity="Synthetic", keychain=selected)
                        bundle.assemble(source, root / "FixtureApp.app", "dev.stratosphere.fixture", "FixtureApp", identity="Synthetic", keychain=selected)
                        boundary.fail = True
                        sign_artifact(source, "Synthetic", selected, "dev.stratosphere.environment-probe")
            self.assertEqual(boundary.search_list, boundary.original)
            changes = [command for command in boundary.commands if command[:5] == ["/usr/bin/security", "list-keychains", "-d", "user", "-s"]]
            self.assertEqual(changes, [
                ["/usr/bin/security", "list-keychains", "-d", "user", "-s", str(keychain), *boundary.original],
                ["/usr/bin/security", "list-keychains", "-d", "user", "-s", *boundary.original],
            ])
            probe_sign = [command for command in boundary.commands if command[0] == "/usr/bin/codesign"][-1]
            self.assertEqual(probe_sign[probe_sign.index("--identifier") + 1], "dev.stratosphere.environment-probe")

    def test_preexisting_membership_needs_no_search_list_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            keychain = root / "Test.keychain-db"
            keychain.touch()
            boundary = SigningBoundary([str(root / "Original.keychain-db"), str(keychain)], keychain)
            self.invoke_bundle(root, boundary)
            self.assertEqual(boundary.search_list, boundary.original)
            self.assertFalse(any(command[0] == "/usr/bin/security" and "-s" in command for command in boundary.commands))

    def test_build_help_exposes_optional_sign_keychain_without_building(self):
        result = subprocess.run([sys.executable, str(ROOT / "Tools/build.py"), "--help"], capture_output=True, text=True, check=True)
        self.assertIn("--sign-keychain", result.stdout)

    def test_identity_without_keychain_preserves_existing_behavior(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            boundary = SigningBoundary([])
            self.invoke_bundle(root, boundary, use_keychain=False)
            self.assertEqual(len(boundary.commands), 1)
            self.assertEqual(boundary.commands[0][0], "/usr/bin/codesign")
            self.assertNotIn("--keychain", boundary.commands[0])


if __name__ == "__main__":
    unittest.main()
