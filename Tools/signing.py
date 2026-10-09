"""Sign with an existing identity while preserving the user's keychain search list."""

from contextlib import contextmanager
from pathlib import Path
import shlex
import subprocess


@contextmanager
def keychain_scope(keychain=None):
    if keychain is None:
        yield None
        return
    selected = Path(keychain).expanduser().resolve()
    if not selected.is_file():
        raise RuntimeError("Signing keychain does not exist: " + str(selected))
    command = ["/usr/bin/security", "list-keychains", "-d", "user"]
    original = shlex.split(subprocess.check_output(command, text=True))
    if str(selected) in original:
        yield selected
        return
    try:
        subprocess.run([*command, "-s", str(selected), *original], check=True)
        yield selected
    finally:
        subprocess.run([*command, "-s", *original], check=True)


def sign_artifact(path, identity, keychain=None, identifier=None):
    with keychain_scope(keychain) as selected:
        command = ["/usr/bin/codesign", "--force", "--options", "runtime"]
        if identifier:
            command += ["--identifier", identifier]
        if selected is not None:
            command += ["--keychain", str(selected)]
        command += ["--sign", identity, str(path)]
        subprocess.run(command, check=True)
