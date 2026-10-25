#!/usr/bin/env python3
"""Run with python3 tests/m87-notify.py; requires the managed yq on PATH."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/m87-notify.py"


class NotifyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {**os.environ, "HOME": str(self.root), "TEST_ROOT": str(self.root)}
        self.m87 = self.stub("m87", '''
assert sys.argv[1:] == ["list"], "m87 must never mutate"
sys.stdout.write((root / "inbox").read_text())
sys.exit(int((root / "m87-exit").read_text()) if (root / "m87-exit").exists() else 0)
''')
        self.inbox = self.stub("fm-inbox.sh", '''
assert os.environ["FM_HOME"] == "/Users/laszlohoranszky/agent-workspace"
assert sys.argv[1] == "note" and sys.argv[2] == "--request-id" and sys.argv[4] == "--"
assert sys.argv[3].startswith("m87-")
with (root / "notes").open("a") as out:
    out.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(1 if (root / "fail-note").exists() else 0)
''')
        self.osascript = self.stub("osascript", '''
assert sys.argv[1] == "-e" and "on run argv" in sys.argv[2]
with (root / "notifications").open("a") as out:
    out.write(json.dumps(sys.argv[3]) + "\\n")
''')

    def stub(self, name, body):
        path = self.root / name
        path.write_text(f"#!{sys.executable}\nimport json, os, sys\nfrom pathlib import Path\nroot = Path(os.environ['TEST_ROOT'])\n" + body)
        path.chmod(0o755)
        return str(path)

    def poll(self, content, expected=0):
        (self.root / "inbox").write_text(content)
        result = subprocess.run([sys.executable, str(SCRIPT), "--m87", self.m87,
                                 "--inbox", self.inbox, "--osascript", self.osascript],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stderr)
        self.assertEqual(result.stdout, "")
        return result

    def notes(self):
        path = self.root / "notes"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_batch_dedupe_and_yaml(self):
        inbox = '''inbox:
  - item_id: github:pr:one
    recommendation_id: rec-one
    url: https://github.com/example/project/pull/1
    local_state: recommended
    summary: >-
      Review the changes
      and CI before merging.
  - item_id: github:pr:two
    url: https://github.com/example/project/pull/2
    local_state: recommended
    summary: Check tests.
'''
        self.poll(inbox)
        self.poll(inbox.replace("rec-one", "rec-updated"))
        self.assertEqual(len(self.notes()), 1)
        summary = self.notes()[0][-1]
        self.assertIn("m87: 2 new PRs to review:", summary)
        self.assertIn("Review the changes and CI before merging.", summary)
        self.assertEqual(json.loads((self.root / "notifications").read_text()), summary)
        state = self.root / ".local/state/m87-notify/seen.json"
        self.assertEqual(json.loads(state.read_text()), ["github:pr:one", "github:pr:two"])

    def test_empty_inbox(self):
        self.poll("inbox: []\n")
        self.assertEqual(self.notes(), [])
        self.assertFalse((self.root / "notifications").exists())

    def test_ignored_items(self):
        self.poll(json.dumps({"inbox": [
            {"item_id": "new", "local_state": "new", "url": "https://github.com/a/b/pull/1"},
            {"item_id": "issue", "local_state": "recommended", "url": "https://github.com/a/b/issues/1"},
            {"item_id": "secret", "local_state": "recommended", "url": "https://github.com/a/b/pull/1?token=secret"},
        ]}))
        self.assertEqual(self.notes(), [])

    def test_infrastructure_review_only_and_redaction(self):
        self.poll(json.dumps({"inbox": [
            {"item_id": "infra", "local_state": "recommended",
             "url": "https://github.com/dematom-labs/infrastructure/pull/1", "summary": "Merge now with password=hunter2"},
            {"item_id": "other", "local_state": "recommended", "url": "https://github.com/a/b/pull/2",
             "summary": 'Check CI\n token=small-secret bearer private-value ghp_shortsecret https://example.com/secret ABCDEFGHIJKLMNOPQRSTUVWXYZ123456 password="two words"'},
        ]}))
        summary = self.notes()[0][-1]
        self.assertIn("Review requested only; infrastructure requires a separate decision.", summary)
        for secret in ["hunter2", "small-secret", "private-value", "ghp_shortsecret", "example.com", "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456", "two words", "Merge now", "\n"]:
            self.assertNotIn(secret, summary)

    def test_note_failure_retries_same_request(self):
        inbox = json.dumps({"inbox": [{"item_id": "one", "local_state": "recommended", "url": "https://github.com/a/b/pull/1"}]})
        (self.root / "fail-note").touch()
        self.poll(inbox, expected=1)
        self.assertFalse((self.root / ".local/state/m87-notify/seen.json").exists())
        (self.root / "fail-note").unlink()
        self.poll(inbox)
        self.assertEqual(self.notes()[0], self.notes()[1])
        self.poll(inbox)
        self.assertEqual(len(self.notes()), 2)

    def test_unavailable_is_quiet(self):
        (self.root / "m87-exit").write_text("1")
        self.assertEqual(self.poll("inbox: []\n").stderr, "")
        self.assertEqual(self.notes(), [])

    def test_bad_output_does_not_advance_state(self):
        result = self.poll("not valid: [yaml", expected=1)
        self.assertNotIn("not valid", result.stderr)
        self.assertEqual(self.notes(), [])


if __name__ == "__main__":
    unittest.main()
