import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[2] / "E2E/vm.py"
spec = importlib.util.spec_from_file_location("vm", MODULE)
vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vm)


class GuestCleanupTests(unittest.TestCase):
    def test_final_wait_timeout_still_deletes_owned_clone_and_closes_log(self):
        class StuckProcess:
            def wait(self, timeout):
                raise subprocess.TimeoutExpired("controlled-owned-process", timeout)

            def terminate(self):
                pass

            def kill(self):
                pass

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / "tart"
            tool.write_text("""#!/usr/bin/env python3
import os, pathlib, shutil, sys
root = pathlib.Path(os.environ['TART_HOME'])
action, *args = sys.argv[1:]
if action == 'clone':
 (root / args[1]).mkdir()
elif action == 'delete':
 shutil.rmtree(root / args[0])
""")
            tool.chmod(0o755)
            (root / "prepared").mkdir()
            guest = vm.Guest("prepared", "owned-clone", str(tool), {**os.environ, "TART_HOME": str(root)}, root / "run.log")
            guest.__enter__()
            self.addCleanup(guest.log.close)
            guest.process = StuckProcess()
            try:
                guest.cleanup()
            except subprocess.TimeoutExpired:
                pass
            self.assertFalse((root / "owned-clone").exists())
            self.assertTrue((root / "prepared").exists())
            self.assertTrue(guest.log.closed)
            self.assertTrue(guest.cleanup_errors)
            self.assertIn("controlled-owned-process", (root / "run.log").read_text())

    def test_failed_scenario_deletes_only_owned_clone(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / "tart"
            tool.write_text("""#!/usr/bin/env python3
import os, pathlib, shutil, sys
root = pathlib.Path(os.environ['TART_HOME'])
action, *args = sys.argv[1:]
if action == 'clone':
 (root / args[1]).mkdir()
elif action == 'stop':
 pass
elif action == 'delete':
 shutil.rmtree(root / args[0])
""")
            tool.chmod(0o755)
            home = root / "images"
            home.mkdir()
            (home / "prepared").mkdir()
            environment = {**os.environ, "TART_HOME": str(home)}
            with self.assertRaisesRegex(RuntimeError, "scenario failed"):
                with vm.Guest("prepared", "owned-clone", str(tool), environment, root / "run.log"):
                    self.assertTrue((home / "owned-clone").is_dir())
                    raise RuntimeError("scenario failed")
            self.assertTrue((home / "prepared").is_dir())
            self.assertFalse((home / "owned-clone").exists())

    def test_clone_failure_still_cleans_partial_owned_disk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tool = root / "tart"
            tool.write_text("""#!/usr/bin/env python3
import os, pathlib, shutil, sys
root = pathlib.Path(os.environ['TART_HOME'])
action, *args = sys.argv[1:]
if action == 'clone':
 (root / args[1]).mkdir()
 sys.exit(1)
elif action == 'delete':
 shutil.rmtree(root / args[0])
""")
            tool.chmod(0o755)
            environment = {**os.environ, "TART_HOME": str(root)}
            with self.assertRaises(Exception):
                with vm.Guest("prepared", "partial-clone", str(tool), environment, root / "run.log"):
                    self.fail("A failed clone cannot run scenarios")
            self.assertFalse((root / "partial-clone").exists())


if __name__ == "__main__":
    unittest.main()
