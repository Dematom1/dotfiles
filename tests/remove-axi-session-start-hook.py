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
                        {"type": "command", "command": "tasks-axi"},
                        {"type": "command", "command": "/nix/store/abc/bin/tasks-axi --session-start"},
                        {"type": "command", "command": "tasks-axi list --state queued"},
                        {"type": "command", "command": "some-other-tool"},
                    ],
                },
            ],
            "PreToolUse": [{"hooks": [{"type": "command", "command": "gh-axi"}]}],
            "SessionEnd": [{"hooks": [{"type": "command", "command": "argocd-axi"}]}],
        },
        "unrelated": True,
    }
    path.write_text(json.dumps(original))
    subprocess.run(["python3", str(script), str(home), "gh-axi"], check=True)
    tasks_cleanup = subprocess.run(["python3", str(script), str(home), "tasks-axi"])
    assert tasks_cleanup.returncode == 3
    result = json.loads(path.read_text())
    assert result["hooks"]["SessionStart"] == [
        {
            "matcher": "",
            "hooks": [
                {"type": "command", "command": "gh-axi --other"},
                {"type": "command", "command": "my-wrapper --session-start"},
                {"type": "command", "command": "/nix/store/abc/bin/tasks-axi --session-start"},
                {"type": "command", "command": "tasks-axi list --state queued"},
                {"type": "command", "command": "some-other-tool"},
            ],
        }
    ]
    assert result["hooks"]["PreToolUse"] == original["hooks"]["PreToolUse"]
    assert result["hooks"]["SessionEnd"] == original["hooks"]["SessionEnd"]
    assert result["unrelated"]

    malformed_home = home / "malformed-home"
    malformed = malformed_home / ".claude/settings.local.json"
    malformed.parent.mkdir(parents=True)
    malformed.write_text("{")
    valid_codex = malformed_home / ".codex/hooks.json"
    valid_codex.parent.mkdir(parents=True)
    valid_codex.write_text(json.dumps({"hooks": {"SessionStart": [{"hooks": [{"command": "tasks-axi"}, {"command": "keep"}]}]}}))
    failed_parse = subprocess.run(["python3", str(script), str(malformed_home), "tasks-axi"], capture_output=True)
    assert failed_parse.returncode == 1
    assert json.loads(valid_codex.read_text())["hooks"]["SessionStart"][0]["hooks"] == [{"command": "keep"}]
    dangling = malformed_home / ".claude/settings.json"
    dangling.symlink_to(malformed_home / "missing-target.json")
    failed_target = subprocess.run(["python3", str(script), str(malformed_home), "tasks-axi"], capture_output=True)
    assert failed_target.returncode == 1
    assert dangling.is_symlink()

    symlink_target = home / "shared-settings.json"
    symlink_target.write_text(json.dumps({"hooks": {"SessionStart": [{"hooks": [{"command": "tasks-axi"}, {"command": "keep"}]}]}}))
    symlink_path = home / ".claude/settings.local.json"
    symlink_path.symlink_to(symlink_target)
    symlink_cleanup = subprocess.run(["python3", str(script), str(home), "tasks-axi"])
    assert symlink_cleanup.returncode == 3
    assert symlink_path.is_symlink()
    assert json.loads(symlink_target.read_text())["hooks"]["SessionStart"][0]["hooks"] == [{"command": "keep"}]

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
                                {"command": "bun-axi"},
                                {"command": "argocd-axi"},
                                {"command": "datadog-axi"},
                                {"command": "keep-me"},
                            ]
                        }
                    ],
                    "SessionEnd": [{"hooks": [{"command": "argocd-axi"}]}],
                }
            }
        )
    )
    local_settings = cleanup_home / ".claude/settings.local.json"
    local_settings.parent.mkdir(parents=True, exist_ok=True)
    local_settings.write_text(
        json.dumps({"hooks": {"SessionStart": [{"hooks": [{"command": "tasks-axi"}, {"command": "bun-axi"}, {"command": "keep-local"}]}]}})
    )
    codex = cleanup_home / ".codex/hooks.json"
    subprocess.run(["python3", str(script), str(cleanup_home), "tasks-axi"], check=True)
    assert json.loads(local_settings.read_text())["hooks"]["SessionStart"][0]["hooks"] == [
        {"command": "bun-axi"}, {"command": "keep-local"}
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
    shared_settings = cleanup_home / "shared-settings.json"
    shared_settings.write_text(json.dumps({"hooks": {"SessionStart": [{"hooks": [{"command": "tasks-axi"}, {"command": "bun-axi"}, {"command": "preserve"}]}]}}))
    (cleanup_home / ".claude/settings.local.json").unlink()
    (cleanup_home / ".claude/settings.local.json").symlink_to(shared_settings)

    user_owned_home = home / "user-owned-home"
    user_owned_settings = user_owned_home / ".claude/settings.json"
    user_owned_settings.parent.mkdir(parents=True)
    user_owned_command = "/home/me/bin/tasks-axi --session-start"
    user_owned_settings.write_text(json.dumps({"hooks": {"SessionStart": [{"hooks": [{"command": user_owned_command}, {"command": "keep"}]}]}}))
    user_owned_env = {**env, "HOME": str(user_owned_home)}
    user_owned_cleanup = subprocess.run([str(cleanup)], env=user_owned_env, capture_output=True, text=True)
    assert user_owned_cleanup.returncode != 0
    assert json.loads(user_owned_settings.read_text())["hooks"]["SessionStart"][0]["hooks"] == [
        {"command": user_owned_command}, {"command": "keep"}
    ]
    assert not (user_owned_home / ".local/state/dotfiles/axi-hooks-cleanup-v2/tasks-axi").exists()

    call_log.write_text("")
    first = subprocess.run([str(cleanup)], env=env, capture_output=True, text=True)
    assert first.returncode == 1 and "bun-axi cleanup failed" in first.stderr, first.stderr
    assert len(call_log.read_text().splitlines()) == 4, call_log.read_text().splitlines()
    assert not (cleanup_home / ".local/state/dotfiles/axi-hooks-cleanup-v2/snapshot").exists()
    markers = cleanup_home / ".local/state/dotfiles/axi-hooks-cleanup-v2"
    assert (markers / "bun-axi.attempted").is_file()
    bun = bin_dir / "bun-axi"
    bun.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n')
    missing = bin_dir / "datadog-axi"
    missing.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n')
    missing.chmod(0o755)
    subprocess.run([str(cleanup)], env=env, check=True, capture_output=True, text=True)
    assert len(call_log.read_text().splitlines()) == 4
    assert (markers / "bun-axi.attempted").is_file()
    subprocess.run([str(cleanup)], env=env, check=True, capture_output=True, text=True)
    assert len(call_log.read_text().splitlines()) == 4
    assert json.loads(settings.read_text())["hooks"]["SessionStart"][0]["hooks"] == [
        {"command": "keep-me"}
    ]
    assert json.loads(settings.read_text())["hooks"]["SessionEnd"] == [
        {"hooks": [{"command": "argocd-axi"}]}
    ]
    assert json.loads(codex.read_text())["hooks"]["SessionStart"][0]["hooks"] == [
        {"command": "keep-codex"}
    ]
    assert json.loads(shared_settings.read_text())["hooks"]["SessionStart"][0]["hooks"] == [
        {"command": "preserve"}
    ]
    assert call_log.read_text().splitlines() == [
        "k8s-axi setup uninstall",
        "bun-axi setup hooks --uninstall",
        "hetzner-axi setup uninstall",
        "argo-workflows-axi setup uninstall",
    ], call_log.read_text().splitlines()

print("AXI SessionStart cleanup passed")
