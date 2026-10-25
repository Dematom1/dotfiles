#!/usr/bin/env python3
"""Verify the real Nix worker, substituting only launchd's PID lookup.

Run: python3 tests/m87-worker.py <Nix m87 package>
"""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from unittest.mock import patch

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("migration", root / "scripts/m87-remove-npm-daemon.py")
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)
package = Path(sys.argv[1]).resolve()
cli = package / "bin/m87"
# macOS Unix socket paths are short; refuse to overwrite an existing directory.
home = root
state = home / ".m87"
state.mkdir()
worker = None
try:
    env = {"HOME": str(state), "PATH": os.environ["PATH"],
           "M87_STATE_DIR": str(state), "M87_SKIP_SHELLENV": "1", "M87_DAEMON": "1"}
    subprocess.run([cli, "init", "--yes", "--plugin", "skip", "--no-install-service"],
                   env=env, check=True, capture_output=True)
    version = subprocess.check_output([cli, "--version"], env=env, text=True).strip()
    with (state / "daemon.log").open("w") as log:
        worker = subprocess.Popen([cli, "daemon", "run"], env=env, stdout=log, stderr=log)
        deadline = time.monotonic() + 10
        while not (state / "daemon.sock").exists():
            if worker.poll() is not None or time.monotonic() >= deadline:
                raise AssertionError("Disposable daemon failed to start")
            time.sleep(0.1)
        pid = int((state / "daemon.pid").read_text())
        print(subprocess.check_output(["/bin/ps", "-p", str(pid), "-o", "command="], text=True).strip())
        with patch.object(migration, "service_pid", return_value=pid):
            migration.verify_worker(home, package, "unused", env, version, timeout=0)
        print("Real Nix worker passed process, socket and status verification")
finally:
    if worker is not None:
        worker.terminate()
        try:
            worker.wait(timeout=10)
        except subprocess.TimeoutExpired:
            worker.kill()
            worker.wait()
    shutil.rmtree(state)
