#!/usr/bin/env python3
"""Exclusive, rollback-safe handoff from the npm worker to Home Manager."""
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import time


LABEL = "org.nix-community.home.m87"


def run(args, *, env=None, timeout=30):
    result = subprocess.run([str(arg) for arg in args], env=env, input="",
                            capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        # Do not echo command output: launchctl can include service credentials.
        raise RuntimeError(f"{Path(args[0]).name} {args[1]} failed (exit {result.returncode})")
    return result.stdout


def service_pid(launchctl, label):
    result = subprocess.run([launchctl, "print", f"gui/{os.getuid()}/{label}"],
                            capture_output=True, text=True, timeout=15)
    if result.returncode:
        if "Could not find service" in result.stderr:
            return None
        raise RuntimeError(f"Cannot inspect launchd job {label}")
    match = re.search(r"^\s*pid = (\d+)\s*$", result.stdout, re.MULTILINE)
    return int(match[1]) if match else 0  # Loaded but not running is not absent.


def bootout(launchctl, label):
    if service_pid(launchctl, label) is not None:
        run([launchctl, "bootout", "--wait", f"gui/{os.getuid()}/{label}"])
    if service_pid(launchctl, label) is not None:
        raise RuntimeError(f"Job remained loaded: {label}")


def plugin_paths(database, package, nix_package):
    with sqlite3.connect(f"{database.as_uri()}?mode=ro", uri=True) as db:
        updates = []
        for plugin_id, binary in db.execute("select id, binary_path from plugins"):
            path = Path(binary).resolve()
            if path.is_relative_to(package.resolve()):
                target = nix_package / path.relative_to(package.resolve())
                if not target.is_file() or not os.access(target, os.X_OK):
                    raise RuntimeError(f"Missing Nix executable for plugin {plugin_id}")
                if not target.resolve().is_relative_to(nix_package.resolve()):
                    raise RuntimeError(f"Plugin escapes Nix package: {plugin_id}")
                manifest = json.loads(run([target, "manifest"]))
                if manifest.get("plugin", {}).get("id") != plugin_id:
                    raise RuntimeError(f"Nix plugin identity mismatch: {plugin_id}")
                updates.append((plugin_id, binary, str(target)))
        return updates


def repoint(database, updates, *, restore=False):
    with sqlite3.connect(f"{database.as_uri()}?mode=rw", uri=True) as db:
        db.execute("begin immediate")
        for plugin_id, old, new in updates:
            before, after = (new, old) if restore else (old, new)
            changed = db.execute("update plugins set binary_path=? where id=? and binary_path=?",
                                 (after, plugin_id, before)).rowcount
            if changed != 1:
                raise RuntimeError(f"Plugin path changed during migration: {plugin_id}")
        for plugin_id, old, new in updates:
            expected = old if restore else new
            if db.execute("select binary_path from plugins where id=?", (plugin_id,)).fetchone() != (expected,):
                raise RuntimeError(f"Plugin path verification failed: {plugin_id}")


def verify_worker(home, nix_root, launchctl, env, version, timeout=30):
    deadline = time.monotonic() + timeout
    while True:
        try:
            pid = service_pid(launchctl, LABEL)
            if not pid or int((home / ".m87/daemon.pid").read_text()) != pid:
                raise RuntimeError("Managed PID does not own M87 state")
            command = run(["/bin/ps", "-p", str(pid), "-o", "command="])
            cli = nix_root / "libexec/m87/node_modules/@kunchenguid/m87/dist/cli.js"
            if str(cli) not in command or "daemon run" not in command:
                raise RuntimeError("Managed PID is not the Nix daemon")
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as control:
                control.settimeout(3)
                control.connect(str(home / ".m87/daemon.sock"))
                control.sendall(b'{"cmd":"ping"}\n')
                with control.makefile("r") as reply:
                    ping = json.loads(reply.readline(65536))
            if not ping.get("ok") or ping.get("version") != version:
                raise RuntimeError("Managed control socket did not answer correctly")
            status = run([nix_root / "bin/m87", "daemon", "status"], env=env)
            fields = dict(line.split(": ", 1) for line in status.splitlines() if ": " in line)
            if fields.get("status") != "running" or fields.get("pid") != str(pid):
                raise RuntimeError("m87 daemon status did not confirm managed PID")
            return
        except (OSError, ValueError, RuntimeError):
            if time.monotonic() >= deadline:
                raise RuntimeError("Managed M87 daemon did not become healthy") from None
            time.sleep(0.25)


def verify_sync(database, nix_root, env):
    with sqlite3.connect(f"{database.as_uri()}?mode=ro", uri=True) as db:
        before = db.execute("select last_sync_at from plugins where id='github'").fetchone()
    if before is None:
        raise RuntimeError("GitHub plugin is not installed")
    run([nix_root / "bin/m87", "plugin", "sync", "github"], env=env, timeout=60)
    with sqlite3.connect(f"{database.as_uri()}?mode=ro", uri=True) as db:
        result = db.execute("select last_sync_at, last_error, status from plugins where id='github'").fetchone()
    if not result or not result[0] or result[0] == before[0] or result[1] or result[2] != "active":
        raise RuntimeError("GitHub sync did not complete successfully")


def migrate(home, nix_root, managed_source, launchctl="/bin/launchctl", dry_run=False):
    home = home.absolute()
    package = home / ".local/lib/node_modules/@kunchenguid/m87"
    cli = package / "dist/cli.js"
    legacy = []
    for plist in sorted((home / "Library/LaunchAgents").glob("com.m87.daemon.*.plist")):
        config = plistlib.loads(plist.read_bytes())
        label = config.get("Label", "")
        if label.startswith("com.m87.daemon.") and str(cli) in config.get("ProgramArguments", []):
            legacy.append((plist, label))
    if not legacy and not package.exists():
        return  # Normal rebuilds remain Home Manager's responsibility.
    if dry_run:
        print("Would preflight, repoint plugins, cut over with rollback, then retire npm M87")
        return

    database = home / ".m87/m87.sqlite"
    nix_package = nix_root / "libexec/m87/node_modules/@kunchenguid/m87"
    new_bytes = managed_source.read_bytes()
    new_config = plistlib.loads(new_bytes)
    if new_config.get("Label") != LABEL:
        raise RuntimeError("Unexpected managed M87 label")
    env = {**os.environ, **new_config.get("EnvironmentVariables", {}),
           "HOME": str(home), "M87_STATE_DIR": str(home / ".m87"), "M87_SKIP_SHELLENV": "1"}
    version = run([nix_root / "bin/m87", "--version"], env=env).strip()
    if not version:
        raise RuntimeError("Nix M87 did not report its version")
    updates = plugin_paths(database, package, nix_package)
    loaded_legacy = [(path, label) for path, label in legacy if service_pid(launchctl, label) is not None]
    if len(loaded_legacy) > 1:
        raise RuntimeError("Multiple legacy M87 services are loaded; refusing ambiguous rollback")
    for plist, _ in loaded_legacy:
        args = plistlib.loads(plist.read_bytes()).get("ProgramArguments", [])
        if not args or not Path(args[0]).is_absolute() or not os.access(args[0], os.X_OK) or not cli.is_file():
            raise RuntimeError("Legacy M87 executable is unavailable for rollback")
    managed_pid = service_pid(launchctl, LABEL)
    loaded_managed = managed_pid is not None
    pid_file = home / ".m87/daemon.pid"
    if pid_file.exists():
        pid = int(pid_file.read_text())
        if pid <= 0:
            raise RuntimeError("Invalid M87 PID file")
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            pass
        else:
            known = [service_pid(launchctl, label) for _, label in loaded_legacy] + [managed_pid]
            if pid not in known:
                raise RuntimeError("An unmanaged M87 worker owns the state; refusing overlap")
    if loaded_managed and loaded_legacy:
        raise RuntimeError("Both M87 services are already loaded; refusing ambiguous handoff")
    destination = home / "Library/LaunchAgents" / f"{LABEL}.plist"
    original = destination.read_bytes() if destination.exists() else None
    if loaded_managed and original != new_bytes:
        print("WARNING: managed M87 service update pending; deferring npm cleanup", file=sys.stderr)
        return

    paths_changed = False
    installed = False
    try:
        repoint(database, updates)
        paths_changed = True
        for _, label in loaded_legacy:
            bootout(launchctl, label)
        if not loaded_managed:
            # Do not truncate an existing read-only Home Manager plist in place.
            temporary = destination.with_suffix(".migration")
            temporary.write_bytes(new_bytes)
            temporary.chmod(0o444)
            temporary.replace(destination)
            installed = True
            run([launchctl, "bootstrap", f"gui/{os.getuid()}", destination])
        verify_worker(home, nix_root, launchctl, env, version)
        verify_sync(database, nix_root, env)
        verify_worker(home, nix_root, launchctl, env, version)
        with sqlite3.connect(f"{database.as_uri()}?mode=ro", uri=True) as db:
            for (binary,) in db.execute("select binary_path from plugins"):
                if Path(binary).resolve().is_relative_to(package.resolve()):
                    raise RuntimeError("M87 still references npm plugin executables")
    except BaseException:
        # Never resume the old worker until the replacement is confirmed unloaded.
        if installed:
            bootout(launchctl, LABEL)
        if paths_changed:
            repoint(database, updates, restore=True)
        if installed:
            if original is None:
                destination.unlink(missing_ok=True)
            else:
                temporary = destination.with_suffix(".rollback")
                temporary.write_bytes(original)
                temporary.chmod(0o444)
                temporary.replace(destination)
        for plist, label in loaded_legacy:
            if service_pid(launchctl, label) is None:
                run([launchctl, "bootstrap", f"gui/{os.getuid()}", plist])
            if not service_pid(launchctl, label):
                raise RuntimeError(f"Legacy M87 rollback did not restart {label}")
        raise

    # Commit point: only the healthy managed worker owns the queue. Cleanup is
    # retryable and nonfatal; a deletion error must not restart a second worker.
    print("Managed M87 daemon and GitHub sync verified; retiring npm installation")
    try:
        for plist, _ in legacy:
            plist.unlink()
        shim = home / ".local/bin/m87"
        if shim.is_symlink() and shim.resolve() == cli.resolve():
            shim.unlink()
        if package.exists():
            shutil.rmtree(package)
    except OSError as error:
        print(f"WARNING: managed daemon is healthy; npm cleanup will retry: {error}", file=sys.stderr)


if __name__ == "__main__":
    migrate(Path.home(), Path(sys.argv[1]), Path(sys.argv[2]), dry_run="DRY_RUN" in os.environ)
