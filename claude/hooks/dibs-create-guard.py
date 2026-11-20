"""Claude/Codex PreToolUse hook (Bash): keep agent tasks' resource creates on dibs.

The dibs shims (home.nix) lease or refuse `docker compose up`, `kind create
cluster`, `k3d cluster create`, `docker run -d` and `orb create` when DIBS_TASK
is set. They only see calls that resolve through PATH, so this hook rejects the
create calls that would skip them: an absolute or relative tool path, the
`command`, `env` or `sudo` wrappers, or a PATH= override. It also rejects the
creates dibs cannot lease at all (`docker run -d`, `orb create`) up front.

Only acts when DIBS_TASK is set; every other command passes. Any error of its
own exits 0 with no decision, so the hook can never block a human session.
Exit 2 with a stderr reason is the deny form both Claude Code and Codex honor.
"""

import json
import os
import shlex
import sys

COMPOSE_FILE_HINT = "dibs create --adapter compose --file <compose file>"
SHIM_HINT = "Call the tool by its bare name so the dibs shim on PATH leases it, or run {}"

DOCKER_GLOBAL_VALUE_FLAGS = {"-H", "--host", "-c", "--context", "--config", "-l", "--log-level",
                             "--tlscacert", "--tlscert", "--tlskey"}
COMPOSE_VALUE_FLAGS = {"-f", "--file", "-p", "--project-name", "--project-directory", "--env-file",
                       "--profile", "--ansi", "--progress", "--parallel"}
# `docker run` booleans; mirrors dibs classifyRun: other long flags without `=` take a value.
RUN_BOOL_LONG = {"--detach", "--rm", "--interactive", "--tty", "--init", "--privileged",
                 "--read-only", "--disable-content-trust", "--no-healthcheck", "--oom-kill-disable",
                 "--publish-all", "--quiet", "--help"}
RUN_BOOL_SHORT = set("dtiPq")
# Prefixes that leave the next word as the program: command modifiers and shell reserved words.
SKIPPED_WORDS = {"exec", "nohup", "time", "{", "}", "!", "if", "then", "else", "elif", "while", "until", "do"}
SHELLS = {"sh", "bash", "zsh", "dash"}
WRAPPER_VALUE_FLAGS = {
    "command": {"-p"},
    "env": {"-u", "--unset", "-C", "--chdir", "-a", "--argv0"},
    "sudo": {"-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt",
             "-C", "--close-from", "-D", "--chdir", "-R", "--chroot", "-T", "--command-timeout",
             "-r", "--role", "-t", "--type"},
}


def positionals(args, value_flags):
    out, skip = [], False
    for arg in args:
        if skip:
            skip = False
        elif arg.startswith("-"):
            skip = arg in value_flags
        else:
            out.append(arg)
    return out


def run_detached(args):
    """True when the `docker run` options before the image include -d/--detach."""
    skip = False
    for arg in args:
        if skip:
            skip = False
        elif arg in ("-d", "--detach") or arg.startswith("--detach="):
            return arg != "--detach=false"
        elif arg.startswith("--"):
            skip = arg not in RUN_BOOL_LONG and "=" not in arg
        elif arg.startswith("-") and len(arg) > 1:
            for i, letter in enumerate(arg[1:]):
                if letter == "d":
                    return True
                if letter not in RUN_BOOL_SHORT:
                    skip = i == len(arg) - 2  # a value letter last in the group takes the next arg
                    break
        else:
            return False  # the image; later args belong to the container
    return False


def create_kind(tool, args):
    """Name the create this call performs, or None. Second value: dibs can lease it via the shim."""
    if tool == "docker":
        pos = positionals(args, DOCKER_GLOBAL_VALUE_FLAGS)
        if pos[:1] == ["compose"]:
            rest = args[args.index("compose") + 1:]
            if positionals(rest, COMPOSE_VALUE_FLAGS)[:1] == ["up"]:
                return "docker compose up", True
        if pos[:1] == ["run"] or pos[:2] == ["container", "run"]:
            if run_detached(args[args.index("run") + 1:]):
                return "docker run -d", False
    elif tool == "docker-compose":
        if positionals(args, COMPOSE_VALUE_FLAGS)[:1] == ["up"]:
            return "docker-compose up", False  # dibs installs no docker-compose shim
    elif tool == "kind" and positionals(args, set())[:2] == ["create", "cluster"]:
        return "kind create cluster", True
    elif tool == "k3d" and positionals(args, set())[:2] == ["cluster", "create"]:
        return "k3d cluster create", True
    elif tool in ("orb", "orbctl") and positionals(args, set())[:1] == ["create"]:
        return tool + " create", False
    return None, False


def dibs_command(kind):
    if kind.startswith("kind"):
        return "dibs create --adapter kind"
    if kind.startswith("k3d"):
        return "dibs create --adapter k3d"
    return COMPOSE_FILE_HINT


def reason(kind, bypass):
    if kind == "docker run -d":
        why = "dibs has no adapter for a detached container"
        fix = f"Describe the container in a Compose file and run {COMPOSE_FILE_HINT}, or run it in the foreground with --rm"
    elif kind == "docker-compose up":
        why = "dibs installs no shim for the standalone docker-compose binary"
        fix = f"Use `docker compose up` so the dibs shim leases it, or run {COMPOSE_FILE_HINT}"
    elif kind.endswith("orb create") or kind.endswith("orbctl create"):
        why = "dibs has no OrbStack machine adapter"
        fix = "Lease a Compose project, kind or k3d cluster with dibs create --adapter compose|kind|k3d instead"
    else:
        why = f"{bypass} skips the dibs shim on PATH"
        fix = SHIM_HINT.format(dibs_command(kind))
    return f"DIBS_TASK is set: `{kind}` would create a resource no dibs lease covers ({why}). {fix}."


def segments(command):
    """Split a shell command into simple commands' word lists."""
    # `{`, `}` and `!` are reserved words, not separators (check skips them), so `${VAR}` stays one word.
    punctuation = "();<>|&\n`"
    lex = shlex.shlex(command, posix=True, punctuation_chars=punctuation)
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    segment = []
    for token in lex:
        if token and set(token) <= set(punctuation):
            if segment:
                yield segment
            segment = []
        else:
            segment.append(token)
    if segment:
        yield segment


def check(command, depth=0):
    """Return a deny reason for the first create that bypasses or cannot use dibs, else None."""
    for words in segments(command):
        bypass = None
        while words:
            head = words[0]
            if "=" in head and not head.startswith("-") and head.split("=", 1)[0].isidentifier():
                if head.startswith("PATH="):
                    bypass = "a PATH= override"
                words = words[1:]
            elif head in SKIPPED_WORDS:
                words = words[1:]
            elif head in WRAPPER_VALUE_FLAGS:
                wrapper = head
                bypass = bypass or f"the `{wrapper}` wrapper"
                words = words[1:]
                while words:
                    option = words[0]
                    if wrapper == "env" and option in ("-S", "--split-string"):
                        words = shlex.split(words[1]) + words[2:]
                        continue
                    if wrapper == "env" and option.startswith(("-S", "--split-string=")):
                        split = option[2:] if option.startswith("-S") else option.split("=", 1)[1]
                        words = shlex.split(split) + words[1:]
                        continue
                    if option in WRAPPER_VALUE_FLAGS[wrapper]:
                        words = words[2:]
                    elif option.startswith("-") or (wrapper == "env" and "=" in option):
                        words = words[1:]
                    else:
                        break
            else:
                break
        if not words:
            continue
        program, args = words[0], words[1:]
        tool = os.path.basename(program)
        flag = next((i for i, a in enumerate(args[:-1]) if a[:1] == "-" and a[1:2] != "-" and "c" in a), None)
        if tool in SHELLS and depth < 3 and flag is not None:
            nested = check(args[flag + 1], depth + 1)
            if nested:
                return nested
            continue
        if "/" in program:
            bypass = bypass or f"the path {program}"
        kind, leasable = create_kind(tool, args)
        if kind and (bypass or not leasable):
            return reason(kind, bypass)
    return None


def main():
    try:
        if not os.environ.get("DIBS_TASK"):
            return 0
        payload = json.load(sys.stdin)
        command = (payload.get("tool_input") or {}).get("command")
        if payload.get("tool_name") != "Bash" or not isinstance(command, str):
            return 0
        denial = check(command)
    except Exception:  # fail open: a broken guard must never block a session
        return 0
    if denial:
        print(denial, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
