#!/usr/bin/env python3
"""Offline check of the dibs create guard hook: python3 tests/dibs-create-guard.py [hook]."""

import json
import os
from pathlib import Path
import subprocess
import sys

HOOK = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "claude/hooks/dibs-create-guard.py"

DENY = [
    "/usr/local/bin/docker compose up -d",
    "/opt/homebrew/bin/kind create cluster",
    "./k3d cluster create",
    "command docker compose up",
    "env docker compose -f c.yml up -d",
    "env -i docker compose up",
    "env --ignore-environment docker compose up",
    "sudo -u agent docker compose up -d",
    "env -u FOO docker compose up -d",
    "env -S 'docker compose up -d'",
    "PATH=/usr/bin docker compose up",
    "docker run -d nginx",
    "docker run --rm -dit nginx",
    "docker run -e A=1 --name x -d nginx",
    "docker container run --detach nginx",
    "orb create ubuntu box",
    "cd /tmp && /usr/local/bin/docker compose up -d",
    "bash -lc '/usr/local/bin/kind create cluster'",
    "echo hi\n/usr/local/bin/orbctl create ubuntu",
]
ALLOW = [
    "docker compose up -d",
    "kind create cluster",
    "k3d cluster create",
    "docker ps",
    "/usr/local/bin/docker ps",
    "command docker compose version",
    "sudo -u agent docker ps",
    "env -u FOO docker compose version",
    "docker run --rm nginx echo -d",
    "docker run -e d=1 nginx",
    "git commit -m 'docker run -d nginx'",
    "echo 'unbalanced",
]


def run(command, task="fm-task", tool="Bash", raw=None):
    env = {k: v for k, v in os.environ.items() if k != "DIBS_TASK"}
    if task:
        env["DIBS_TASK"] = task
    stdin = raw if raw is not None else json.dumps({"tool_name": tool, "tool_input": {"command": command}})
    result = subprocess.run([sys.executable, str(HOOK)], input=stdin, capture_output=True, text=True, env=env)
    return result.returncode, result.stderr


failures = []
for command in DENY:
    code, err = run(command)
    if code != 2 or "dibs" not in err:
        failures.append(f"expected deny: {command!r} -> {code} {err!r}")
    code, err = run(command, task=None)
    if code != 0 or err:
        failures.append(f"expected pass without DIBS_TASK: {command!r} -> {code} {err!r}")
for command in ALLOW:
    code, err = run(command)
    if code != 0 or err:
        failures.append(f"expected allow: {command!r} -> {code} {err!r}")

code, err = run("/usr/local/bin/kind create cluster")
if "dibs create --adapter kind" not in err:
    failures.append(f"kind denial must name the dibs command: {err!r}")
# Fails open on its own errors and ignores non-Bash tools.
for raw in ["not json", "", json.dumps({"tool_name": "Bash", "tool_input": {"command": 7}})]:
    code, err = run(None, raw=raw)
    if code != 0 or err:
        failures.append(f"expected fail-open for {raw!r}: {code} {err!r}")
code, err = run("/usr/local/bin/docker compose up", tool="Edit")
if code != 0:
    failures.append("non-Bash tools must pass")

for failure in failures:
    print(failure, file=sys.stderr)
print(f"dibs-create-guard: {len(DENY) + len(ALLOW)} commands, {len(failures)} failure(s)")
sys.exit(1 if failures else 0)
