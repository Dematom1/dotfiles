#!/usr/bin/env python3
"""Run the agent tooling reconciler against synthetic copies of every tool file."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).absolute().parent.parent
script = repo / "scripts/agent-tooling-reconcile.py"
manifest_path = repo / "agent-tooling.json"
manifest = json.loads(manifest_path.read_text())
assert sys.version_info >= (3, 11), "the Codex TOML checks need tomllib"

FAKE_CLAUDE = r'''#!/usr/bin/env python3
import json, os, sys
state_path = os.environ["FAKE_CLAUDE_STATE"]
state = json.load(open(state_path))
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("claude " + " ".join(args) + "\n")
if args == ["plugin", "list", "--json"]:
    print(json.dumps(state["plugins"]))
elif args == ["plugin", "marketplace", "list", "--json"]:
    print(json.dumps(state["marketplaces"]))
elif args[:2] == ["plugin", "uninstall"]:
    state["plugins"] = [p for p in state["plugins"] if not (p["id"] == args[2] and p["scope"] == args[-1] and (args[-1] != "project" or p["projectPath"] == os.getcwd()))]
elif args[:3] == ["plugin", "marketplace", "remove"]:
    state["marketplaces"] = [m for m in state["marketplaces"] if m["name"] != args[3]]
elif args[:3] == ["plugin", "marketplace", "add"]:
    state["marketplaces"].append({"name": args[-1].split("/")[-1], "repo": args[-1]})
elif args[:2] == ["plugin", "install"]:
    state["plugins"].append({"id": args[-1], "scope": "user", "projectPath": None, "enabled": True})
else:
    sys.exit("unexpected claude call: " + " ".join(args))
if not args[-1] == "--json":
    home = __import__("pathlib").Path(os.environ["HOME"])
    registry = home / ".claude/plugins/installed_plugins.json"
    registry.parent.mkdir(parents=True, exist_ok=True)
    registry.write_text(json.dumps({"plugins": state["plugins"]}))
    settings = home / ".claude/settings.json"
    data = json.loads(settings.read_text()) if settings.exists() else {}
    data["enabledPlugins"] = {p["id"]: True for p in state["plugins"] if p["scope"] == "user"}
    settings.write_text(json.dumps(data))
json.dump(state, open(state_path, "w"))
'''

FAKE_NPX = r'''#!/usr/bin/env python3
import os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write("npx " + " ".join(args) + "\n")
skills = args[args.index("--skill") + 1:args.index("-g")]
agents = args[args.index("--agent") + 1:args.index("--copy")]
home = pathlib.Path(os.environ["HOME"])
roots = [home / ".agents/skills"] + ([home / ".claude/skills"] if "claude-code" in agents else [])
for root in roots:
    for skill in skills:
        (root / skill).mkdir(parents=True, exist_ok=True)
        (root / skill / "SKILL.md").write_text(f"---\nname: {skill}\ndescription: fixture\n---\n")
'''

# An AXI tool whose `setup hooks` replaces its own SessionStart hook in both agents.
FAKE_AXI = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write(name + " " + " ".join(args) + "\n")
if args == ["setup", "--help"]:
    print(f"usage: {name} setup hooks")
elif args == ["setup", "hooks"]:
    for relative in [".claude/settings.json", ".codex/hooks.json"]:
        path = pathlib.Path.home() / relative
        settings = json.loads(path.read_text())
        groups = settings.setdefault("hooks", {}).setdefault("SessionStart", [])
        for group in groups:
            group["hooks"] = [h for h in group["hooks"] if name not in h.get("command", "")]
        groups[:] = [g for g in groups if g["hooks"]]
        groups.append({"matcher": "", "hooks": [{"type": "command", "command": name, "timeout": 10}]})
        path.write_text(json.dumps(settings, indent=2) + "\n")
'''

FAKE_INTEGRATION = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
home = pathlib.Path(os.environ["HOME"])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write(name + " " + " ".join(args) + "\n")
if name == "rtk":
    assert args == ["init", "-g", "--hook-only", "--auto-patch"]
    relative, event, command = ".claude/settings.json", "PreToolUse", "rtk hook claude"
else:
    assert args[:2] == ["integration", "install"]
    agent = args[2]
    artifact = home / {"claude": ".claude/hooks/herdr-agent-state.sh",
                       "codex": ".codex/herdr-agent-state.sh",
                       "pi": ".pi/agent/extensions/herdr-agent-state.ts"}[agent]
    artifact.parent.mkdir(parents=True, exist_ok=True)
    artifact.write_text("installed integration\n")
    if agent == "pi":
        sys.exit(0)
    relative = ".claude/settings.json" if agent == "claude" else ".codex/hooks.json"
    event, command = "SessionStart", f"bash '{artifact}' session"
path = home / relative
settings = json.loads(path.read_text()) if path.exists() else {}
groups = settings.setdefault("hooks", {}).setdefault(event, [])
if not any(h.get("command") == command for group in groups for h in group["hooks"]):
    groups.append({"hooks": [{"type": "command", "command": command}]})
path.write_text(json.dumps(settings, indent=2) + "\n")
'''

CODEX_CONFIG = '''# Codex config (fixture)
[features]
hooks = true

[mcp_servers.linear]
url = "https://mcp.linear.app/mcp"

[mcp_servers.headroom]
command = "/fixture/.local/bin/headroom"
args = ["mcp", "serve"]

[mcp_servers.headroom.env]
HEADROOM_TOKEN = "FIXTURE-SECRET"

[projects."/fixture/project"]
trust_level = "trusted"

[hooks.state."/fixture/.codex/hooks.json:session_start:0:0"]
trusted_hash = "sha256:fixture"
'''


def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def check(condition, message):
    if not condition:
        fail(message)


def skill(root, name):
    (root / name).mkdir(parents=True, exist_ok=True)
    (root / name / "SKILL.md").write_text(f"---\nname: {name}\ndescription: fixture\n---\n")


def hook_group(command, matcher=None, **extra):
    group = {"hooks": [{"type": "command", "command": command, **extra}]}
    if matcher is not None:
        group["matcher"] = matcher
    return group


def write_json(path, data, mode=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    if mode is not None:
        os.chmod(path, mode)


def build_home(root):
    home = root / "home"
    xirp = "'/fixture/Library/Application Support/Xirp/xirp-external/hook-scripts/{agent}/{event}.cjs'"
    write_json(home / ".claude.json", {
        "numStartups": 7,
        "mcpServers": {
            "fff": {"type": "stdio", "command": str(home / ".local/bin/fff-mcp"), "args": [], "env": {}},
            "uidotsh": {"type": "http", "url": "https://ui.sh/mcp?agent=claude",
                        "headers": {"Authorization": "Bearer FIXTURE-SECRET"}},
            "headroom": {"type": "stdio", "command": "headroom", "args": ["mcp", "serve"], "env": {}},
            "linear-server": {"type": "http", "url": "https://mcp.linear.app/mcp"},
            "memtrace": {"type": "stdio", "command": "memtrace", "args": ["mcp"], "env": {"MEMTRACE_UI_PORT": "1"}},
            "serena": {"type": "stdio", "command": "uvx", "args": ["serena"], "env": {}},
            "executor": {"type": "stdio", "command": "executor", "args": ["mcp"], "env": {}},
            "superlogical": {"type": "http", "url": "https://www.superlogical.com/rex/community-mcp"},
        },
        "projects": {
            "/fixture/la-saas": {"allowedTools": [], "mcpServers": {
                "linear-server": {"type": "http", "url": "https://mcp.linear.app/mcp"},
                "workos": {"type": "http", "url": "https://mcp.workos.com/mcp"}}},
            "/fixture/infrastructure": {"mcpServers": {
                "notion": {"type": "http", "url": "https://mcp.notion.com/mcp"},
                "linear-server": {"type": "http", "url": "https://mcp.linear.app/mcp"}}},
            "/fixture/plain": {"allowedTools": ["Bash"]},
        },
    })
    write_json(home / ".claude/settings.json", {
        "effortLevel": "high",
        "enabledPlugins": {"adlc@ai-agentic-academy": True, "ponytail@ponytail": True},
        "statusLine": {"type": "command", "command": "/fixture/statusline.sh"},
        "hooks": {
            "PreToolUse": [hook_group("rtk hook claude", "Bash"),
                           hook_group(xirp.format(agent="claude", event="preToolUse"), ".*")],
            "SessionStart": [
                hook_group("/opt/homebrew/bin/gh-axi", "", timeout=10),
                hook_group("chrome-devtools-axi", "", timeout=10),
                hook_group("lavish-axi", "", timeout=10),
                hook_group("bash '/fixture/.claude/hooks/herdr-agent-state.sh' session", "*", timeout=10),
                hook_group(xirp.format(agent="claude", event="sessionStart"), ".*"),
                hook_group("/bin/sh -c 'rex __internal session-start --agent claude 2>/dev/null || true'", timeout=5),
            ],
            "Notification": [hook_group(xirp.format(agent="claude", event="notification"), ".*")],
            "Stop": [hook_group(xirp.format(agent="claude", event="stop"), ".*")],
            "PermissionRequest": [hook_group(xirp.format(agent="claude", event="permissionRequest"), ".*")],
        },
    })
    # The live file has a stray block after its closing brace.
    (home / ".claude/settings.local.json").write_text(
        '{\n  "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "headroom wrap selfheal"}]}]}\n}\n'
        '  "env": {"ANTHROPIC_BASE_URL": "http://127.0.0.1:8787"}\n}\n')
    (home / ".codex").mkdir(parents=True)
    (home / ".codex/config.toml").write_text(CODEX_CONFIG)
    write_json(home / ".codex/hooks.json", {"hooks": {
        "SessionStart": [
            hook_group("/opt/homebrew/bin/gh-axi", "", timeout=10),
            hook_group("chrome-devtools-axi", "", timeout=10),
            hook_group("lavish-axi", "", timeout=10),
            hook_group("bash '/fixture/.codex/herdr-agent-state.sh' session"),
            hook_group(xirp.format(agent="codex", event="sessionStart")),
            hook_group("/bin/sh -c 'rex __internal session-start --agent codex 2>/dev/null || true'"),
        ],
        "PreToolUse": [hook_group(xirp.format(agent="codex", event="preToolUse"))],
        "Stop": [hook_group(xirp.format(agent="codex", event="stop"))],
    }})
    pi_settings = home / ".pi/agent/settings.json"
    write_json(pi_settings, {"theme": "captain-local", "packages": [
        "npm:pi-web-access@0.14.0",
        "npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6",
        "git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055",
        "git:github.com/DietrichGebert/ponytail",
        "npm:pi-autoresearch",
        "git:github.com/michael-denyer/pstack-claude",
        "npm:@ff-labs/pi-fff",
    ]}, mode=0o600)
    (root / "symlink-target").write_text("keep me\n")
    (pi_settings.parent / "settings.json.tmp").symlink_to(root / "symlink-target")

    # Claude's skill root links into the dotfiles checkout, as Home Manager does.
    claude_root = home / "Code/dotfiles/.agents/skills"
    claude_root.mkdir(parents=True)
    (claude_root / ".gitkeep").write_text("")
    (home / ".claude/skills").symlink_to(claude_root)
    shared_root = home / ".agents/skills"
    for source in manifest["skills"]["sources"]:
        for name in source["skills"]:
            skill(shared_root, name)
            if "claude-code" in source["agents"]:
                skill(claude_root, name)
    # The self-referencing link the old relative install left behind.
    shutil.rmtree(claude_root / "codebase-design")
    (claude_root / "codebase-design").symlink_to("../../.agents/skills/codebase-design")
    for name in ["rex", "synced", "design", "find-skills", "vercel-optimize"]:
        skill(claude_root, name)
    for name in ["rex", "adapt", "seo-audit", "frontend-design", "seo-sprint"]:
        skill(shared_root, name)
    write_json(home / ".agents/.skill-lock.json", {"version": 3, "skills": {
        "axi": {"source": "kunchenguid/axi"}, "adapt": {"source": "pbakaus/impeccable"},
        "seo-audit": {"source": "coreyhaines31/marketingskills"}, "find-skills": {"source": "vercel-labs/skills"}}})
    for name in ["workos", "workos-widgets", ".system"]:
        skill(home / ".codex/skills", name)
    pi_root = home / ".pi/agent/skills"
    for name in ["memtrace-first", "vision", "teach"]:
        skill(pi_root, name)
    # A Pi-root copy of a skill the kept pstack-claude package already provides.
    skill(root / "store", "typescript-best-practices")
    (pi_root / "typescript-best-practices").symlink_to(root / "store/typescript-best-practices")
    opencode = home / "Code/dotfiles/opencode/skills"
    opencode.mkdir(parents=True)
    (opencode / "design").symlink_to("../../.agents/skills/design")
    (opencode / "no-mistakes").symlink_to("../../.agents/skills/no-mistakes")
    (home / ".config").mkdir()
    (home / ".config/opencode").symlink_to(home / "Code/dotfiles/opencode")
    # Installed AXI tools: two hook tools from `axi-tools` and the no-hook hey-axi.
    (home / ".nix-profile/bin").mkdir(parents=True)
    for name in ["gh-axi", "tasks-axi", "hey-axi"]:
        (home / ".nix-profile/bin" / name).write_text(FAKE_AXI.replace("#!/usr/bin/env python3", f"#!{sys.executable}", 1))
        os.chmod(home / ".nix-profile/bin" / name, 0o755)
    return home


def fake_bin(root):
    bin_dir = root / "bin"
    bin_dir.mkdir()
    for name, body in [("claude", FAKE_CLAUDE), ("npx", FAKE_NPX)]:
        (bin_dir / name).write_text(body.replace("#!/usr/bin/env python3", f"#!{sys.executable}", 1))
        os.chmod(bin_dir / name, 0o755)
    # The real justfile recipe runs the AXI hook setup; it needs just and node.
    for name in ["just", "node"]:
        (bin_dir / name).symlink_to(shutil.which(name))
    project = root / "home/Code/retired-project"
    write_json(project / ".claude/settings.local.json", {
        "permissions": {"allow": ["Bash"]},
        "hooks": {"SessionStart": [hook_group("headroom selfheal"), hook_group("keep-project-hook")]},
    })
    config = root / "home/.claude.json"
    data = json.loads(config.read_text()) if config.exists() else {}
    data.setdefault("projects", {})[str(project)] = {}
    write_json(config, data)
    state = root / "claude-state.json"
    state.write_text(json.dumps({
        "plugins": [
            {"id": "adlc@ai-agentic-academy", "scope": "user", "projectPath": None, "enabled": True},
            {"id": "posthog@claude-plugins-official", "scope": "user", "projectPath": None, "enabled": True},
            {"id": "playground@claude-plugins-official", "scope": "user", "projectPath": None, "enabled": True},
            {"id": "playground@claude-plugins-official", "scope": "project", "projectPath": str(project), "enabled": True},
            {"id": "pstack@pstack-claude", "scope": "user", "projectPath": None, "enabled": True},
        ],
        "marketplaces": [
            {"name": "ai-agentic-academy", "repo": "dematom1/AIAgenticAcademy"},
            {"name": "claude-plugins-official", "repo": "anthropics/claude-plugins-official"},
            {"name": "memtrace", "url": "https://github.com/syncable-dev/memtrace-public.git"},
            {"name": "pstack-claude", "repo": "michael-denyer/pstack-claude"},
        ],
    }))
    for name in ["installed_plugins.json", "known_marketplaces.json"]:
        write_json(root / "home/.claude/plugins" / name, {"original": name})
    return bin_dir, state


def reconcile(home, bin_dir, state, log, *extra, manifest_file=manifest_path):
    # USER keeps the real /etc/profiles Nix profile out of the AXI tool lookup.
    env = {"HOME": str(home), "USER": "agent-tooling-test", "PATH": f"{bin_dir}:/usr/bin:/bin", "FAKE_CLAUDE_STATE": str(state),
           "FAKE_LOG": str(log)}
    result = subprocess.run([sys.executable, script, "--manifest", manifest_file, *extra],
                            env=env, capture_output=True, text=True, umask=0o022)
    check(result.returncode == 0, f"reconciler exited {result.returncode}: {result.stderr}")
    return result


def snapshot(home):
    files = {}
    for path in sorted(home.rglob("*")):
        relative = str(path.relative_to(home))
        if relative.startswith(".local/state"):
            continue
        if path.is_symlink():
            files[relative] = "link:" + os.readlink(path)
        elif path.is_file():
            files[relative] = path.read_bytes()
    return files


def backups(home):
    base = home / ".local/state/dotfiles/agent-tooling-backups"
    return sorted(base.iterdir()) if base.exists() else []


def calls(log):
    return log.read_text().splitlines() if log.exists() else []


def mutating(lines):
    """Plugin and skill installs; AXI `setup hooks` rerun every time and must converge."""
    return [line for line in lines if line.startswith(("claude ", "npx ")) and not line.endswith("--json")]


def hook_commands(settings, event):
    return [h["command"] for group in settings["hooks"].get(event, []) for h in group["hooks"]]


with tempfile.TemporaryDirectory(dir=repo, prefix=".agent-tooling-") as directory:
    root = Path(directory)
    home = build_home(root)
    bin_dir, state = fake_bin(root)
    log = root / "calls.log"
    (home / ".agents/skills/teach/SKILL.md").write_text("locally customized sibling skill\n")
    (home / ".codex").chmod(0o700)
    (home / ".codex/config.toml").chmod(0o644)
    nested_skill = home / ".agents/skills/teach/references/nested"
    nested_skill.mkdir(parents=True)
    nested_skill.parent.chmod(0o755)
    nested_skill.chmod(0o755)
    (nested_skill / "private.txt").write_text("private fixture\n")
    (nested_skill / "private.txt").chmod(0o600)
    (nested_skill / "reference").symlink_to("private.txt")
    initial = snapshot(home)

    # Dry run: reports, changes nothing, calls nothing that mutates.
    result = reconcile(home, bin_dir, state, log, "--dry-run")
    check(snapshot(home) == initial, "dry run changed files")
    check(not backups(home), "dry run created a backup")
    check(not mutating(calls(log)), f"dry run ran mutating commands: {mutating(calls(log))}")
    check("would update" in result.stdout and "would remove" in result.stdout, "dry run reported no plan")
    log.unlink()

    # First run: converge on the manifest.
    result = reconcile(home, bin_dir, state, log)
    first_calls = calls(log)
    claude_json = json.loads((home / ".claude.json").read_text())
    check(set(claude_json["mcpServers"]) == {"fff", "superlogical", "uidotsh"},
          f"Claude user MCP servers: {sorted(claude_json['mcpServers'])}")
    check(claude_json["mcpServers"]["uidotsh"]["headers"] == {"Authorization": "Bearer FIXTURE-SECRET"},
          "uidotsh lost its existing auth header")
    check(claude_json["numStartups"] == 7, "unrelated ~/.claude.json keys changed")
    projects = claude_json["projects"]
    check(set(projects["/fixture/la-saas"]["mcpServers"]) == {"workos"}, "la-saas project MCP servers")
    check(set(projects["/fixture/infrastructure"]["mcpServers"]) == {"notion"}, "infrastructure project MCP servers")
    check(projects["/fixture/plain"] == {"allowedTools": ["Bash"]}, "project without MCP servers changed")

    settings = json.loads((home / ".claude/settings.json").read_text())
    check(settings["effortLevel"] == "high" and settings["statusLine"]["command"] == "/fixture/statusline.sh",
          "unrelated Claude settings changed")
    check(sorted(hook_commands(settings, "SessionStart")) == sorted([
        json.dumps(str(home / ".nix-profile/bin/gh-axi")), "chrome-devtools-axi", "tasks-axi",
        "bash '/fixture/.claude/hooks/herdr-agent-state.sh' session",
        "/bin/sh -c 'rex __internal session-start --agent claude 2>/dev/null || true'",
    ]), f"Claude SessionStart hooks: {hook_commands(settings, 'SessionStart')}")
    for tool in ["gh-axi", "tasks-axi"]:
        check(f"{tool} setup hooks" in first_calls, f"{tool} hooks were not registered")
    check(not any(line.startswith(("hey-axi", "lavish-axi")) for line in first_calls),
          "a no-hook AXI tool was set up")
    check(hook_commands(settings, "PreToolUse") == ["rtk hook claude"], "Claude PreToolUse hooks")
    check(set(settings["hooks"]) == {"SessionStart", "PreToolUse"}, f"Claude hook events: {sorted(settings['hooks'])}")
    check("Xirp" not in json.dumps(settings), "Xirp hooks survived in Claude settings")
    check((home / ".claude/settings.local.json").read_bytes() == initial[".claude/settings.local.json"],
          "invalid settings.local.json was rewritten")
    check("settings.local.json is not valid JSON" in result.stderr, "invalid settings.local.json gave no warning")

    import tomllib
    codex_text = (home / ".codex/config.toml").read_text()
    codex = tomllib.loads(codex_text)
    check("mcp_servers" not in codex, f"Codex MCP servers survived: {codex.get('mcp_servers')}")
    check(codex["features"] == {"hooks": True} and "/fixture/project" in codex["projects"]
          and codex["hooks"]["state"], "unrelated Codex config changed")
    check(codex_text.startswith("# Codex config (fixture)\n"), "Codex config comment was lost")
    check("FIXTURE-SECRET" not in codex_text, "removed Codex server env survived")
    codex_hooks = json.loads((home / ".codex/hooks.json").read_text())
    check(sorted(hook_commands(codex_hooks, "SessionStart")) == sorted([
        json.dumps(str(home / ".nix-profile/bin/gh-axi")), "chrome-devtools-axi", "tasks-axi",
        "bash '/fixture/.codex/herdr-agent-state.sh' session",
        "/bin/sh -c 'rex __internal session-start --agent codex 2>/dev/null || true'",
    ]), f"Codex SessionStart hooks: {hook_commands(codex_hooks, 'SessionStart')}")
    check(set(codex_hooks["hooks"]) == {"SessionStart"}, "Codex Xirp hook events survived")

    pi_settings = home / ".pi/agent/settings.json"
    pi = json.loads(pi_settings.read_text())
    check(pi["packages"] == manifest["pi"]["packages"], f"Pi packages: {pi['packages']}")
    check(pi["theme"] == "captain-local", "unrelated Pi settings changed")
    check(pi_settings.stat().st_mode & 0o777 == 0o600, "Pi settings lost their private mode")
    check((root / "symlink-target").read_text() == "keep me\n", "a predictable temp-file symlink was followed")

    claude_root = home / "Code/dotfiles/.agents/skills"
    claude_names = {p.name for p in claude_root.iterdir()}
    expected_claude = {s for src in manifest["skills"]["sources"] if "claude-code" in src["agents"]
                       for s in src["skills"]} | {"rex", "synced", ".gitkeep"}
    check(claude_names == expected_claude, f"Claude skills: {sorted(claude_names ^ expected_claude)}")
    check((claude_root / "codebase-design/SKILL.md").is_file()
          and not (claude_root / "codebase-design").is_symlink(), "self-referencing skill link was not reinstalled")
    shared_names = {p.name for p in (home / ".agents/skills").iterdir()}
    check(not shared_names & {"seo-audit", "frontend-design", "seo-sprint", "adapt"}, "removed shared skills survived")
    check({"rex", "axi", "impeccable", "lavish"} <= shared_names, "kept shared skills were removed")
    check({p.name for p in (home / ".codex/skills").iterdir()} == {".system"}, "Codex-only skills")
    check({p.name for p in (home / ".pi/agent/skills").iterdir()} == set(),
          "Pi-root skills")
    check(sorted(p.name for p in (home / "Code/dotfiles/opencode/skills").iterdir()) == ["no-mistakes"],
          "dangling OpenCode skill links")
    lock = json.loads((home / ".agents/.skill-lock.json").read_text())
    check(set(lock["skills"]) == {"axi"}, f"skill lock entries: {sorted(lock['skills'])}")

    plugin_state = json.loads(state.read_text())
    check({(p["id"], p["scope"]) for p in plugin_state["plugins"]} == {
        ("ponytail@ponytail", "user"), ("pstack@pstack-claude", "user")},
        f"Claude plugins: {plugin_state['plugins']}")
    check({m["name"] for m in plugin_state["marketplaces"]} == set(manifest["claude"]["marketplaces"]),
          f"Claude marketplaces: {plugin_state['marketplaces']}")
    npx_calls = [line for line in first_calls if line.startswith("npx ")]
    check(len(npx_calls) == 1 and "skills add mattpocock/skills --skill" in npx_calls[0]
          and npx_calls[0].endswith("--copy"), f"skill installs: {npx_calls}")

    taken = backups(home)
    check(len(taken) == 1, f"expected one backup directory, got {taken}")
    backup_root = taken[0]
    for directory in [backup_root, *backup_root.rglob("*")]:
        if directory.is_dir() and not directory.is_symlink():
            check(directory.stat().st_mode & 0o777 == 0o700,
                  f"backup directory is not private: {directory}")
    config_backup = backup_root / ".codex/config.toml"
    check(config_backup.stat().st_mode & 0o777 == 0o644, "backup changed source file permissions")
    check(all(parent.stat().st_mode & 0o077 == 0
              for parent in [backup_root, config_backup.parent]),
          "other users can traverse to the copied Codex credentials")
    private_backup = backup_root / ".agents/skills/teach/references/nested/private.txt"
    check(private_backup.read_text() == "private fixture\n", "nested private backup lost content")
    check(private_backup.stat().st_mode & 0o077 == 0, "private copied file is readable by others")
    check(os.readlink(private_backup.parent / "reference") == "private.txt", "backup changed a nested symlink")
    check(nested_skill.stat().st_mode & 0o777 == 0o755, "backup changed source directory permissions")
    for relative in [".claude.json", ".claude/settings.json", ".codex/config.toml", ".codex/hooks.json",
                     ".pi/agent/settings.json", ".agents/.skill-lock.json",
                     ".claude/plugins/installed_plugins.json", ".claude/plugins/known_marketplaces.json"]:
        check((taken[0] / relative).read_bytes() == initial[relative], f"backup of {relative} is not the original")
    for relative in [".claude/skills/design/SKILL.md", ".agents/skills/seo-audit/SKILL.md",
                     ".codex/skills/workos/SKILL.md", ".pi/agent/skills/memtrace-first/SKILL.md"]:
        check((taken[0] / relative).is_file(), f"removed {relative} was not backed up")
    check("FIXTURE-SECRET" in (taken[0] / ".codex/config.toml").read_text(), "backup lost content")

    project_settings = json.loads((home / "Code/retired-project/.claude/settings.local.json").read_text())
    check(hook_commands(project_settings, "SessionStart") == ["keep-project-hook"], "project hook cleanup")
    check(project_settings["permissions"] == {"allow": ["Bash"]}, "project permissions changed")
    check((taken[0] / "Code/retired-project/.claude/settings.local.json").read_bytes()
          == initial["Code/retired-project/.claude/settings.local.json"], "project backup changed")
    check((taken[0] / ".agents/skills/teach/SKILL.md").read_bytes()
          == initial[".agents/skills/teach/SKILL.md"], "overwritten sibling skill was not saved")

    # Second run: nothing left to do.
    converged = snapshot(home)
    log.unlink()
    result = reconcile(home, bin_dir, state, log)
    check(snapshot(home) == converged, "second run changed files")
    check(backups(home) == taken, "second run created another backup")
    check(not mutating(calls(log)), f"second run ran mutating commands: {mutating(calls(log))}")
    check("updated" not in result.stdout and "removed" not in result.stdout, f"second run reported changes: {result.stdout}")
    check("tasks-axi setup hooks" in calls(log), "second run did not re-register AXI hooks")

    # Unparsable files are left alone, and the other tools still converge.
    broken = root / "broken"
    broken_home = broken / "home"
    (broken_home / ".pi/agent").mkdir(parents=True)
    (broken_home / ".claude.json").write_text('{"mcpServers": {')
    write_json(broken_home / ".pi/agent/settings.json", {"packages": ["npm:pi-autoresearch"]})
    (broken_home / ".codex").mkdir()
    (broken_home / ".codex/config.toml").write_text("[mcp_servers.linear\n")
    # Without just, the AXI lists are unknown, so no hook may be judged undeclared.
    unread_hooks = json.dumps({"hooks": {"SessionStart": [hook_group("tasks-axi")]}})
    (broken_home / ".codex/hooks.json").write_text(unread_hooks)
    result = reconcile(broken_home, root / "no-bin", state, broken / "calls.log")
    check((broken_home / ".codex/hooks.json").read_text() == unread_hooks, "hooks were reconciled without the AXI lists")
    check("cannot read the AXI tool lists" in result.stderr, "missing AXI lists gave no warning")
    check((broken_home / ".claude.json").read_text() == '{"mcpServers": {', "invalid ~/.claude.json was rewritten")
    check((broken_home / ".codex/config.toml").read_text() == "[mcp_servers.linear\n", "invalid Codex config was rewritten")
    check(".claude.json is not valid JSON" in result.stderr and "config.toml is not valid TOML" in result.stderr,
          f"parse errors gave no warnings: {result.stderr}")
    check(json.loads((broken_home / ".pi/agent/settings.json").read_text())["packages"] == manifest["pi"]["packages"],
          "a parse error in one tool blocked the others")

    # Codex: declared servers are added or updated in place, keeping their secrets.
    codex_home = root / "codex/home"
    (codex_home / ".codex").mkdir(parents=True)
    (codex_home / ".codex/config.toml").write_text(
        'model = "o5"\n\n# docs server\n[mcp_servers.docs]\nurl = "https://old.example/mcp"\n\n'
        '[mcp_servers.docs.env]\nDOCS_TOKEN = "FIXTURE-SECRET"\n\n[mcp_servers.stale]\ncommand = "stale"\n')
    variant = dict(manifest, codex={**manifest["codex"], "mcpServers": {
        "docs": {"url": "https://docs.example/mcp"},
        "local": {"command": "~/.local/bin/local-mcp", "args": ["serve"], "enabled": True}}})
    variant_path = root / "codex/manifest.json"
    variant_path.write_text(json.dumps(variant))
    reconcile(codex_home, root / "no-bin", state, root / "codex/calls.log", manifest_file=variant_path)
    codex = tomllib.loads((codex_home / ".codex/config.toml").read_text())
    check(codex["model"] == "o5", "unrelated Codex keys changed")
    check(codex["mcp_servers"] == {
        "docs": {"url": "https://docs.example/mcp", "env": {"DOCS_TOKEN": "FIXTURE-SECRET"}},
        "local": {"command": str(codex_home / ".local/bin/local-mcp"), "args": ["serve"], "enabled": True},
    }, f"Codex declared servers: {codex['mcp_servers']}")
    converged_codex = (codex_home / ".codex/config.toml").read_text()
    reconcile(codex_home, root / "no-bin", state, root / "codex/calls.log", manifest_file=variant_path)
    check((codex_home / ".codex/config.toml").read_text() == converged_codex, "Codex reconcile is not idempotent")

    fresh_home = root / "fresh/home"
    fresh_home.mkdir(parents=True)
    result = reconcile(fresh_home, bin_dir, state, root / "fresh/calls.log", manifest_file=variant_path,
                       *["--justfile", str(repo / "justfile")])
    check(set(json.loads((fresh_home / ".claude.json").read_text())["mcpServers"]) == {"fff", "superlogical", "uidotsh"},
          "fresh Claude MCP configuration missing")
    check(json.loads((fresh_home / ".pi/agent/settings.json").read_text())["packages"] == manifest["pi"]["packages"],
          "fresh Pi packages missing")
    for name in [".claude/settings.json", ".codex/hooks.json"]:
        check(hook_commands(json.loads((fresh_home / name).read_text()), "SessionStart"), "fresh hooks missing")
    check(set(tomllib.loads((fresh_home / ".codex/config.toml").read_text())["mcp_servers"]) == {"docs", "local"},
          "fresh Codex MCP configuration missing")

    # A wiped ~/.claude.json gets uidotsh back without credentials, never the token from a backup.
    wiped_home = root / "wiped/home"
    write_json(wiped_home / ".local/state/dotfiles/agent-tooling-backups/20260101T000000Z/.claude.json",
               {"mcpServers": {"uidotsh": {"type": "http", "url": "https://ui.sh/mcp?agent=claude",
                                           "headers": {"Authorization": "Bearer FIXTURE-SECRET"}}}})
    write_json(wiped_home / ".claude.json", {"mcpServers": {"fff": {"type": "stdio", "command": "fff-mcp"}}})
    reauth = ("uidotsh needs re-authentication (lacks Authorization); run `claude mcp remove -s user uidotsh && "
              "claude mcp add -s user -t http uidotsh 'https://ui.sh/mcp?agent=claude' -H 'Authorization: Bearer <token>'`")
    result = reconcile(wiped_home, root / "no-bin", state, root / "wiped/calls.log")
    wiped_text = (wiped_home / ".claude.json").read_text()
    restored = json.loads(wiped_text)["mcpServers"]
    check(restored.get("uidotsh") == {"type": "http", "url": "https://ui.sh/mcp?agent=claude"},
          f"uidotsh was not recreated without credentials: {restored}")
    check(set(restored) == {"fff", "superlogical", "uidotsh"}, f"wiped Claude MCP servers: {restored}")
    check("FIXTURE-SECRET" not in wiped_text, "a backed-up token was copied into ~/.claude.json")
    check(result.stderr.count(reauth) == 1, f"missing re-authentication notice: {result.stderr}")
    result = reconcile(wiped_home, root / "no-bin", state, root / "wiped/calls.log")
    check((wiped_home / ".claude.json").read_text() == wiped_text, "uidotsh recreation is not idempotent")
    check(result.stderr.count(reauth) == 1, f"re-authentication notice not repeated: {result.stderr}")

    integrations = root / "integrations"
    integration_home = integrations / "home"
    integration_home.mkdir(parents=True)
    integration_bin = integrations / "bin"
    integration_bin.mkdir()
    (integration_bin / "just").symlink_to(shutil.which("just"))
    integration_log = integrations / "calls.log"
    for name in ["rtk", "herdr"]:
        executable = integration_bin / name
        executable.write_text(FAKE_INTEGRATION.replace("#!/usr/bin/env python3", f"#!{sys.executable}", 1))
        executable.chmod(0o755)
    result = reconcile(integration_home, integration_bin, state, integration_log)
    check("failed:" not in result.stderr, result.stderr)
    for agent in ["claude", "codex", "pi"]:
        check(f"herdr integration install {agent}" in calls(integration_log), f"missing herdr {agent}")
    check("rtk init -g --hook-only --auto-patch" in calls(integration_log), "rtk installer missing")
    integrated = snapshot(integration_home)
    integration_backups = backups(integration_home)
    reconcile(integration_home, integration_bin, state, integration_log)
    check(snapshot(integration_home) == integrated, "integration installers do not converge")
    check(backups(integration_home) == integration_backups, "converged installers kept another backup")
    for name in [".claude/settings.json", ".codex/hooks.json"]:
        (integration_home / name).write_text("{invalid")
    integration_log.unlink()
    result = reconcile(integration_home, integration_bin, state, integration_log)
    check(not any(line.startswith("rtk ") or line.endswith(("install claude", "install codex"))
                  for line in calls(integration_log)), "installer touched malformed hook configuration")
    for name in [".claude/settings.json", ".codex/hooks.json"]:
        check((integration_home / name).read_text() == "{invalid", "malformed hook state changed")

    # A layout the line editor cannot express safely is reported, not mangled.
    inline_home = root / "inline/home"
    (inline_home / ".codex").mkdir(parents=True)
    inline = 'mcp_servers = { linear = { url = "https://mcp.linear.app/mcp" } }\n'
    (inline_home / ".codex/config.toml").write_text(inline)
    result = reconcile(inline_home, root / "no-bin", state, root / "inline/calls.log")
    check((inline_home / ".codex/config.toml").read_text() == inline, "inline Codex MCP table was rewritten")
    check("layout this reconciler does not edit" in result.stderr, "unsupported Codex layout gave no warning")

print("agent tooling reconcile checks passed")
