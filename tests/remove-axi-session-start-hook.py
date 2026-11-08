#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

script = (
    Path(__file__).resolve().parents[1] / "scripts/remove-axi-session-start-hook.py"
)
with tempfile.TemporaryDirectory() as temporary:
    home = Path(temporary)
    path = home / ".claude/settings.json"
    path.parent.mkdir(parents=True)
    original = {
        "hooks": {
            "SessionStart": [
                {
                    "matcher": "",
                    "hooks": [
                        {"type": "command", "command": "gh-axi"},
                        {"type": "command", "command": "gh-axi --session-start"},
                        {"type": "command", "command": "gh-axi --other"},
                        {"type": "command", "command": "my-wrapper --session-start"},
                        {"type": "command", "command": '"/nix/bin/gh-axi"'},
                        {"type": "command", "command": '"gh-axi" --session-start'},
                        {"type": "command", "command": "/usr/local/bin/gh-axi"},
                        {"type": "command", "command": "/nix/store/abc/bin/tasks-axi --session-start"},
                        {"type": "command", "command": "some-other-tool"},
                    ],
                },
            ],
            "PreToolUse": [{"hooks": [{"type": "command", "command": "gh-axi"}]}],
        },
        "unrelated": True,
    }
    path.write_text(json.dumps(original))
    subprocess.run(["python3", str(script), str(home), "gh-axi"], check=True)
    subprocess.run(["python3", str(script), str(home), "tasks-axi"], check=True)
    result = json.loads(path.read_text())
    assert result["hooks"]["SessionStart"] == [
        {
            "matcher": "",
            "hooks": [
                {"type": "command", "command": "gh-axi --other"},
                {"type": "command", "command": "my-wrapper --session-start"},
                {"type": "command", "command": "some-other-tool"},
            ],
        }
    ]
    assert result["hooks"]["PreToolUse"] == original["hooks"]["PreToolUse"]
    assert result["unrelated"]

    import runpy
    from unittest.mock import patch

    remover = runpy.run_path(str(script))
    before = path.read_bytes()
    with patch.object(
        remover["os"], "replace", side_effect=OSError("synthetic replace failure")
    ):
        try:
            remover["write_atomic"](path, result)
        except OSError:
            pass
        else:
            raise AssertionError("atomic write failure was hidden")
    assert path.read_bytes() == before
    assert not list(path.parent.glob(f".{path.name}.*"))

    cleanup_home = home / "cleanup-home"
    profile = cleanup_home / ".config/dotfiles-profile"
    profile.parent.mkdir(parents=True)
    profile.write_text("work")
    settings = cleanup_home / ".claude/settings.json"
    settings.parent.mkdir(parents=True)
    settings.write_text(
        json.dumps(
            {
                "hooks": {
                    "SessionStart": [
                        {
                            "hooks": [
                                {"command": "gh-axi"},
                                {"command": "keep-me"},
                            ]
                        }
                    ]
                }
            }
        )
    )
    local_settings = cleanup_home / ".claude/settings.local.json"
    local_settings.parent.mkdir(parents=True, exist_ok=True)
    local_settings.write_text(
        json.dumps({"hooks": {"SessionStart": [{"hooks": [{"command": "tasks-axi"}, {"command": "keep-local"}]}]}})
    )
    codex = cleanup_home / ".codex/hooks.json"
    subprocess.run(["python3", str(script), str(cleanup_home), "tasks-axi"], check=True)
    assert json.loads(local_settings.read_text())["hooks"]["SessionStart"][0]["hooks"] == [
        {"command": "keep-local"}
    ]
    codex.parent.mkdir(parents=True)
    codex.write_text(
        json.dumps(
            {
                "hooks": {
                    "SessionStart": [
                        {
                            "hooks": [
                                {"command": "tasks-axi"},
                                {"command": "keep-codex"},
                            ]
                        }
                    ]
                }
            }
        )
    )
    bin_dir = home / "bin"
    bin_dir.mkdir()
    call_log = home / "uninstall.log"
    for tool in ["bun-axi", "k8s-axi", "hetzner-axi", "argocd-axi", "argo-workflows-axi"]:
        command = bin_dir / tool
        script = '#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n'
        command.write_text(script + ("exit 2\n" if tool == "bun-axi" else ""))
        command.chmod(0o755)
    cleanup = Path(__file__).resolve().parents[1] / "scripts/cleanup-axi-hooks.sh"
    utils = home / "utils"
    utils.mkdir()
    for name in ["env", "bash", "dirname", "mkdir", "touch", "python3", "cp", "mktemp", "rm", "mv"]:
        (utils / name).symlink_to(shutil.which(name))
    env = {
        **os.environ,
        "HOME": str(cleanup_home),
        "PATH": f"{bin_dir}:{utils}",
        "CALL_LOG": str(call_log),
    }
    personal_home = home / "personal-home"
    personal_env = {**env, "HOME": str(personal_home)}
    personal = subprocess.run(
        [str(cleanup)], env=personal_env, capture_output=True, text=True
    )
    assert personal.returncode == 1
    assert all(tool not in personal.stderr for tool in ["slack-axi", "aws-axi", "gws-axi", "notion-axi"])
    personal_markers = personal_home / ".local/state/dotfiles/axi-hooks-cleanup-v2"
    assert not any((personal_markers / tool).exists() for tool in ["slack-axi", "aws-axi", "gws-axi", "notion-axi"])
    call_log.write_text("")
    first = subprocess.run([str(cleanup)], env=env, capture_output=True, text=True)
    assert first.returncode == 1 and "bun-axi cleanup failed" in first.stderr
    assert "datadog-axi unavailable" in first.stderr
    assert len(call_log.read_text().splitlines()) == 5
    markers = cleanup_home / ".local/state/dotfiles/axi-hooks-cleanup-v2"
    assert len(list(markers.iterdir())) == 16
    bun = bin_dir / "bun-axi"
    bun.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n')
    missing = bin_dir / "datadog-axi"
    missing.write_text(
        '#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\nexit 2\n'
    )
    missing.chmod(0o755)
    failed = subprocess.run([str(cleanup)], env=env, capture_output=True, text=True)
    assert failed.returncode == 1 and "datadog-axi cleanup failed" in failed.stderr
    assert len(call_log.read_text().splitlines()) == 7
    assert len(list(markers.iterdir())) == 17
    missing.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n')
    subprocess.run([str(cleanup)], env=env, check=True, capture_output=True, text=True)
    assert len(call_log.read_text().splitlines()) == 8
    assert len(list(markers.iterdir())) == 18
    subprocess.run([str(cleanup)], env=env, check=True, capture_output=True, text=True)
    assert len(call_log.read_text().splitlines()) == 8
    assert json.loads(settings.read_text())["hooks"]["SessionStart"][0]["hooks"] == [
        {"command": "keep-me"}
    ]
    assert json.loads(codex.read_text())["hooks"]["SessionStart"][0]["hooks"] == [
        {"command": "keep-codex"}
    ]
    assert call_log.read_text().splitlines() == [
        "k8s-axi setup hooks --uninstall",
        "bun-axi setup hooks --uninstall",
        "hetzner-axi setup uninstall",
        "argocd-axi setup uninstall",
        "argo-workflows-axi setup uninstall",
        "bun-axi setup hooks --uninstall",
        "datadog-axi setup uninstall",
        "datadog-axi setup uninstall",
    ], call_log.read_text().splitlines()

print("AXI SessionStart cleanup passed")
