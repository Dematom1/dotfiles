#!/usr/bin/env python3
"""Reconcile agent tool state to the declared set in agent-tooling.json.

Each tool keeps owning its files. This edits only the keys the manifest
declares, backs a file up before rewriting it, and leaves a file it cannot
parse untouched with a warning. Running it twice changes nothing the second
time. Secrets are never read from the manifest: an MCP server's existing
headers and env survive, and a server that needs auth is never created
without it.

AXI tools are the exception: their lists stay in the justfile (`axi-tools`,
`axi-tools-work`, `axi-tools-git`; `axi-tools-no-hooks` get none). Each
installed hook tool registers its own hooks through `just _setup-axi-hooks`,
and those hooks are kept.

Home Manager activation runs the full reconcile; `just update-skills` runs
`--refresh-skills`, which only reinstalls every declared skill source.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = Path(os.environ["HOME"])
ALL_AGENTS_ROOT = "shared"
INSTALL_TIMEOUT = 600
warnings: list[str] = []


def warn(message: str) -> None:
    warnings.append(message)
    print(f"agent-tooling: WARNING: {message}", file=sys.stderr)


def note(message: str) -> None:
    print(f"agent-tooling: {message}")


class Run:
    def __init__(self, dry_run: bool, stream: bool = False, manifest: dict | None = None) -> None:
        self.dry_run = dry_run
        self.stream = stream  # show command output live instead of only on failure
        self.backup_root: Path | None = None
        self.prepared = False
        self.originals = {}
        self.paths = [HOME / name for name in [
            ".claude.json", ".claude/settings.json", ".claude/settings.local.json",
            ".claude/plugins/installed_plugins.json", ".claude/plugins/known_marketplaces.json",
            ".codex/config.toml", ".codex/hooks.json", ".pi/agent/settings.json",
            ".agents/.skill-lock.json", ".claude/hooks/herdr-agent-state.sh",
            ".codex/herdr-agent-state.sh", ".pi/agent/extensions/herdr-agent-state.ts",
        ]]
        if manifest is not None:
            for root, _ in skill_roots(manifest).values():
                if root.is_dir():
                    self.paths.extend(root.iterdir())
            root = HOME / ".config/opencode/skills"
            if root.is_dir():
                self.paths.extend(root.iterdir())
            self.paths.extend(project / ".claude/settings.local.json"
                              for project in project_paths(manifest))

    def prepare(self) -> None:
        if self.prepared or self.dry_run:
            return
        for path in dict.fromkeys(self.paths):
            self.originals[path] = fingerprint(path)
            if path.is_file():
                shutil.copy2(path, self.backup_target(path))
            elif path.is_symlink():
                self.backup_target(path).symlink_to(os.readlink(path))
            elif path.is_dir():
                copy_private_tree(path, self.backup_target(path))
        self.prepared = True

    def finish(self) -> None:
        if self.backup_root and all(fingerprint(path) == original
                                    for path, original in self.originals.items()):
            shutil.rmtree(self.backup_root)

    def backup_dir(self) -> Path:
        if self.backup_root is None:
            state = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state")
            base = state / "dotfiles/agent-tooling-backups"
            stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
            candidate, n = base / stamp, 1
            while candidate.exists():
                candidate, n = base / f"{stamp}-{n}", n + 1
            candidate.mkdir(mode=0o700, parents=True)
            self.backup_root = candidate
            note(f"backups in {candidate}")
        return self.backup_root

    def backup_target(self, path: Path) -> Path:
        absolute = Path(os.path.abspath(path))
        try:
            relative = absolute.relative_to(HOME)
        except ValueError:
            relative = absolute.relative_to(absolute.anchor)
        parent = self.backup_dir()
        for part in relative.parts[:-1]:
            parent = parent / part
            parent.mkdir(mode=0o700, exist_ok=True)
        return parent / relative.name

    def write_text(self, path: Path, text: str, summary: str) -> None:
        if self.dry_run:
            note(f"would update {path}: {summary}")
            return
        real = Path(os.path.realpath(path))
        self.prepare()
        mode = real.stat().st_mode & 0o7777 if real.exists() else 0o600
        real.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=f".{real.name}.", dir=real.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(text)
            os.chmod(tmp, mode)
            os.replace(tmp, real)
        except BaseException:
            os.unlink(tmp)
            raise
        note(f"updated {path}: {summary}")

    def move_away(self, path: Path, why: str) -> None:
        if self.dry_run:
            note(f"would remove {path} ({why})")
            return
        self.prepare()
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()
        note(f"removed {path} ({why})")

    def command(self, argv: list[str], why: str, timeout: int = 120, cwd: Path | None = None) -> bool:
        if self.dry_run:
            note(f"would run: {' '.join(argv)}")
            return True
        self.prepare()
        note(f"{why}: {' '.join(argv)}")
        output = None if self.stream else subprocess.PIPE
        try:
            result = subprocess.run(argv, cwd=cwd or HOME, timeout=timeout, stdin=subprocess.DEVNULL,
                                    stdout=output, stderr=subprocess.STDOUT, text=True)
        except (OSError, subprocess.TimeoutExpired) as error:
            warn(f"{' '.join(argv)} failed: {error}")
            return False
        if result.returncode != 0:
            warn(f"{' '.join(argv)} exited {result.returncode}: {(result.stdout or '').strip()[-500:]}")
            return False
        return True


def copy_private_tree(source: Path, target: Path) -> None:
    target.mkdir(mode=0o700)
    for entry in source.iterdir():
        destination = target / entry.name
        if entry.is_symlink():
            destination.symlink_to(os.readlink(entry))
        elif entry.is_dir():
            copy_private_tree(entry, destination)
        else:
            shutil.copy2(entry, destination)


def fingerprint(path: Path):
    if path.is_symlink():
        return ("link", os.readlink(path), path.read_bytes() if path.is_file() else None)
    if path.is_dir():
        return {p.name: fingerprint(p) for p in path.iterdir()}
    if path.is_file():
        return (path.stat().st_mode, path.read_bytes())
    return None


def project_paths(manifest: dict) -> set[Path]:
    paths = {Path(expand(p)) for p in manifest["claude"].get("projectPaths", [])}
    loaded = load_json(HOME / ".claude.json")
    if loaded and isinstance(loaded[0].get("projects"), dict):
        paths.update(Path(p) for p in loaded[0]["projects"])
    return {p for p in paths if p.is_absolute() and p.is_dir()}


def load_json(path: Path, create: bool = False):
    """Parsed JSON and its original text, or None when absent or unparsable."""
    if not path.exists() and not path.is_symlink():
        return ({}, "\n") if create else None
    text = path.read_text(encoding="utf-8")
    try:
        data = json.loads(text)
        if not isinstance(data, dict):
            warn(f"{path} is not a JSON object; left untouched")
            return None
        return data, text
    except json.JSONDecodeError as error:
        warn(f"{path} is not valid JSON ({error}); left untouched")
        return None


def dump_json(data, original: str) -> str:
    text = json.dumps(data, indent=2, ensure_ascii=False)
    return text + "\n" if original.endswith("\n") else text


def expand(value):
    if isinstance(value, str) and value.startswith("~/"):
        return str(HOME / value[2:])
    if isinstance(value, list):
        return [expand(item) for item in value]
    return value


def desired_servers(current: dict, declared: dict, where: str) -> dict:
    """Declared fields win; fields the manifest leaves out (headers, env) survive."""
    result = {}
    for name, spec in current.items():
        if name not in declared:
            continue
        merged = {**spec, **{k: expand(v) for k, v in declared[name].items() if k != "requiredHeaders"}}
        missing = [h for h in declared[name].get("requiredHeaders", []) if h not in merged.get("headers", {})]
        if missing:
            warn(f"{where} MCP server {name} lacks {', '.join(missing)}; re-run its auth setup")
        result[name] = merged
    for name, spec in declared.items():
        if name in result:
            continue
        if spec.get("requiredHeaders"):
            warn(f"{where} MCP server {name} is declared but absent; add it with its own auth flow "
                 f"(see README 'Declarative agent tooling')")
            continue
        result[name] = {k: expand(v) for k, v in spec.items()}
    return result


def reconcile_claude_json(run: Run, manifest: dict) -> None:
    path = HOME / ".claude.json"
    loaded = load_json(path, create=True)
    if loaded is None:
        return
    data, original = loaded
    claude = manifest["claude"]
    changes = []
    current = data.get("mcpServers") or {}
    desired = desired_servers(current, claude["mcpServers"], "Claude")
    if desired != current:
        removed = sorted(set(current) - set(desired))
        added = sorted(set(desired) - set(current))
        changes.append(f"user MCP servers -{removed} +{added}" if removed or added else "user MCP servers updated")
        data["mcpServers"] = desired
    retired = set(claude["retiredProjectMcpServers"])
    for project, settings in (data.get("projects") or {}).items():
        servers = settings.get("mcpServers") if isinstance(settings, dict) else None
        if not servers or not retired & set(servers):
            continue
        dropped = sorted(retired & set(servers))
        settings["mcpServers"] = {k: v for k, v in servers.items() if k not in retired}
        changes.append(f"{project} MCP servers -{dropped}")
    if changes:
        run.write_text(path, dump_json(data, original), "; ".join(changes))


def hook_text(hook: dict) -> str:
    return str(hook.get("command") or hook.get("url") or hook.get("prompt") or "")


def reconcile_hooks(hooks: dict, policy: dict) -> dict:
    """Keep hooks matching a `keep` pattern, normalize each `ensure` entry, drop the rest."""
    ensure = policy["ensure"]
    keep = policy["keep"]
    result: dict = {}
    slots: dict[int, tuple[str, int]] = {}
    for event, groups in hooks.items():
        new_groups = []
        for group in groups if isinstance(groups, list) else []:
            kept = []
            for hook in group.get("hooks", []) if isinstance(group, dict) else []:
                text = hook_text(hook) if isinstance(hook, dict) else ""
                owner = next((i for i, e in enumerate(ensure) if e["event"] == event and e["match"] in text), None)
                if owner is not None:
                    slots.setdefault(owner, (event, len(new_groups)))
                elif any(pattern in text for pattern in keep):
                    kept.append(hook)
            if kept:
                new_groups.append({**group, "hooks": kept})
        result[event] = new_groups
    # Insert from the back so earlier slot positions stay valid.
    placements = []
    for index, entry in enumerate(ensure):
        event, position = slots.get(index, (entry["event"], len(result.get(entry["event"], []))))
        placements.append((event, position, index, {"matcher": entry["matcher"], "hooks": [entry["hook"]]}))
    for event, position, _, group in sorted(placements, key=lambda p: (p[0], p[1], p[2]), reverse=True):
        result.setdefault(event, []).insert(position, group)
    return {event: groups for event, groups in result.items() if groups}


def reconcile_hook_file(run: Run, path: Path, policy: dict) -> None:
    loaded = load_json(path, create=True)
    if loaded is None:
        return
    data, original = loaded
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        if not policy["ensure"]:
            return
        hooks = {}
    desired = reconcile_hooks(hooks, policy)
    if desired == hooks:
        return
    before = sorted({hook_text(h) for g in hooks.values() for grp in g for h in grp.get("hooks", [])})
    after = sorted({hook_text(h) for g in desired.values() for grp in g for h in grp.get("hooks", [])})
    data["hooks"] = desired
    summary = f"hooks -{sorted(set(before) - set(after))} +{sorted(set(after) - set(before))}"
    run.write_text(path, dump_json(data, original), summary)


TABLE_HEADER = re.compile(r"^\s*\[")
SERVER_HEADER = re.compile(
    r"""^\s*\[\s*mcp_servers\s*\.\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z0-9_-]+))\s*[.\]]""")


def toml_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    raise TypeError(f"unsupported TOML value {value!r}")


def toml_key(key: str) -> str:
    return key if re.fullmatch(r"[A-Za-z0-9_-]+", key) else json.dumps(key, ensure_ascii=False)


def toml_table(path: str, table: dict) -> str:
    lines = [f"[{path}]"]
    lines += [f"{toml_key(k)} = {toml_value(v)}" for k, v in table.items() if not isinstance(v, dict)]
    text = "\n".join(lines) + "\n"
    for key, value in table.items():
        if isinstance(value, dict):
            text += "\n" + toml_table(f"{path}.{toml_key(key)}", value)
    return text


def reconcile_codex_config(run: Run, manifest: dict) -> None:
    path = HOME / ".codex/config.toml"
    try:
        import tomllib
    except ImportError:
        warn(f"Python {sys.version.split()[0]} has no tomllib; skipped {path}")
        return
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    try:
        parsed = tomllib.loads(original)
    except tomllib.TOMLDecodeError as error:
        warn(f"{path} is not valid TOML ({error}); left untouched")
        return
    current = parsed.get("mcp_servers") or {}
    desired = desired_servers(current, manifest["codex"]["mcpServers"], "Codex")
    if desired == current:
        return
    rewrite = {name for name in current if desired.get(name) != current[name]}
    blocks: list[list[str]] = [[]]
    for line in original.splitlines(keepends=True):
        if TABLE_HEADER.match(line):
            blocks.append([])
        blocks[-1].append(line)
    kept = []
    for block in blocks:
        match = SERVER_HEADER.match(block[0]) if block else None
        name = match and next(group for group in match.groups() if group)
        if name not in rewrite:
            kept.append("".join(block))
    text = "".join(kept)
    for name, spec in desired.items():
        if name in rewrite or name not in current:
            try:
                rendered = toml_table(f"mcp_servers.{toml_key(name)}", spec)
            except TypeError as error:
                warn(f"cannot render Codex MCP server {name} ({error}); {path} left untouched")
                return
            text = text.rstrip("\n") + "\n\n" + rendered
    try:
        result = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        warn(f"edited {path} would not parse ({error}); left untouched")
        return
    others = {k: v for k, v in parsed.items() if k != "mcp_servers"}
    if (result.get("mcp_servers") or {}) != desired or {k: v for k, v in result.items() if k != "mcp_servers"} != others:
        warn(f"{path} declares MCP servers in a layout this reconciler does not edit; left untouched")
        return
    removed = sorted(set(current) - set(desired))
    added = sorted(set(desired) - set(current))
    run.write_text(path, text, f"MCP servers -{removed} +{added}")


def source_of(package) -> str:
    return package if isinstance(package, str) else str(package.get("source", ""))


def reconcile_pi_settings(run: Run, manifest: dict) -> None:
    path = HOME / ".pi/agent/settings.json"
    loaded = load_json(path, create=True)
    if loaded is None:
        return
    data, original = loaded
    declared = manifest["pi"]["packages"]
    current = data.get("packages") or []
    present = {source_of(p) for p in current}
    desired = [p for p in current if source_of(p) in declared] + [p for p in declared if p not in present]
    if desired == current:
        return
    data["packages"] = desired
    removed = sorted(present - set(declared))
    added = sorted(set(declared) - present)
    run.write_text(path, dump_json(data, original), f"packages -{removed} +{added}")


def skill_roots(manifest: dict) -> dict[str, tuple[Path, set[str]]]:
    skills = manifest["skills"]
    claude = {s for src in skills["sources"] if "claude-code" in src["agents"] for s in src["skills"]}
    shared = {s for src in skills["sources"] for s in src["skills"]}
    return {
        "claude": (HOME / ".claude/skills", claude | set(skills["keep"]["claude"])),
        ALL_AGENTS_ROOT: (HOME / ".agents/skills", shared | set(skills["keep"]["shared"])),
        "codex": (HOME / ".codex/skills", set(skills["keep"]["codex"])),
        "pi": (HOME / ".pi/agent/skills", set(manifest["pi"]["skills"])),
    }


def reconcile_skill_roots(run: Run, manifest: dict) -> None:
    roots = skill_roots(manifest)
    for root, allowed in roots.values():
        if not root.is_dir():
            continue
        for entry in sorted(root.iterdir()):
            if entry.name.startswith("."):
                continue
            if entry.name not in allowed:
                run.move_away(entry, "not declared")
            elif entry.is_symlink() and not entry.exists():
                run.move_away(entry, "broken link")
    # OpenCode links into the repository's skill tree; drop the ones left dangling.
    opencode = HOME / ".config/opencode/skills"
    if opencode.is_dir():
        for entry in sorted(opencode.iterdir()):
            if entry.is_symlink() and not entry.exists() and ".agents/skills/" in os.readlink(entry):
                run.move_away(entry, "dangling skill link")
    lock_path = HOME / ".agents/.skill-lock.json"
    loaded = load_json(lock_path)
    if loaded is None:
        return
    lock, original = loaded
    known = set().union(*(allowed for _, allowed in roots.values()))
    entries = lock.get("skills")
    if isinstance(entries, dict) and set(entries) - known:
        dropped = sorted(set(entries) - known)
        lock["skills"] = {k: v for k, v in entries.items() if k in known}
        run.write_text(lock_path, dump_json(lock, original), f"lock entries -{dropped}")


def install_skills(run: Run, manifest: dict, refresh: bool) -> None:
    roots = skill_roots(manifest)
    npx = shutil.which("npx") or ("npx" if run.dry_run else None)
    for source in manifest["skills"]["sources"]:
        targets = [roots[ALL_AGENTS_ROOT][0]]
        if "claude-code" in source["agents"]:
            targets.append(roots["claude"][0])
        missing = [s for s in source["skills"] for t in targets if not (t / s / "SKILL.md").is_file()]
        if not refresh and not missing:
            continue
        if npx is None:
            warn(f"npx not found; cannot install {source['source']}")
            continue
        argv = [npx, "-y", "skills", "add", source["source"], "--skill", *source["skills"],
                "-g", "-y", "--agent", *source["agents"], "--copy"]
        run.command(argv, "install skills" if missing else "refresh skills", INSTALL_TIMEOUT)


HOOK_FILES = [HOME / ".claude/settings.json", HOME / ".codex/hooks.json"]


def axi_hook_tools(justfile: Path | None, profile: str) -> list[str] | None:
    """Hook-enabled AXI tools from the justfile, or None when they cannot be read."""
    just = shutil.which("just")
    if justfile is None or not justfile.is_file() or just is None:
        warn("cannot read the AXI tool lists (no justfile or just); skipped AXI and hook reconciliation")
        return None
    names = ["axi-tools", "axi-tools-git"] + (["axi-tools-work"] if profile == "work" else [])
    tools: list[str] = []
    for name in names:
        try:
            value = subprocess.run([just, "--justfile", str(justfile), "--evaluate", name], cwd=HOME,
                                   timeout=60, check=True, capture_output=True, text=True).stdout
        except (OSError, subprocess.SubprocessError) as error:
            warn(f"just --evaluate {name} failed ({error}); skipped AXI and hook reconciliation")
            return None
        # Git-sourced specs are owner/repo; the binary is the repo name.
        tools += [spec.rsplit("/", 1)[-1] for spec in value.split()]
    return tools


def register_axi_hooks(run: Run, justfile: Path, tools: list[str]) -> None:
    just = shutil.which("just")
    if any(load_json(path, create=True) is None for path in HOOK_FILES):
        return
    for tool in tools:
        managed = HOME / ".local/bin" / tool
        if not (os.access(managed, os.X_OK) or shutil.which(tool)):
            note(f"{tool} is not installed; its hooks register on the next rebuild once installed")
            continue
        run.command([just, "--justfile", str(justfile), "_setup-axi-hooks", tool], "register AXI hooks")

def claude_json(claude: str, args: list[str]):
    try:
        output = subprocess.run([claude, *args, "--json"], cwd=HOME, timeout=120, check=True,
                                stdin=subprocess.DEVNULL, capture_output=True, text=True).stdout
        return json.loads(output)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        warn(f"claude {' '.join(args)} --json failed ({error}); skipped Claude plugins")
        return None


def reconcile_claude_plugins(run: Run, manifest: dict) -> None:
    claude = shutil.which("claude")
    if claude is None:
        note("claude not on PATH; skipped Claude plugins and marketplaces")
        return
    declared_plugins = manifest["claude"]["plugins"]
    declared_markets = manifest["claude"]["marketplaces"]
    plugins = claude_json(claude, ["plugin", "list"])
    markets = claude_json(claude, ["plugin", "marketplace", "list"])
    if plugins is None or markets is None:
        return
    for plugin in plugins:
        if plugin.get("scope") != "project" or plugin["id"] not in manifest["claude"].get("retiredProjectPlugins", []):
            continue
        project = Path(plugin.get("projectPath") or "")
        if not project.is_absolute() or not project.is_dir():
            continue
        paths = [project / ".claude" / name for name in ["settings.json", "settings.local.json"]]
        run.paths.extend(paths)
    if any(load_json(path, create=True) is None for path in [
        HOME / ".claude/settings.json", HOME / ".claude/plugins/installed_plugins.json",
        HOME / ".claude/plugins/known_marketplaces.json",
    ]):
        return
    for plugin in plugins:
        project = Path(plugin.get("projectPath") or "")
        if (plugin.get("scope") == "project"
                and plugin["id"] in manifest["claude"].get("retiredProjectPlugins", [])
                and project.is_absolute() and project.is_dir()
                and all(load_json(project / ".claude" / name, create=True) is not None
                        for name in ["settings.json", "settings.local.json"])):
            run.command([claude, "plugin", "uninstall", plugin["id"], "--scope", "project"],
                        "uninstall project plugin", cwd=project)
    user = {p["id"]: p for p in plugins if p.get("scope") == "user"}
    for plugin_id in user:
        if plugin_id not in declared_plugins:
            run.command([claude, "plugin", "uninstall", plugin_id, "--scope", "user"], "uninstall plugin")
    names = {m["name"] for m in markets}
    for name in sorted(names - set(declared_markets)):
        run.command([claude, "plugin", "marketplace", "remove", name], "remove marketplace")
    for name, repo in declared_markets.items():
        if name not in names:
            run.command([claude, "plugin", "marketplace", "add", "--scope", "user", repo], "add marketplace")
    for plugin_id in declared_plugins:
        if plugin_id not in user:
            run.command([claude, "plugin", "install", "--scope", "user", plugin_id], "install plugin")
        elif user[plugin_id].get("enabled") is False:
            run.command([claude, "plugin", "enable", plugin_id, "--scope", "user"], "enable plugin")


def reconcile_project_hooks(run: Run, manifest: dict) -> None:
    retired = manifest["claude"].get("retiredProjectHooks", [])
    for project in project_paths(manifest):
        path = project / ".claude/settings.local.json"
        loaded = load_json(path)
        if loaded is None:
            continue
        data, original = loaded
        hooks = data.get("hooks")
        if not isinstance(hooks, dict):
            continue
        desired = {}
        for event, groups in hooks.items():
            desired[event] = []
            for group in groups:
                kept = [h for h in group.get("hooks", [])
                        if not any(pattern in hook_text(h) for pattern in retired)]
                if kept == group.get("hooks", []):
                    desired[event].append(group)
                elif kept:
                    desired[event].append({**group, "hooks": kept})
        if desired != hooks:
            data["hooks"] = desired
            run.write_text(path, dump_json(data, original), "retired project hooks removed")


def install_integrations(run: Run) -> None:
    rtk = shutil.which("rtk")
    if rtk is None:
        warn("rtk is not installed; its Claude hook installs on the next rebuild once installed")
    elif load_json(HOME / ".claude/settings.json", create=True) is not None:
        if not run.dry_run:
            (HOME / ".claude").mkdir(parents=True, exist_ok=True)
        run.command([rtk, "init", "-g", "--hook-only", "--auto-patch"], "install rtk hook")
    herdr = shutil.which("herdr")
    if herdr is None:
        warn("herdr is not installed; its integrations install on the next rebuild once installed")
    else:
        for agent, directory, settings in [
            ("claude", ".claude", ".claude/settings.json"),
            ("codex", ".codex", ".codex/hooks.json"),
            ("pi", ".pi/agent/extensions", ".pi/agent/settings.json"),
        ]:
            if load_json(HOME / settings, create=True) is None:
                continue
            if agent == "codex" and (HOME / ".codex/config.toml").exists():
                import tomllib
                try:
                    tomllib.loads((HOME / ".codex/config.toml").read_text())
                except tomllib.TOMLDecodeError:
                    warn("invalid Codex config; skipped herdr Codex installer")
                    continue
            if not run.dry_run:
                (HOME / directory).mkdir(parents=True, exist_ok=True)
            run.command([herdr, "integration", "install", agent], f"install herdr {agent}")
    rex = shutil.which("rex")
    if rex is None:
        note("Rex app owns its skill and hook; no Rex CLI installer is available")
    else:
        result = subprocess.run([rex, "setup", "--help"], capture_output=True, text=True, timeout=30)
        if result.returncode == 0 and re.search(r"^\s+hooks\b", result.stdout, re.MULTILINE):
            if all(load_json(path, create=True) is not None for path in HOOK_FILES):
                run.command([rex, "setup", "hooks"], "install Rex hooks")
        else:
            note("Rex CLI exposes no supported hook installer; preserving app-owned integration")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--dry-run", action="store_true", help="report changes without making them")
    parser.add_argument("--refresh-skills", action="store_true",
                        help="only reinstall every declared skill source")
    parser.add_argument("--justfile", type=Path,
                        help="justfile with the AXI tool lists (default: next to the manifest)")
    parser.add_argument("--profile", default="personal", help="dotfiles profile (work adds axi-tools-work)")
    args = parser.parse_args()
    justfile = args.justfile or args.manifest.parent / "justfile"
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    run = Run(args.dry_run, stream=args.refresh_skills, manifest=manifest)
    if args.refresh_skills:
        install_skills(run, manifest, refresh=True)
        # An explicit refresh fails loudly; activation below only warns.
        run.finish()
        return 1 if warnings else 0
    else:
        tools = axi_hook_tools(justfile, args.profile)

        def hook_policy(agent: str, local: bool = False) -> dict:
            policy = manifest[agent]["hooks"]
            return {"ensure": [] if local else policy["ensure"], "keep": policy["keep"] + (tools or [])}

        def hooks(path: Path, policy: dict) -> None:
            if tools is not None:  # without the AXI lists, a kept AXI hook could look undeclared
                reconcile_hook_file(run, path, policy)

        # Plugin and AXI CLI calls rewrite the tools' files, so they go first.
        steps = [
            ("Claude plugins", lambda: reconcile_claude_plugins(run, manifest)),
            ("project hooks", lambda: reconcile_project_hooks(run, manifest)),
            ("AXI hooks", lambda: tools is not None and register_axi_hooks(run, justfile, tools)),
            ("Claude MCP servers", lambda: reconcile_claude_json(run, manifest)),
            ("Claude hooks", lambda: hooks(HOME / ".claude/settings.json", hook_policy("claude"))),
            # Local settings only ever lose undeclared hooks; the declared ones live in settings.json.
            ("Claude local hooks", lambda: hooks(HOME / ".claude/settings.local.json", hook_policy("claude", True))),
            ("Codex MCP servers", lambda: reconcile_codex_config(run, manifest)),
            ("Codex hooks", lambda: hooks(HOME / ".codex/hooks.json", hook_policy("codex"))),
            # Installers must see ensured hooks on the first run too, so their
            # final ordering and serialization are stable on subsequent runs.
            ("integrations", lambda: install_integrations(run)),
            ("Pi packages", lambda: reconcile_pi_settings(run, manifest)),
            ("skill roots", lambda: reconcile_skill_roots(run, manifest)),
            ("skill installs", lambda: install_skills(run, manifest, refresh=False)),
        ]
        for name, step in steps:
            try:
                step()
            except Exception as error:  # one broken tool must not block the others
                warn(f"{name} failed: {error!r}")
    run.finish()
    if warnings:
        print(f"agent-tooling: finished with {len(warnings)} warning(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
