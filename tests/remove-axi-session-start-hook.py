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
    subprocess.run(["python3", str(script), str(home), "tasks-axi"], check=True)
    result = json.loads(path.read_text())
    assert result["hooks"]["SessionStart"] == [
        {
            "matcher": "",
            "hooks": [
                {"type": "command", "command": "gh-axi --other"},
                {"type": "command", "command": "my-wrapper --session-start"},
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
    subprocess.run(["python3", str(script), str(home), "tasks-axi"], check=True)
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

    failed_backup_home = home / "failed-backup-home"
    failed_backup_settings = failed_backup_home / ".claude/settings.json"
    failed_backup_settings.parent.mkdir(parents=True)
    before_failed_backup = json.dumps({"hooks": {"SessionStart": [{"hooks": [{"command": "bun-axi"}]}]}})
    failed_backup_settings.write_text(before_failed_backup)
    failing_bin = home / "failing-bin"
    failing_bin.mkdir()
    cp_stub = failing_bin / "cp"
    cp_stub.write_text("#!/bin/sh\nexit 2\n")
    cp_stub.chmod(0o755)
    failed_backup_log = home / "failed-backup.log"
    failed_backup_env = {**env, "HOME": str(failed_backup_home), "PATH": f"{failing_bin}:{bin_dir}:{utils}", "CALL_LOG": str(failed_backup_log)}
    backup_failure = subprocess.run([str(cleanup)], env=failed_backup_env, capture_output=True, text=True)
    assert backup_failure.returncode != 0
    assert failed_backup_settings.read_text() == before_failed_backup
    assert not failed_backup_log.exists()
    failed_backup_markers = failed_backup_home / ".local/state/dotfiles/axi-hooks-cleanup-v2"
    assert not any(failed_backup_markers.glob("*.axi"))

    failed_target_home = home / "failed-target-home"
    failed_target_settings = failed_target_home / ".claude/settings.local.json"
    failed_target_settings.parent.mkdir(parents=True)
    failed_target_file = failed_target_home / "shared-settings.json"
    before_failed_target = json.dumps({"hooks": {"SessionStart": [{"hooks": [{"command": "bun-axi"}]}]}})
    failed_target_file.write_text(before_failed_target)
    failed_target_settings.symlink_to(failed_target_file)
    cp_count = home / "cp-count"
    cp_stub.write_text(
        '#!/bin/sh\nif [ -e "$COUNT_FILE" ]; then exit 2; fi\ntouch "$COUNT_FILE"\n'
        + f'exec {shutil.which("cp")} "$@"\n'
    )
    failed_target_env = {**failed_backup_env, "HOME": str(failed_target_home), "COUNT_FILE": str(cp_count)}
    target_backup_failure = subprocess.run([str(cleanup)], env=failed_target_env, capture_output=True, text=True)
    assert target_backup_failure.returncode != 0
    assert failed_target_settings.is_symlink()
    assert failed_target_file.read_text() == before_failed_target
    assert not failed_backup_log.exists()
    assert not list((failed_target_home / ".local/state/dotfiles/axi-hooks-cleanup-v2").glob("*.axi"))

    personal_home = home / "personal-home"
    incomplete = personal_home / ".local/state/dotfiles/axi-hooks-cleanup-v2/snapshot"
    incomplete.mkdir(parents=True)
    (incomplete / "partial").write_text("incomplete")
    personal_env = {**env, "HOME": str(personal_home)}
    personal = subprocess.run(
        [str(cleanup)], env=personal_env, capture_output=True, text=True
    )
    assert personal.returncode == 1
    assert (incomplete / ".complete").is_file()
    assert not (incomplete / "partial").exists()
    assert all(tool not in personal.stderr for tool in ["slack-axi", "aws-axi", "gws-axi", "notion-axi"])
    personal_markers = personal_home / ".local/state/dotfiles/axi-hooks-cleanup-v2"
    assert not any((personal_markers / tool).exists() for tool in ["slack-axi", "aws-axi", "gws-axi", "notion-axi"])
    call_log.write_text("")
    first = subprocess.run([str(cleanup)], env=env, capture_output=True, text=True)
    assert first.returncode == 1 and "bun-axi cleanup failed" in first.stderr, first.stderr
    assert len(call_log.read_text().splitlines()) == 4, call_log.read_text().splitlines()
    snapshot = cleanup_home / ".local/state/dotfiles/axi-hooks-cleanup-v2/snapshot"
    assert (snapshot / ".claude/settings.local.json").is_symlink()
    assert json.loads((snapshot / ".targets/.claude/settings.local.json").read_text())["hooks"]["SessionStart"][0]["hooks"] == [
        {"command": "tasks-axi"}, {"command": "bun-axi"}, {"command": "preserve"}
    ]
    markers = cleanup_home / ".local/state/dotfiles/axi-hooks-cleanup-v2"
    assert len(list(markers.iterdir())) == 17
    bun = bin_dir / "bun-axi"
    bun.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n')
    missing = bin_dir / "datadog-axi"
    missing.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n')
    missing.chmod(0o755)
    subprocess.run([str(cleanup)], env=env, check=True, capture_output=True, text=True)
    assert len(call_log.read_text().splitlines()) == 5
    assert len(list(markers.iterdir())) == 18
    subprocess.run([str(cleanup)], env=env, check=True, capture_output=True, text=True)
    assert len(call_log.read_text().splitlines()) == 5
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
        "bun-axi setup hooks --uninstall",
    ], call_log.read_text().splitlines()

print("AXI SessionStart cleanup passed")
