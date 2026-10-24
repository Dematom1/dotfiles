#!/usr/bin/env python3
"""Verify dry-run inventory with the real Claude CLI preserves persisted state."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).absolute().parent.parent
claude = shutil.which("claude")
if claude is None:
    sys.exit("Required tool missing from PATH: claude")

with tempfile.TemporaryDirectory(prefix=".test-claude-", dir=repo) as temporary:
    root = Path(temporary)
    home = root / "home"
    plugins = home / ".claude/plugins"
    plugins.mkdir(parents=True)
    bin_dir = root / "bin"
    bin_dir.mkdir()
    (bin_dir / "claude").symlink_to(claude)
    env = {"HOME": str(home), "PATH": f"{bin_dir}:/usr/bin:/bin",
           "TMPDIR": str(root)}
    (home / ".claude.json").write_text('{"mcpServers": {}}\n')
    (home / ".claude/settings.json").write_text(json.dumps({
        "enabledPlugins": {"retired@fixture": True},
    }))
    (plugins / "installed_plugins.json").write_text(json.dumps({
        "version": 2, "plugins": {"retired@fixture": [{
            "scope": "user", "installPath": str(plugins / "cache/fixture/retired/1"),
            "version": "1", "installedAt": "2026-01-01T00:00:00.000Z",
            "lastUpdated": "2026-01-01T00:00:00.000Z",
        }]},
    }))
    (plugins / "known_marketplaces.json").write_text(json.dumps({
        "fixture": {"source": {"source": "github", "repo": "example/fixture"},
                    "installLocation": str(plugins / "marketplaces/fixture"),
                    "lastUpdated": "2026-01-01T00:00:00.000Z"},
    }))

    def snapshot():
        return {str(path.relative_to(home)): path.read_bytes()
                for path in home.rglob("*") if path.is_file()}

    before = snapshot()
    result = subprocess.run([
        sys.executable, str(repo / "scripts/agent-tooling-reconcile.py"),
        "--manifest", str(repo / "agent-tooling.json"), "--dry-run",
    ], env=env, cwd=home, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, result.stderr
    after = snapshot()
    changed = sorted(name for name in before.keys() | after.keys()
                     if before.get(name) != after.get(name))
    assert not changed, f"Dry-run changed persisted files: {changed}"
    assert "plugin uninstall retired@fixture --scope user" in result.stdout, result.stdout
    assert "plugin marketplace remove fixture" in result.stdout, result.stdout
    assert "plugin install --scope user ponytail@ponytail" in result.stdout, result.stdout
    assert "skipped Claude plugins" not in result.stderr, result.stderr

print("Real Claude dry-run preserves configuration and inventories installed plugins")
