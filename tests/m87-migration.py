#!/usr/bin/env python3
"""Exercise legacy retirement against an isolated home, never live launchd."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "migration", Path(__file__).resolve().parents[1] / "scripts/m87-remove-npm-daemon.py"
)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class MigrationTest(unittest.TestCase):
    def test_migration(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            package = home / ".local/lib/node_modules/@kunchenguid/m87"
            cli = package / "dist/cli.js"
            cli.parent.mkdir(parents=True)
            cli.write_text("legacy npm executable")
            shim = home / ".local/bin/m87"
            shim.parent.mkdir(parents=True)
            shim.symlink_to(cli)
            queue = home / ".m87/m87.sqlite"
            queue.parent.mkdir()
            queue.write_bytes(b"preserved queue")
            agents = home / "Library/LaunchAgents"
            agents.mkdir(parents=True)
            legacy = agents / "com.m87.daemon.legacy.plist"
            legacy.write_bytes(plistlib.dumps({
                "Label": "com.m87.daemon.legacy",
                "ProgramArguments": ["node", str(cli), "daemon", "run"],
            }))
            managed = agents / "com.m87.daemon.managed.plist"
            managed.write_bytes(plistlib.dumps({
                "Label": "com.m87.daemon.managed",
                "ProgramArguments": ["/nix/store/m87/bin/m87", "daemon", "run"],
            }))
            with patch.object(migration.subprocess, "run") as run:
                migration.migrate(home, dry_run=True)
                run.assert_not_called()
                self.assertTrue(legacy.exists() and cli.exists() and shim.exists())
                run.return_value = subprocess.CompletedProcess([], 1, stderr="permission denied")
                with self.assertRaises(RuntimeError):
                    migration.migrate(home)
                self.assertTrue(legacy.exists() and cli.exists() and shim.exists())
                run.return_value = subprocess.CompletedProcess([], 0, stderr="")
                migration.migrate(home)
                self.assertEqual(run.call_args.args[0], [
                    "/bin/launchctl", "bootout", "--wait",
                    f"gui/{migration.os.getuid()}/com.m87.daemon.legacy",
                ])
                self.assertFalse(legacy.exists() or package.exists() or shim.is_symlink())
                run.reset_mock()
                migration.migrate(home)
                run.assert_not_called()
            # An already-unloaded legacy job is safe to clean up. A replacement
            # bin link must not be removed, even if its target is currently absent.
            legacy.write_bytes(plistlib.dumps({
                "Label": "com.m87.daemon.legacy",
                "ProgramArguments": ["node", str(cli)],
            }))
            shim.symlink_to(home / "replacement/bin/m87")
            with patch.object(migration.subprocess, "run", return_value=
                              subprocess.CompletedProcess([], 3, stderr="No such process")):
                migration.migrate(home)
            self.assertFalse(legacy.exists())
            self.assertTrue(shim.is_symlink())
            self.assertTrue(managed.exists())
            self.assertEqual(queue.read_bytes(), b"preserved queue")


if __name__ == "__main__":
    unittest.main()
