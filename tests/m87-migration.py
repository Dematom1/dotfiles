#!/usr/bin/env python3
"""Exercise handoff and rollback with an isolated home and fake OS boundaries."""
import importlib.util
import io
import itertools
import json
import os
from pathlib import Path
import plistlib
import sqlite3
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


class Control:
    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def settimeout(self, seconds):
        pass

    def connect(self, address):
        pass

    def sendall(self, message):
        assert json.loads(message) == {"cmd": "ping"}

    def makefile(self, mode):
        return io.StringIO('{"ok":true,"version":"0.1.10"}\n')


class HandoffTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.package = self.home / ".local/lib/node_modules/@kunchenguid/m87"
        self.cli = self.package / "dist/cli.js"
        self.cli.parent.mkdir(parents=True)
        self.cli.write_text("legacy executable")
        self.shim = self.home / ".local/bin/m87"
        self.shim.parent.mkdir(parents=True)
        self.shim.symlink_to(self.cli)
        self.nix_root = self.home / "nix-m87"
        self.nix_package = self.nix_root / "libexec/m87/node_modules/@kunchenguid/m87"
        self.paths = {}
        for name in ("github", "gmail"):
            relative = Path(f"plugins/{name}/m87-src-{name}.js")
            target = self.nix_package / relative
            target.parent.mkdir(parents=True)
            target.write_text("replacement executable")
            target.chmod(0o755)
            self.paths[name] = (str(self.package / relative), str(target))
        self.database = self.home / ".m87/m87.sqlite"
        self.database.parent.mkdir()
        with sqlite3.connect(self.database) as db:
            db.execute("create table plugins (id text primary key, binary_path text, config_json text, last_sync_at text, last_error text, status text)")
            db.executemany("insert into plugins values (?, ?, ?, ?, ?, ?)", [
                (name, old, '{"retained":true}', "before", None, "active")
                for name, (old, new) in self.paths.items()
            ] + [("custom", "/custom/plugin", "{}", None, None, "active")])
            db.execute("create table queue (payload text)")
            db.execute("insert into queue values ('preserved queue')")
        self.agents = self.home / "Library/LaunchAgents"
        self.agents.mkdir(parents=True)
        self.legacy = self.agents / "com.m87.daemon.legacy.plist"
        self.legacy.write_bytes(plistlib.dumps({
            "Label": "com.m87.daemon.legacy",
            "ProgramArguments": [sys.executable, str(self.cli), "daemon", "run"],
        }))
        self.unrelated = self.agents / "com.m87.daemon.unrelated.plist"
        self.unrelated.write_bytes(plistlib.dumps({
            "Label": "com.m87.daemon.unrelated",
            "ProgramArguments": ["/nix/store/other/bin/m87", "daemon", "run"],
        }))
        self.source = self.home / "new.plist"
        self.source.write_bytes(plistlib.dumps({
            "Label": migration.LABEL,
            "ProgramArguments": [str(self.nix_root / "bin/m87"), "daemon", "run"],
        }))
        self.destination = self.agents / f"{migration.LABEL}.plist"
        self.active = {"com.m87.daemon.legacy": os.getpid()}
        (self.home / ".m87/daemon.pid").write_text(str(os.getpid()))
        self.calls = []
        self.failure = None
        for target, replacement in (
            ("subprocess.run", self.command),
            ("socket.socket", lambda *args: Control()),
            ("time.monotonic", lambda: next(self.clock)),
        ):
            mock = patch("migration." + target, replacement)
            # importlib loading doesn't register this module in sys.modules.
            sys.modules["migration"] = migration
            mock.start()
            self.addCleanup(mock.stop)
        self.clock = itertools.count(0, 100)

    def rows(self):
        with sqlite3.connect(self.database) as db:
            return dict(db.execute("select id, binary_path from plugins"))

    def command(self, args, **kwargs):
        args = list(map(str, args))
        self.calls.append(args)
        stdout, stderr, code = "", "", 0
        if args[0] == "/bin/launchctl":
            operation = args[1]
            if operation == "print":
                label = args[2].split("/", 2)[2]
                if label in self.active:
                    stdout = f"pid = {self.active[label]}\n"
                else:
                    code, stderr = 113, "Could not find service"
            elif operation == "bootout":
                label = args[-1].split("/", 2)[2]
                if self.failure == "bootout" and label.startswith("com.m87."):
                    code = 1
                else:
                    self.active.pop(label, None)
            elif operation == "bootstrap":
                plist = Path(args[-1])
                label = plistlib.loads(plist.read_bytes())["Label"]
                # Every bootstrap must happen without another queue owner.
                self.assertFalse(self.active)
                if label == migration.LABEL:
                    # Repointing must be committed before either service starts.
                    self.assertEqual(self.rows()["github"], self.paths["github"][1])
                    self.assertTrue(self.legacy.exists() and self.cli.exists())
                    if self.failure == "bootstrap":
                        code = 1
                    else:
                        self.active[label] = 4242
                        (self.home / ".m87/daemon.pid").write_text("4242")
                else:
                    self.assertEqual(self.rows()["github"], self.paths["github"][0])
                    self.active[label] = os.getpid()
                    (self.home / ".m87/daemon.pid").write_text(str(os.getpid()))
        elif args[-1] == "--version":
            stdout = "0.1.10\n"
            if self.failure == "version":
                code = 1
        elif args[-1] == "manifest":
            name = Path(args[0]).parent.name
            stdout = json.dumps({"plugin": {"id": name}})
        elif args[0] == "/bin/ps":
            stdout = str(self.nix_package / "dist/cli.js") + " daemon run"
            if self.failure == "identity":
                stdout = "wrong daemon run"
        elif args[-2:] == ["daemon", "status"]:
            stdout = "status: running\npid: 4242\n"
            if self.failure == "status":
                stdout = "status: not_running\n"
        elif args[-3:] == ["plugin", "sync", "github"]:
            self.assertEqual(self.active, {migration.LABEL: 4242})
            self.assertTrue(self.legacy.exists() and self.cli.exists() and self.shim.exists())
            with sqlite3.connect(self.database) as db:
                db.execute("update plugins set last_sync_at='after', last_error=? where id='github'",
                           ("sync failed" if self.failure == "sync" else None,))
        else:
            self.fail(f"Unexpected command: {args}")
        return subprocess.CompletedProcess(args, code, stdout, stderr)

    def migrate(self, **kwargs):
        migration.migrate(self.home, self.nix_root, self.source, **kwargs)

    def assert_preserved(self):
        self.assertTrue(self.legacy.exists() and self.cli.exists() and self.shim.exists())
        self.assertEqual(self.active, {"com.m87.daemon.legacy": os.getpid()})
        self.assertFalse(self.destination.exists())
        self.assertEqual(self.rows()["github"], self.paths["github"][0])
        self.assertEqual(self.rows()["gmail"], self.paths["gmail"][0])
        with sqlite3.connect(self.database) as db:
            self.assertEqual(db.execute("select * from queue").fetchall(), [("preserved queue",)])
            self.assertEqual(db.execute("select config_json from plugins where id='github'").fetchone(),
                             ('{"retained":true}',))

    def test_success_and_repeat(self):
        self.migrate()
        self.assertEqual(self.active, {migration.LABEL: 4242})
        self.assertFalse(self.package.exists() or self.legacy.exists() or self.shim.is_symlink())
        self.assertEqual(self.destination.read_bytes(), self.source.read_bytes())
        for name, (_, target) in self.paths.items():
            self.assertEqual(self.rows()[name], target)
        self.assertEqual(self.rows()["custom"], "/custom/plugin")
        self.assertTrue(self.unrelated.exists())
        self.calls.clear()
        self.migrate()
        self.assertEqual(self.calls, [])

    def test_dry_run(self):
        self.migrate(dry_run=True)
        self.assertEqual(self.calls, [])
        self.assert_preserved()

    def test_missing_plugin_preflight_preserves_running_worker(self):
        Path(self.paths["gmail"][1]).unlink()
        with self.assertRaises(RuntimeError):
            self.migrate()
        self.assert_preserved()

    def test_abort_and_rollback(self):
        for failure in ("version", "bootout", "bootstrap", "status", "identity", "sync"):
            with self.subTest(failure=failure):
                self.failure = failure
                self.clock = itertools.count(0, 100)
                with self.assertRaises(RuntimeError):
                    self.migrate()
                self.assert_preserved()

    def test_repoint_conflict_rolls_back_entire_transaction(self):
        updates = [(name, old, new) for name, (old, new) in self.paths.items()]
        updates[1] = ("gmail", "/unexpected/path", self.paths["gmail"][1])
        with self.assertRaises(RuntimeError):
            migration.repoint(self.database, updates)
        self.assert_preserved()

    def test_install_failure_restarts_old_worker(self):
        with patch.object(Path, "replace", side_effect=OSError("read-only destination")):
            with self.assertRaises(OSError):
                self.migrate()
        self.assert_preserved()

    def test_cleanup_failure_does_not_restart_a_second_worker(self):
        with patch.object(migration.shutil, "rmtree", side_effect=OSError("cleanup denied")):
            self.migrate()
        self.assertEqual(self.active, {migration.LABEL: 4242})
        self.assertTrue(self.package.exists())
        self.assertEqual(self.rows()["github"], self.paths["github"][1])

    def test_cleanup_retry_defers_to_managed_service_update(self):
        with patch.object(Path, "unlink", side_effect=OSError("cleanup denied")):
            self.migrate()
        original = self.destination.read_bytes()
        config = plistlib.loads(self.source.read_bytes())
        config["EnvironmentVariables"] = {"UPDATED": "1"}
        self.source.write_bytes(plistlib.dumps(config))
        before_files = {path: path.read_bytes() for path in self.home.rglob("*") if path.is_file()}
        before_paths = self.rows()
        self.calls.clear()

        self.migrate()

        self.assertEqual(self.active, {migration.LABEL: 4242})
        self.assertEqual(self.destination.read_bytes(), original)
        self.assertEqual(self.rows(), before_paths)
        self.assertTrue(self.shim.is_symlink())
        self.assertEqual(
            {path: path.read_bytes() for path in self.home.rglob("*") if path.is_file()},
            before_files,
        )
        self.assertFalse(any(call[1] in ("bootout", "bootstrap") for call in self.calls))
        self.assertFalse(any(call[-3:] == ["plugin", "sync", "github"] for call in self.calls))

    def test_missing_service_is_not_permission_failure(self):
        with patch.object(migration.subprocess, "run", return_value=
                          subprocess.CompletedProcess([], 1, "", "Operation not permitted")):
            with self.assertRaises(RuntimeError):
                self.migrate()
        self.assert_preserved()

    def test_unmanaged_pid_blocks_overlap(self):
        self.active.clear()
        with self.assertRaises(RuntimeError):
            self.migrate()
        self.assertTrue(self.legacy.exists() and self.cli.exists())
        self.assertEqual(self.rows()["github"], self.paths["github"][0])


if __name__ == "__main__":
    unittest.main()
