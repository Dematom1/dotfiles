#!/usr/bin/env python3
"""Drive a built generation's m87 activation steps against a scratch HOME.

Real: the generation's activation python, handoff script, managed plist,
m87GithubDiscovery block, and the Nix m87 CLI and daemons. Fake: launchd
(fake-launchctl.py) and GitHub (a gh stub through m87's own M87_GH_BIN).

usage: m87-handoff.py GENERATION OUT_DIR [SCENARIO ...]
scenarios: noop dry-run handoff slow-sync (default: all)
"""
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
REAL_HOME = pwd.getpwuid(os.getuid()).pw_dir
LEGACY_LABEL = "com.m87.daemon.verify"
GH_STUB = """#!/bin/sh
printf '%s\\n' "$*" >> "$M87_FAKE_GH_LOG"
case "$1 $2" in
  "auth status") echo "Logged in to github.com as verify-bot"; exit 0 ;;
  "--version "*) echo "gh version 0.0.0 (verify stub)"; exit 0 ;;
  "api user") echo verify-bot; exit 0 ;;
esac
# Every list/search call: no items, after the configured network latency.
sleep "${M87_FAKE_GH_DELAY:-0}"
echo '[]'
"""


def parse_activation(generation):
    text = (generation / "activate").read_text()
    handoff = re.search(r'"m87DaemonHandoff"\n(\S+/python3\.\d+) (\S+-m87-remove-npm-daemon\.py) \\\n'
                        r'\s+(\S+) "\$newGenPath/LaunchAgents/([^"]+)"', text)
    discovery = re.search(r'"m87GithubDiscovery"\n(.*?)\n\n\n_iNote', text, re.S)
    if not handoff or not discovery:
        sys.exit("activation script has no m87GithubDiscovery/m87DaemonHandoff steps")
    python, script, nix_root, plist = handoff.groups()
    return {"python": python, "script": script, "nix_root": Path(nix_root),
            "plist": generation / "LaunchAgents" / plist, "discovery": discovery[1]}


class Scratch:
    """One throwaway HOME. Everything it starts is torn down by close()."""

    def __init__(self, out, gh_delay=0):
        # Short /tmp path: the daemon's Unix socket path must stay under 104 bytes.
        self.home = Path(tempfile.mkdtemp(prefix="dfv.", dir="/tmp")).resolve()
        assert not str(self.home).startswith(REAL_HOME + "/")
        assert len(str(self.home / ".m87/daemon.sock")) < 100
        self.out = out
        out.mkdir(parents=True, exist_ok=True)
        self.transcript = open(out / "transcript.log", "w")
        tools = self.home / "verify-bin"
        tools.mkdir()
        (tools / "gh").write_text(GH_STUB)
        (tools / "gh").chmod(0o755)
        self.launchctl = str(HERE / "fake-launchctl.py")
        fake_gh = {"M87_GH_BIN": str(tools / "gh"), "M87_FAKE_GH_LOG": str(self.home / "gh-calls.log"),
                   "M87_FAKE_GH_DELAY": str(gh_delay)}
        # Minimal environment: nothing from the operator's shell (tokens, GH_*) leaks in.
        self.env = {"HOME": str(self.home), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": "/tmp",
                    "USER": pwd.getpwuid(os.getuid()).pw_name, "LANG": "en_US.UTF-8",
                    "M87_STATE_DIR": str(self.home / ".m87"), "M87_SKIP_SHELLENV": "1", **fake_gh,
                    "FAKE_LAUNCHD_DIR": str(self.home / ".fake-launchd"),
                    "FAKE_LAUNCHD_HOME": str(self.home), "FAKE_LAUNCHD_REAL_HOME": REAL_HOME,
                    "FAKE_LAUNCHD_EXTRA_ENV": json.dumps(fake_gh)}

    def run(self, args, *, env=None, timeout=120, check=True):
        args = [str(arg) for arg in args]
        self.transcript.write(f"$ {' '.join(args)[:400]}\n")
        result = subprocess.run(args, env={**self.env, **(env or {})}, capture_output=True,
                                text=True, timeout=timeout, cwd=self.home, stdin=subprocess.DEVNULL)
        self.transcript.write(result.stdout + result.stderr + f"[exit {result.returncode}]\n")
        self.transcript.flush()
        if check and result.returncode:
            raise RuntimeError(f"{Path(args[0]).name} exited {result.returncode}")
        return result

    def tree(self):
        skip = {"verify-bin", ".fake-launchd"}
        return sorted(str(p.relative_to(self.home)) for p in self.home.rglob("*")
                      if p.relative_to(self.home).parts[0] not in skip)

    def close(self):
        jobs = self.home / ".fake-launchd"
        for pidfile in sorted(jobs.glob("*.pid")):
            self.run([self.launchctl, "bootout", "--wait", f"gui/{os.getuid()}/{pidfile.stem}"], check=False)
        # Belt and braces: anything still running from this unique scratch path is ours.
        stray = subprocess.run(["/usr/bin/pgrep", "-f", str(self.home)], capture_output=True, text=True).stdout.split()
        for pid in stray:
            os.kill(int(pid), signal.SIGKILL)
        logs = {jobs / "calls.log": "launchctl-calls.log", self.home / "gh-calls.log": "gh-calls.log",
                self.home / ".m87/daemon.log": "daemon.log", self.home / ".m87/legacy.log": "legacy.log"}
        for log, name in logs.items():
            if log.exists():
                shutil.copy(log, self.out / name)
        self.transcript.close()
        shutil.rmtree(self.home)


def install_legacy(scratch, nix_root):
    """Lay out the npm-global m87 the handoff retires, as `npm i -g` left it."""
    home = scratch.home
    nix_modules = nix_root / "libexec/m87/node_modules"
    modules = home / ".local/lib/node_modules"
    package = modules / "@kunchenguid/m87"
    package.parent.mkdir(parents=True)
    shutil.copytree(nix_modules / "@kunchenguid/m87", package, symlinks=True)
    subprocess.run(["/bin/chmod", "-R", "u+w", package], check=True)
    for entry in nix_modules.iterdir():
        if entry.name not in {"@kunchenguid", ".bin"}:
            (modules / entry.name).symlink_to(entry)
    cli = package / "dist/cli.js"
    (home / ".local/bin").mkdir(parents=True)
    (home / ".local/bin/m87").symlink_to(cli)
    node = (nix_root / "bin/m87").read_text().splitlines()[0][2:].strip()
    agents = home / "Library/LaunchAgents"
    agents.mkdir(parents=True)
    plist = agents / f"{LEGACY_LABEL}.plist"
    plist.write_bytes(plistlib.dumps({
        "Label": LEGACY_LABEL, "ProgramArguments": [node, str(cli), "daemon", "run"],
        "EnvironmentVariables": {"M87_DAEMON": "1", "M87_STATE_DIR": str(home / ".m87"),
                                 "M87_SKIP_SHELLENV": "1"},
        "RunAtLoad": True, "KeepAlive": True, "StandardOutPath": str(home / ".m87/legacy.log"),
        "StandardErrorPath": str(home / ".m87/legacy.log")}))
    return node, cli, plist


def launchd_pid(scratch, label):
    out = scratch.run([scratch.launchctl, "print", f"gui/{os.getuid()}/{label}"], check=False).stdout
    match = re.search(r"^\s*pid = (\d+)$", out, re.M)
    return int(match[1]) if match else None


def wait_daemon(scratch, nix_root, label, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pid = launchd_pid(scratch, label)
        status = scratch.run([nix_root / "bin/m87", "daemon", "status"], check=False).stdout
        if pid and f"pid: {pid}\n" in status and "status: running" in status:
            return pid
        time.sleep(0.5)
    raise RuntimeError(f"{label} daemon did not become ready")


def wait_first_sync(scratch, timeout=120):
    """A long-running npm worker has synced before; start the handoff from that state."""
    database = scratch.home / ".m87/m87.sqlite"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        with sqlite3.connect(f"{database.as_uri()}?mode=ro", uri=True) as db:
            if db.execute("select last_sync_at from plugins where id='github'").fetchone()[0]:
                return
        time.sleep(0.5)
    raise RuntimeError("npm worker never completed its first GitHub sync")


def snapshot(scratch, nix_root, managed_label):
    home = scratch.home
    with sqlite3.connect(f"{(home / '.m87/m87.sqlite').as_uri()}?mode=ro", uri=True) as db:
        plugins = {row[0]: {"binary": row[1].replace(str(home), "~").replace(str(nix_root), "<nix-m87>"),
                            "config": json.loads(row[2] or "{}"), "status": row[3],
                            "last_sync_at": row[4], "last_error": row[5]}
                   for row in db.execute("select id, binary_path, config_json, status, last_sync_at, last_error from plugins")}
        items = db.execute("select count(*) from items").fetchone()[0]
    pid_file = home / ".m87/daemon.pid"
    return {
        "plugins": plugins, "items": items,
        "daemon_pid": int(pid_file.read_text()) if pid_file.exists() else None,
        "legacy_pid": launchd_pid(scratch, LEGACY_LABEL),
        "managed_pid": launchd_pid(scratch, managed_label),
        "legacy_plist": (home / f"Library/LaunchAgents/{LEGACY_LABEL}.plist").exists(),
        "legacy_package": (home / ".local/lib/node_modules/@kunchenguid/m87").exists(),
        "legacy_shim": (home / ".local/bin/m87").is_symlink(),
        "managed_plist": (home / f"Library/LaunchAgents/{managed_label}.plist").exists(),
    }


def exact_step(steps, scratch, **env):
    """The m87DaemonHandoff line exactly as activation runs it (real /bin/launchctl)."""
    return scratch.run([steps["python"], steps["script"], steps["nix_root"], steps["plist"]],
                       env=env, check=False)


def scenario_noop(steps, out):
    """A normal rebuild with no npm m87 left: the step must be a silent no-op."""
    scratch = Scratch(out)
    try:
        before = scratch.tree()
        assert not (scratch.home / ".local").exists()  # guarantees the early return before launchctl
        result = exact_step(steps, scratch)
        problems = [p for p, bad in [("non-zero exit", result.returncode),
                                     ("unexpected output", result.stdout + result.stderr),
                                     ("scratch HOME changed", scratch.tree() != before)] if bad]
        return problems
    finally:
        scratch.close()


def scenario_dry_run(steps, out):
    """`DRY_RUN=1` with the npm worker present: describe, change nothing."""
    scratch = Scratch(out)
    try:
        install_legacy(scratch, steps["nix_root"])
        before = scratch.tree()
        result = exact_step(steps, scratch, DRY_RUN="1")
        expected = "Would preflight, repoint plugins, cut over with rollback, then retire npm M87\n"
        return [p for p, bad in [("non-zero exit", result.returncode),
                                 ("unexpected output", result.stdout != expected or result.stderr),
                                 ("scratch HOME changed", scratch.tree() != before)] if bad]
    finally:
        scratch.close()


def scenario_handoff(steps, out, gh_delay=0):
    """npm worker live under launchd -> rebuild -> only the Nix daemon owns ~/.m87."""
    scratch = Scratch(out, gh_delay)
    nix_root = steps["nix_root"]
    managed_label = plistlib.loads(steps["plist"].read_bytes())["Label"]
    try:
        node, cli, legacy_plist = install_legacy(scratch, nix_root)
        repos = ["dematom-labs/alteran", "dematom-labs/data-first-jobs", "dematom-labs/infrastructure"]
        scratch.run([node, cli, "init", "--yes", "--plugin", "github", "--github-repo", *repos,
                     "--no-install-service"])
        scratch.run([scratch.launchctl, "bootstrap", f"gui/{os.getuid()}", legacy_plist])
        wait_daemon(scratch, nix_root, LEGACY_LABEL)
        wait_first_sync(scratch)
        # The step that runs right before the handoff on every rebuild.
        scratch.run(["/bin/bash", "-c", "set -eu -o pipefail\nDRY_RUN_CMD=\n" + steps["discovery"]])
        before = snapshot(scratch, nix_root, managed_label)
        (out / "before.json").write_text(json.dumps(before, indent=2))
        handoff = scratch.run([steps["python"], "-c", (
            "import importlib.util, sys\nfrom pathlib import Path\n"
            "spec = importlib.util.spec_from_file_location('handoff', sys.argv[1])\n"
            "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
            "m.migrate(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]), launchctl=sys.argv[5])"),
            steps["script"], scratch.home, nix_root, steps["plist"], scratch.launchctl], timeout=300, check=False)
        after = snapshot(scratch, nix_root, managed_label)
        (out / "after.json").write_text(json.dumps(after, indent=2))
        github = after["plugins"].get("github", {})
        if handoff.returncode:
            try:  # launchd would restart the restored worker; give it time to own ~/.m87 again
                wait_daemon(scratch, nix_root, LEGACY_LABEL)
            except RuntimeError:
                pass
            after = snapshot(scratch, nix_root, managed_label)
            (out / "after.json").write_text(json.dumps(after, indent=2))
            reason = (handoff.stderr.strip().splitlines() or ["no stderr"])[-1]
            rolled_back = (after["legacy_pid"] and after["daemon_pid"] == after["legacy_pid"]
                           and not after["managed_pid"] and not after["managed_plist"]
                           and all(after["plugins"][k]["binary"] == v["binary"] for k, v in before["plugins"].items()))
            return [f"handoff failed: {reason}",
                    "rollback intact (npm worker restored)" if rolled_back else "ROLLBACK BROKEN"]
        managed_plist = scratch.home / f"Library/LaunchAgents/{managed_label}.plist"
        checks = [
            ("commit message missing", "GitHub sync verified" not in handoff.stdout),
            ("managed daemon not running", not after["managed_pid"]),
            ("managed daemon does not own ~/.m87", after["daemon_pid"] != after["managed_pid"]),
            ("npm worker still loaded", after["legacy_pid"]),
            ("installed plist differs from the generation's",
             not managed_plist.exists() or managed_plist.read_bytes() != steps["plist"].read_bytes()),
            ("npm plist/package/shim not retired",
             after["legacy_plist"] or after["legacy_package"] or after["legacy_shim"]),
            ("github plugin not repointed to Nix", not github.get("binary", "").startswith("<nix-m87>/")),
            ("github config lost", github.get("config") != before["plugins"]["github"]["config"]),
            ("sync did not complete",
             github.get("last_sync_at") == before["plugins"]["github"]["last_sync_at"] or github.get("last_error")),
            ("queue lost items", after["items"] < before["items"]),
        ]
        return [problem for problem, bad in checks if bad]
    finally:
        scratch.close()


SCENARIOS = {
    "noop": scenario_noop,
    "dry-run": scenario_dry_run,
    "handoff": scenario_handoff,
    # Real GitHub syncs outlast `m87 plugin sync`'s 15 s wait; 6 list calls x 4 s models that.
    "slow-sync": lambda steps, out: scenario_handoff(steps, out, gh_delay=4),
}


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    generation, out = Path(sys.argv[1]), Path(sys.argv[2])
    names = sys.argv[3:] or list(SCENARIOS)
    steps = parse_activation(generation)
    failed = 0
    for name in names:
        started = time.monotonic()
        try:
            problems = SCENARIOS[name](steps, out / f"m87-{name}")
        except Exception as error:  # a broken setup is a failed journey, not a crash
            problems = [f"setup error: {error}"]
        verdict = "FAIL" if problems else "PASS"
        failed += bool(problems)
        line = f"m87 {name}: {verdict} ({time.monotonic() - started:.0f}s)"
        print(line + "".join(f"\n  - {p}" for p in problems), flush=True)
        (out / f"m87-{name}" / "result.json").write_text(json.dumps({"verdict": verdict, "problems": problems}))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
