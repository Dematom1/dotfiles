#!/usr/bin/env python3
"""Stand-in for /bin/launchctl that runs jobs as plain child processes.

Implements only the calls scripts/m87-remove-npm-daemon.py makes: print,
bootout --wait, bootstrap. Every path under the real home is rewritten into the
scratch home, and a job that would still reach the real home is refused, so a
scratch run can never start a daemon against the live ~/.m87.

Environment: FAKE_LAUNCHD_DIR (job state), FAKE_LAUNCHD_HOME (scratch home),
FAKE_LAUNCHD_REAL_HOME, FAKE_LAUNCHD_EXTRA_ENV (JSON merged into job env).
"""
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time

state = Path(os.environ["FAKE_LAUNCHD_DIR"])
scratch = os.environ["FAKE_LAUNCHD_HOME"]
real = os.environ["FAKE_LAUNCHD_REAL_HOME"].rstrip("/")
state.mkdir(parents=True, exist_ok=True)
with open(state / "calls.log", "a") as log:
    log.write(" ".join(sys.argv[1:]) + "\n")


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    # A zombie is dead for launchd purposes.
    stat = subprocess.run(["/bin/ps", "-o", "stat=", "-p", str(pid)],
                          capture_output=True, text=True).stdout.strip()
    return bool(stat) and not stat.startswith("Z")


def job(target):
    label = target.rsplit("/", 1)[-1]
    return label, state / f"{label}.pid"


def rewrite(value):
    if isinstance(value, str):
        value = value.replace(real + "/", scratch + "/")
        if value == real or real + "/" in value:
            sys.exit(f"fake-launchctl: refusing job that still reaches {real}")
        return value
    if isinstance(value, list):
        return [rewrite(item) for item in value]
    if isinstance(value, dict):
        return {key: rewrite(item) for key, item in value.items()}
    return value


command = sys.argv[1] if len(sys.argv) > 1 else ""
if command == "print":
    label, pidfile = job(sys.argv[2])
    if not pidfile.exists():
        print(f'Could not find service "{label}" in domain for user gui: {os.getuid()}', file=sys.stderr)
        sys.exit(113)
    pid = int(pidfile.read_text())
    print(f"{sys.argv[2]} = {{")
    print("\tstate = running" if alive(pid) else "\tstate = not running")
    if alive(pid):
        print(f"\tpid = {pid}")
    print("}")
elif command == "bootout":
    label, pidfile = job(sys.argv[-1])
    if not pidfile.exists():
        print(f"Boot-out failed: 3: No such process", file=sys.stderr)
        sys.exit(3)
    pid = int(pidfile.read_text())
    if alive(pid):
        os.killpg(pid, signal.SIGTERM)
        deadline = time.monotonic() + 10
        while alive(pid) and time.monotonic() < deadline:
            time.sleep(0.1)
        if alive(pid):
            os.killpg(pid, signal.SIGKILL)
    pidfile.unlink()
elif command == "bootstrap":
    config = rewrite(plistlib.loads(Path(sys.argv[3]).read_bytes()))
    label, pidfile = job(config["Label"])
    if pidfile.exists():
        print("Bootstrap failed: 5: Input/output error", file=sys.stderr)
        sys.exit(5)
    env = {"HOME": scratch, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
           **config.get("EnvironmentVariables", {}),
           **json.loads(os.environ.get("FAKE_LAUNCHD_EXTRA_ENV", "{}"))}
    output = config.get("StandardOutPath", str(state / f"{label}.log"))
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    with open(output, "ab") as stream:
        process = subprocess.Popen(config["ProgramArguments"], env=env, stdin=subprocess.DEVNULL,
                                   stdout=stream, stderr=stream, cwd="/", start_new_session=True)
    pidfile.write_text(str(process.pid))
else:
    print(f"fake-launchctl: unsupported call: {' '.join(sys.argv[1:])}", file=sys.stderr)
    sys.exit(64)
