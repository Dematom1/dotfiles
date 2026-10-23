#!/usr/bin/env python3
"""Execute evaluated postActivation shell with filesystem and ownership fixtures."""

import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


activation = sys.stdin.read()
if not activation.strip():
    raise SystemExit("FAIL: no evaluated activation script supplied")


def executable(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\n" + body + "\n")
    path.chmod(0o755)


def check(case):
    with tempfile.TemporaryDirectory(prefix="av-sync-", dir=Path(__file__).parent) as tmp:
        root = Path(tmp).resolve()
        app = root / "Automic Vault.app"
        bundled = app / "Contents/MacOS/av"
        target = root / "usr/local/bin/av"
        executable(bundled, 'echo 4.20.1')
        if case != "first-install":
            executable(target, 'echo 3.15.1')
        if case == "same-version-different-bytes":
            executable(target, 'printf "%s\\n" 4.20.1')
        if case == "missing-bundle":
            bundled.unlink()
        if case == "empty-version":
            executable(bundled, 'exit 0')
        if case in ("target-version-failure", "target-version-mismatch"):
            result = "exit 7" if case == "target-version-failure" else "echo 3.15.1; exit 0"
            executable(bundled, f'if [ "$0" = {shlex.quote(str(target))} ]; then {result}; fi\necho 4.20.1')

        script = activation.replace("/Applications/Automic Vault.app", str(app))
        script = script.replace("/usr/local/bin/av", str(target))
        script = script.replace("-o root -g wheel", f"-o {os.getuid()} -g {os.getgid()}")
        if case == "corrupt-install":
            installer = root / "install"
            executable(installer, f'printf "corrupt\\n" > {shlex.quote(str(target))}')
            script = script.replace("/usr/bin/install", shlex.quote(str(installer)))

        result = subprocess.run(["/bin/sh", "-c", script], capture_output=True, text=True)
        success = case in ("first-install", "stale-target", "same-version-different-bytes")
        if success:
            assert result.returncode == 0, f"{case}: {result.stderr}"
            assert target.read_bytes() == bundled.read_bytes(), f"{case}: target differs from bundle"
            assert os.access(target, os.X_OK), f"{case}: target is not executable"
            again = subprocess.run(["/bin/sh", "-c", script], capture_output=True, text=True)
            assert again.returncode == 0, f"{case}: repeated activation failed: {again.stderr}"
            assert target.read_bytes() == bundled.read_bytes(), f"{case}: repeated activation changed target"
        else:
            assert result.returncode != 0, f"{case}: activation accepted a verification failure"
        print(f"PASS: {case}")


for scenario in (
    "first-install",
    "stale-target",
    "same-version-different-bytes",
    "missing-bundle",
    "empty-version",
    "target-version-failure",
    "target-version-mismatch",
    "corrupt-install",
):
    check(scenario)
