#!/usr/bin/env python3
"""Forward new recommended PRs to firstmate without mutating the m87 inbox."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

FIRSTMATE_HOME = "/Users/laszlohoranszky/agent-workspace"


def recommendation(item):
    if item["url"].lower().startswith("https://github.com/dematom-labs/infrastructure/"):
        return "Review requested only; infrastructure requires a separate decision."
    text = item.get("summary") or "Review diff and CI before deciding."
    if not isinstance(text, str):
        raise ValueError("invalid recommendation summary")
    text = "".join(char for char in " ".join(text.split()) if char.isprintable())
    # Strip credential assignments, embedded URLs, and opaque/token-like strings.
    text = re.sub(r"(?i)\b(?:bearer\s+\S+|(?:\w*(?:token|secret|password|api[_-]?key)\w*[\"']?)\s*[:=]\s*(?:\"[^\"]*\"|'[^']*'|\S+))", "[redacted]", text)
    text = re.sub(r"https?://\S+|\b(?:gh[pousr]_|github_pat_|sk-|AKIA|ASIA)\S+|[A-Za-z0-9_+/=\-]{24,}", "[redacted]", text)
    return text[:400]


def run(args):
    state = Path.home() / ".local/state/m87-notify"
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (state / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        try:
            result = subprocess.run([args.m87, "list"], capture_output=True, text=True, timeout=60)
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return
        if result.returncode:
            return
        # m87 0.1.10 has no JSON flag: its native list output is structured YAML.
        result = subprocess.run([args.yq, "."], input=result.stdout, capture_output=True, text=True, check=True, timeout=30)
        items = json.loads(result.stdout)["inbox"] or []
        if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
            raise ValueError("invalid inbox schema")
        seen_file = state / "seen.json"
        seen = set(json.loads(seen_file.read_text())) if seen_file.exists() else set()
        batch = {}
        for item in items:
            url = item.get("url", "")
            item_id = item.get("item_id")
            if (item.get("local_state") == "recommended" and isinstance(item_id, str)
                    and item_id not in seen and re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+", url)):
                batch[item_id] = item
        if not batch:
            return
        ids = sorted(batch)
        digest = hashlib.sha256(json.dumps(ids).encode()).hexdigest()
        summary = f"m87: {len(ids)} new PRs to review: " + " ; ".join(
            f"{batch[item_id]['url']} - {recommendation(batch[item_id])}" for item_id in ids
        )
        subprocess.run([args.inbox, "note", "--request-id", f"m87-{digest}", "--", summary],
                       env={**os.environ, "FM_HOME": FIRSTMATE_HOME},
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=60)
        # argv avoids interpolating untrusted recommendation text into AppleScript.
        script = 'on run argv\ndisplay notification (item 1 of argv) with title "m87"\nend run'
        try:
            subprocess.run([args.osascript, "-e", script, summary], capture_output=True, check=True, timeout=30)
        except (OSError, subprocess.SubprocessError):
            print("m87-notify: desktop notification failed; firstmate note delivered", file=sys.stderr)
        with tempfile.NamedTemporaryFile(mode="w", dir=state, delete=False) as output:
            temporary = Path(output.name)
            try:
                json.dump(sorted(seen | set(ids)), output)
                output.flush()
                os.fsync(output.fileno())
                os.replace(temporary, seen_file)
            finally:
                temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--m87", default="m87")
    parser.add_argument("--yq", default="yq")
    parser.add_argument("--inbox", default=f"{FIRSTMATE_HOME}/bin/fm-inbox.sh")
    parser.add_argument("--osascript", default="/usr/bin/osascript")
    args = parser.parse_args()
    try:
        run(args)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        # Never echo external output, which can contain credentials.
        print("m87-notify: poll failed; will retry next interval", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
