#!/usr/bin/env python3
"""Remove one AXI tool's exact SessionStart command from agent hook settings."""

import json
import sys
from pathlib import Path


def owned_command(command: object, tool: str) -> bool:
    if not isinstance(command, str):
        return False
    # gh-axi setup hooks may persist a JSON-quoted absolute executable path.
    quoted = command.startswith('"')
    if quoted:
        try:
            command = json.loads(command)
        except json.JSONDecodeError:
            return False
    if not isinstance(command, str) or any(c.isspace() for c in command):
        return False
    return (not quoted and command == tool) or (
        quoted
        and tool == "gh-axi"
        and Path(command).is_absolute()
        and Path(command).name == tool
    )


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
            path.write_text(json.dumps(data, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
