#!/usr/bin/env python3
"""Retire only the legacy npm service, leaving the M87 queue untouched."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess


def migrate(home, launchctl="/bin/launchctl", dry_run=False):
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
    migrate(Path.home(), dry_run="DRY_RUN" in os.environ)
