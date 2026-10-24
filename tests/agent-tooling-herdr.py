#!/usr/bin/env python3
"""Check reconciliation convergence with the real Herdr integration installer."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).absolute().parent.parent
executables = {name: shutil.which(name) for name in ("herdr", "just")}
for name, executable in executables.items():
    if executable is None:
        sys.exit(f"Required tool missing from PATH: {name}")

with tempfile.TemporaryDirectory(prefix=".test-herdr-", dir=repo) as temporary:
    root = Path(temporary)
    home = root / "home"
    home.mkdir()
    bin_dir = root / "bin"
    bin_dir.mkdir()
    for name, executable in executables.items():
        (bin_dir / name).symlink_to(executable)
    env = {"HOME": str(home), "PATH": f"{bin_dir}:/usr/bin:/bin"}
    command = [sys.executable, str(repo / "scripts/agent-tooling-reconcile.py"),
               "--manifest", str(repo / "agent-tooling.json")]

    def reconcile():
        result = subprocess.run(command, env=env, cwd=home, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        assert "failed:" not in result.stderr and "exited " not in result.stderr, result.stderr

    def snapshot():
        return {str(path.relative_to(home)): path.read_bytes()
                for path in home.rglob("*") if path.is_file()}

    reconcile()
    for relative in (".claude/settings.json", ".codex/hooks.json"):
        hooks = json.loads((home / relative).read_text())["hooks"]["SessionStart"]
        commands = [hook["command"] for group in hooks for hook in group["hooks"]]
        assert any("herdr-agent-state.sh" in command for command in commands), commands
    first = snapshot()
    backup_root = home / ".local/state/dotfiles/agent-tooling-backups"
    backups = sorted(backup_root.glob("*"))
    reconcile()
    second = snapshot()
    changed = sorted(name for name in first.keys() | second.keys()
                     if first.get(name) != second.get(name))
    assert not changed, f"Second reconciliation changed files: {changed}"
    assert sorted(backup_root.glob("*")) == backups, "Second reconciliation retained a new backup"

print("Real Herdr reconciliation converges without new backups")
