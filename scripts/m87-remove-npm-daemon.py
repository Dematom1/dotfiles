#!/usr/bin/env python3
"""Retire only the legacy npm service, leaving the M87 queue untouched."""
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import sys


def migrate(home, nix_package, launchctl="/bin/launchctl", dry_run=False):
    package = home / ".local/lib/node_modules/@kunchenguid/m87"
    cli = package / "dist/cli.js"
    for plist in sorted((home / "Library/LaunchAgents").glob("com.m87.daemon.*.plist")):
        with plist.open("rb") as source:
            config = plistlib.load(source)
        label = config.get("Label", "")
        if not label.startswith("com.m87.daemon.") or str(cli) not in config.get("ProgramArguments", []):
            continue
        print(f"Retiring npm daemon {label}")
        if dry_run:
            continue
        result = subprocess.run(
            [launchctl, "bootout", "--wait", f"gui/{os.getuid()}/{label}"],
            capture_output=True, text=True,
        )
        if result.returncode and "No such process" not in result.stderr:
            raise RuntimeError(f"Could not stop {label}: {result.stderr.strip()}")
        plist.unlink()

    states = {home / ".m87", Path(os.environ.get("M87_STATE_DIR") or home / ".m87")}
    for state in sorted(states):
        database = state / "m87.sqlite"
        if not database.exists():
            continue
        mode = "ro" if dry_run else "rw"
        with sqlite3.connect(f"{database.resolve().as_uri()}?mode={mode}", uri=True) as db:
            replacements = []
            for plugin_id, binary in db.execute("select id, binary_path from plugins"):
                path = Path(binary)
                if not path.is_relative_to(package):
                    continue
                replacement = nix_package / path.relative_to(package)
                if not replacement.is_file():
                    raise RuntimeError(f"Missing Nix executable for {plugin_id}: {replacement}")
                print(f"Repointing plugin {plugin_id} to {replacement}")
                replacements.append((str(replacement), plugin_id))
            if not dry_run:
                db.executemany("update plugins set binary_path=? where id=?", replacements)

    # npm's bin link must still point at this package, not a replacement install.
    shim = home / ".local/bin/m87"
    if shim.is_symlink() and shim.resolve() == cli.resolve():
        print(f"Removing npm shim {shim}")
        if not dry_run:
            shim.unlink()
    if package.exists():
        print(f"Removing npm package {package}")
        if not dry_run:
            shutil.rmtree(package)


if __name__ == "__main__":
    migrate(Path.home(), Path(sys.argv[1]), dry_run="DRY_RUN" in os.environ)
