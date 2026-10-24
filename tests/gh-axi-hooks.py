#!/usr/bin/env python3
"""Execute persisted SessionStart hooks with a stale gh-axi first on PATH."""
import json
import os
from pathlib import Path
import subprocess
import tempfile


repo = Path(__file__).absolute().parent.parent
with tempfile.TemporaryDirectory(prefix=".gh-hooks-", dir=repo) as directory:
    root = Path(directory)
    home = root / "home with spaces"
    # The Home Manager profile copy; USER below keeps the real /etc/profiles one out.
    managed = home / ".nix-profile/bin/gh-axi"
    stale = root / "stale/gh-axi"
    targets = [home / ".claude/settings.json", home / ".codex/hooks.json"]
    unrelated = {"type": "command", "command": "echo unrelated", "timeout": 15}
    for target in targets:
        target.parent.mkdir(parents=True)
        target.write_text(json.dumps({
            "keep": True,
            "hooks": {"SessionStart": [{"hooks": [
                {"type": "command", "command": "/opt/homebrew/bin/gh-axi"},
                unrelated,
            ]}]},
        }))
    managed.parent.mkdir(parents=True)
    managed.write_text('''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
if sys.argv[1:2] == ["setup"]:
    if os.environ.get("GH_AXI_TEST_CLI"):
        sys.exit(subprocess.call([os.environ["GH_AXI_TEST_CLI"], *sys.argv[1:]]))
    if sys.argv[2:] == ["--help"]:
        print("usage: gh-axi setup hooks")
    else:
        for name in [".claude/settings.json", ".codex/hooks.json"]:
            path = pathlib.Path.home() / name
            settings = json.loads(path.read_text())
            hook = settings["hooks"]["SessionStart"][0]["hooks"][0]
            hook.update(type="command", command="gh-axi", timeout=10)
            path.write_text(json.dumps(settings))
else:
    print("managed hook executed")
''')
    managed.chmod(0o755)
    stale.parent.mkdir()
    stale.write_text("#!/bin/sh\necho stale hook executed >&2\nexit 77\n")
    stale.chmod(0o755)
    env = {**os.environ, "HOME": str(home), "USER": "gh-axi-hooks-test",
           "PATH": f"{stale.parent}:{os.environ['PATH']}"}
    for attempt in range(2):
        subprocess.run(["just", "_setup-axi-hooks", "gh-axi"], cwd=repo, env=env, check=True)
        for target in targets:
            settings = json.loads(target.read_text())
            assert settings["keep"] is True
            hooks = settings["hooks"]["SessionStart"][0]["hooks"]
            assert hooks[1] == unrelated
            result = subprocess.run(hooks[0]["command"], shell=True, env=env,
                                    input="{}", text=True, capture_output=True)
            assert result.returncode == 0, (target, result.returncode, result.stderr)
            assert result.stdout.strip() == "managed hook executed", result.stdout
print("Managed gh-axi SessionStart execution passed (including repeated setup)")
