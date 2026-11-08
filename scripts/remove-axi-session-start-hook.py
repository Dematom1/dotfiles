#!/usr/bin/env python3
"""Remove one AXI tool's exact SessionStart command from agent hook settings."""

import json
import os
import shlex
import stat
import sys
import tempfile
from pathlib import Path


def owned_command(command: object, tool: str) -> bool:
    if not isinstance(command, str):
        return False
    quoted = command.startswith('"')
    if quoted:
        try:
            command = json.loads(command)
        except json.JSONDecodeError:
            return False
    try:
        argv = shlex.split(command)
    except ValueError:
        return False
    if not argv:
        return False
    if argv[0] == tool and not argv[1:]:
        return True
    return (
        tool == "gh-axi"
        and Path(argv[0]).name == tool
        and argv[1:] in ([], ["--session-start"])
    )


def write_atomic(path: Path, data: dict) -> None:
    path = path.resolve()
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            file.write(json.dumps(data, indent=2) + "\n")
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode))
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def remove_from(value: object, tool: str) -> bool:
    """Filter only SessionStart hook objects from Claude/Codex settings."""
    changed = False
    if not isinstance(value, dict):
        return False
    hooks = value.get("hooks")
    if not isinstance(hooks, dict):
        return False
    entries = hooks.get("SessionStart")
    if not isinstance(entries, list):
        return False
    kept = []
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
            kept.append(entry)
            continue
        commands = entry["hooks"]
        remaining = [
            hook
            for hook in commands
            if not (isinstance(hook, dict) and owned_command(hook.get("command"), tool))
        ]
        changed |= len(remaining) != len(commands)
        if remaining:
            group = dict(entry)
            group["hooks"] = remaining
            kept.append(group)
    if changed:
        hooks = dict(hooks)
        hooks["SessionStart"] = kept
        value["hooks"] = hooks
    return changed


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: remove-axi-session-start-hook.py HOME TOOL", file=sys.stderr)
        return 2
    home, tool = Path(sys.argv[1]), sys.argv[2]
    for relative in (".claude/settings.json", ".codex/hooks.json"):
        path = home / relative
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as error:
            print(f"{path}: cannot parse settings: {error}", file=sys.stderr)
            return 1
        if remove_from(data, tool):
            write_atomic(path, data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
