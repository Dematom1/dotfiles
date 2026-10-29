#!/usr/bin/env python3
"""Offline CLI check: python3 tests/axi-approve.py. No registry or 1Password access."""
import json
import os
from pathlib import Path
import pty
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/axi-approve.py"
STAGE = {
    "id": "1de6f3db-2ed9-4d72-b3dd-8f0e2b474a2f",
    "packageName": "argocd-axi", "version": "1.2.3", "status": "awaiting_approval",
    "provenance": {"predicate": {
        "buildDefinition": {
            "externalParameters": {"workflow": {"repository": "https://github.com/example/argocd-axi"}},
            "resolvedDependencies": [
                {"uri": "git+https://github.com/example/dependency@refs/heads/main", "digest": {"gitCommit": "dependency123"}},
                {"uri": "git+https://github.com/example/argocd-axi@refs/heads/main", "digest": {"gitCommit": "abc123"}},
            ],
        },
        "runDetails": {"metadata": {"invocationId": "https://github.com/example/argocd-axi/actions/runs/42"}},
    }},
}

with tempfile.TemporaryDirectory(prefix="axi-approve-test-") as directory:
    root = Path(directory)
    stub = root / "npm"
    stub.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["TRACE"], "a") as trace:
    trace.write(("version" if args == ["--version"] else " ".join(args[:2])) + "\\n")
if args == ["--version"]:
    print(os.environ.get("VERSION", "11.19.0"))
    sys.exit(0)
assert "--logs-max=0" in args
assert args[args.index("--registry") + 1] == "https://registry.npmjs.org/"
item = json.loads(os.environ["STAGE"])
if args[:2] == ["stage", "list"]:
    print(json.dumps([item] if os.environ.get("PENDING") and args[2] == item["packageName"] else []))
elif args[:2] == ["stage", "view"]:
    print(json.dumps(item))
elif args[:2] == ["stage", "download"]:
    print(json.dumps({item["packageName"]: {
        "name": item["packageName"], "version": item["version"],
        "files": [{"path": "package.json"}, {"path": "dist/index.js"}],
    }}))
elif args[:2] == ["stage", "approve"]:
    assert args[args.index("--otp") + 1] == "123456"
    sys.exit(int(os.environ.get("APPROVE_STATUS", "0")))
else:
    sys.exit(99)
''')
    stub.chmod(0o755)
    op = root / "op"
    op.write_text('''#!/usr/bin/env python3
import os, sys
assert sys.argv[1:] == ["read", "op://Test/npm/one-time password"]
with open(os.environ["TRACE"], "a") as trace:
    trace.write("op read\\n")
print("123456")
''')
    op.chmod(0o755)
    env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", STAGE=json.dumps(STAGE),
               TRACE=str(root / "trace"))
    env.pop("AXI_APPROVE_OP_REF", None)

    def run(extra=None, answer=None):
        (root / "trace").write_text("")
        master, slave = pty.openpty()
        try:
            if answer is not None:
                os.write(master, answer.encode())
            result = subprocess.run([sys.executable, str(SCRIPT)], env=env | (extra or {}),
                                    stdin=slave if answer is not None else subprocess.DEVNULL,
                                    capture_output=True, text=True, timeout=10)
        finally:
            os.close(master)
            os.close(slave)
        assert "123456" not in result.stdout + result.stderr
        return result, (root / "trace").read_text()

    result, trace = run()
    assert result.returncode == 0 and "nothing pending" in result.stdout
    assert trace.count("stage list") == 3 and "op read" not in trace
    result, trace = run({"VERSION": "11.18.0"})
    assert result.returncode == 1 and "npm >= 11.19" in result.stdout
    assert "stage" not in trace
    result, trace = run({"PENDING": "1"})
    assert result.returncode == 1 and "AXI_APPROVE_OP_REF" in result.stdout
    assert "op read" not in trace
    configured = {"PENDING": "1", "AXI_APPROVE_OP_REF": "op://Test/npm/one-time password"}
    for malformed in (
        {"predicate": "bad"},
        {"predicate": {"buildDefinition": "bad"}},
        {"predicate": {"buildDefinition": {"externalParameters": "bad", "resolvedDependencies": [None]}}},
        {"predicate": {"runDetails": "bad"}},
    ):
        result, _ = run(configured | {"STAGE": json.dumps(STAGE | {"provenance": malformed})}, "n\n")
        assert result.returncode == 0 and "not provided by npm stage view" in result.stdout
    result, trace = run(configured, "n\n")
    assert result.returncode == 0 and "skipped" in result.stdout
    assert "op read" not in trace and "stage approve" not in trace
    assert 'commit: "abc123"' in result.stdout
    assert 'commit: "dependency123"' not in result.stdout
    assert all(value in result.stdout for value in ("actions/runs/42", "dist/index.js", STAGE["id"]))
    result, trace = run(configured, "yes\n")
    assert result.returncode == 0 and "skipped" in result.stdout
    assert "op read" not in trace and "stage approve" not in trace
    result, trace = run(configured, "y\n")
    assert result.returncode == 0 and "approved and published" in result.stdout
    assert trace.endswith("op read\nstage approve\n")
    result, trace = run(configured | {"APPROVE_STATUS": "1"}, "y\n")
    assert result.returncode == 1 and "approval failed" in result.stdout

print("axi-approve offline checks passed")
