#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

script = Path(__file__).resolve().parents[1] / "scripts/remove-axi-session-start-hook.py"
with tempfile.TemporaryDirectory() as temporary:
    home = Path(temporary)
    path = home / ".claude/settings.json"
    path.parent.mkdir(parents=True)
    original = {
        "hooks": {
            "SessionStart": [
                {"matcher": "", "hooks": [
                    {"type": "command", "command": "gh-axi"},
                    {"type": "command", "command": '"/nix/bin/gh-axi"'},
                    {"type": "command", "command": "/usr/local/bin/gh-axi"},
                    {"type": "command", "command": "some-other-tool"},
                ]},
            ],
            "PreToolUse": [{"hooks": [{"type": "command", "command": "gh-axi"}]}],
        },
        "unrelated": True,
    }
    path.write_text(json.dumps(original))
    subprocess.run(["python3", str(script), str(home), "gh-axi"], check=True)
    result = json.loads(path.read_text())
    assert result["hooks"]["SessionStart"] == [{"matcher": "", "hooks": [
        {"type": "command", "command": "/usr/local/bin/gh-axi"},
        {"type": "command", "command": "some-other-tool"},
    ]}]
    assert result["hooks"]["PreToolUse"] == original["hooks"]["PreToolUse"]
    assert result["unrelated"]

    cleanup_home = home / "cleanup-home"
    settings = cleanup_home / ".claude/settings.json"
    settings.parent.mkdir(parents=True)
    settings.write_text(json.dumps({"hooks": {"SessionStart": [{"hooks": [
        {"command": "gh-axi"}, {"command": "keep-me"},
    ]}]}}))
    codex = cleanup_home / ".codex/hooks.json"
    codex.parent.mkdir(parents=True)
    codex.write_text(json.dumps({"hooks": {"SessionStart": [{"hooks": [
        {"command": "tasks-axi"}, {"command": "keep-codex"},
    ]}]}}))
    bin_dir = home / "bin"
    bin_dir.mkdir()
    call_log = home / "uninstall.log"
    for tool in ["bun-axi", "hetzner-axi", "argocd-axi", "argo-workflows-axi"]:
        command = bin_dir / tool
        command.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n')
        command.chmod(0o755)
    cleanup = Path(__file__).resolve().parents[1] / "scripts/cleanup-axi-hooks.sh"
    utils = home / "utils"
    utils.mkdir()
    for name in ["env", "bash", "dirname", "mkdir", "touch", "python3"]:
        (utils / name).symlink_to(shutil.which(name))
    env = {**os.environ, "HOME": str(cleanup_home),
           "PATH": f"{bin_dir}:{utils}", "CALL_LOG": str(call_log)}
    subprocess.run([str(cleanup)], env=env, check=True, capture_output=True, text=True)
    assert len(call_log.read_text().splitlines()) == 4
    markers = cleanup_home / ".local/state/dotfiles/axi-hooks-cleanup"
    assert len(list(markers.iterdir())) == 15
    missing = bin_dir / "datadog-axi"
    missing.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n')
    missing.chmod(0o755)
    subprocess.run([str(cleanup)], env=env, check=True, capture_output=True, text=True)
    assert len(call_log.read_text().splitlines()) == 5
    assert len(list(markers.iterdir())) == 16
    subprocess.run([str(cleanup)], env=env, check=True, capture_output=True, text=True)
    assert len(call_log.read_text().splitlines()) == 5
    assert json.loads(settings.read_text())["hooks"]["SessionStart"][0]["hooks"] == [{"command": "keep-me"}]
    assert json.loads(codex.read_text())["hooks"]["SessionStart"][0]["hooks"] == [{"command": "keep-codex"}]
    assert call_log.read_text().splitlines() == [
        "bun-axi setup hooks --uninstall",
        "hetzner-axi setup uninstall",
        "argocd-axi setup uninstall",
        "argo-workflows-axi setup uninstall",
        "datadog-axi setup uninstall",
    ]

print("AXI SessionStart cleanup passed")
