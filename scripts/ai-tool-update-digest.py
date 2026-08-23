#!/usr/bin/env python3
"""Read-only AI tool release digest collector.

This program may query public metadata and write its own state/output only. It
never invokes an installer, updater, rebuild, restart, shell, or release-note
text as code.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen

VERSION_RE = re.compile(r"(?<!\d)v?(\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?)")
ARROW_RE = re.compile(
    r"v?(\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?)\s*(?:->|→)\s*"
    r"v?(\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?)"
)
SECURITY_RE = re.compile(
    r"\b(?:cve|vulnerabilit(?:y|ies)|security|credential|signing(?: key)?|"
    r"arbitrary code|sandbox escape|auth(?:entication|orization)? bypass|"
    r"protocol|breaking|migration)\b",
    re.IGNORECASE,
)

DEFAULT_STATE = (
    Path.home() / ".local" / "state" / "ai-tool-update-digest" / "state.json"
)
DEFAULT_OUTPUT = (
    Path.home() / ".local" / "state" / "ai-tool-update-digest" / "digest.md"
)


def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def timestamp(value: dt.datetime) -> str:
    return value.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path, default: object) -> object:
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def command_result(command: list[str], timeout: int = 30) -> tuple[str, str | None]:
    """Run one allowlisted read-only command without invoking a shell."""
    if not command:
        return "", "empty command"
    environment = os.environ.copy()
    if Path(command[0]).name == "brew":
        # Keep this guard in the command environment, not just launchd config.
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout,
            env=environment,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return "", f"{type(error).__name__}: {error}"
    output = "\n".join(part for part in (result.stdout, result.stderr) if part).strip()
    if result.returncode:
        first_line = output.splitlines()[0] if output else "no output"
        return output, f"exit {result.returncode}: {first_line[:240]}"
    return output, None


def fetch_bytes(url: str, max_bytes: int = 2_000_000) -> bytes:
    request = Request(
        url,
        headers={
            "Accept": "application/json, text/plain",
            "User-Agent": "ai-tool-update-digest/1",
        },
    )
    with urlopen(request, timeout=20) as response:
        return response.read(max_bytes + 1)[:max_bytes]


def fetch_json(url: str) -> dict | list:
    return json.loads(fetch_bytes(url).decode("utf-8"))


def fetch_text(url: str) -> str:
    return fetch_bytes(url, 1_000_000).decode("utf-8", errors="replace")


def fetch_error(error: Exception) -> str:
    if isinstance(error, HTTPError):
        return f"HTTP {error.code}"
    if isinstance(error, URLError):
        return f"network error: {error.reason}"
    return f"{type(error).__name__}: {error}"


def normalize_version(value: str | None) -> str | None:
    if not value:
        return None
    return value.strip().lstrip("v") or None


def extract_version(text: str, pattern: str | None = None) -> str | None:
    if pattern:
        try:
            match = re.search(pattern, text, re.IGNORECASE)
        except re.error:
            match = None
        if match:
            return normalize_version(match.group(1))
        return None
    matches = VERSION_RE.findall(text)
    return normalize_version(matches[-1]) if matches else None


def version_key(value: str) -> tuple[tuple[int, ...], str]:
    match = VERSION_RE.search(value)
    if not match:
        return (), value
    numeric = re.match(r"v?(\d+)(?:\.(\d+))?(?:\.(\d+))?", match.group(0))
    numbers = tuple(
        int(part) for part in (numeric.groups() if numeric else ()) if part is not None
    )
    return numbers, match.group(1)


def is_newer(current: str | None, candidate: str | None) -> bool:
    if not candidate:
        return False
    if not current:
        return True
    return version_key(candidate)[0] > version_key(current)[0]


def safe_url(url: str | None) -> str | None:
    if not url:
        return None
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        return None
    return url


def escape_markdown(value: str, limit: int = 420) -> str:
    """Escape untrusted release text before inserting it into Markdown."""
    value = " ".join(value.replace("\x00", "").split())
    value = value[:limit] + ("..." if len(value) > limit else "")
    return re.sub(r"([\\`*_{}\[\]()#+.!|<>~-])", r"\\\1", value)


def load_inventory(path: Path) -> list[dict]:
    document = read_json(path, {})
    tools = document.get("tools") if isinstance(document, dict) else None
    if not isinstance(tools, list):
        raise ValueError(f"inventory has no tools list: {path}")
    return [tool for tool in tools if isinstance(tool, dict) and tool.get("id")]


def collect_npm_global(errors: dict[str, str]) -> dict[str, str]:
    output, error = command_result(["npm", "list", "-g", "--depth=0", "--json"])
    if error:
        errors["npm global"] = error
        return {}
    try:
        dependencies = json.loads(output).get("dependencies", {})
    except (AttributeError, json.JSONDecodeError):
        errors["npm global"] = "invalid JSON from npm list"
        return {}
    return {
        name: str(details.get("version"))
        for name, details in dependencies.items()
        if isinstance(details, dict) and details.get("version")
    }


def collect_brew(errors: dict[str, str]) -> dict[str, dict]:
    # command_result adds HOMEBREW_NO_AUTO_UPDATE=1 to every brew invocation.
    output, error = command_result(["brew", "outdated", "--json=v2"])
    if error:
        errors["Homebrew"] = error
        return {}
    try:
        document = json.loads(output)
    except json.JSONDecodeError:
        errors["Homebrew"] = "invalid JSON from brew outdated"
        return {}
    result = {}
    for kind in ("formulae", "casks"):
        for entry in document.get(kind, []):
            if isinstance(entry, dict) and entry.get("name"):
                result[entry["name"]] = {
                    "kind": "formula" if kind == "formulae" else "cask",
                    "new": normalize_version(str(entry.get("current_version", ""))),
                    "installed": normalize_version(
                        str((entry.get("installed_versions") or [""])[0])
                    ),
                }
    return result


def github_url(repo: str, tag: str | None = None) -> str:
    if tag:
        return (
            f"https://api.github.com/repos/{repo}/releases/tags/{quote(tag, safe='')}"
        )
    return f"https://api.github.com/repos/{repo}/releases/latest"


def latest_github(
    repo: str, cache: dict[str, dict | None], errors: dict[str, str]
) -> dict | None:
    """Read latest-release metadata only; release bodies wait for detection."""
    if repo in cache:
        return cache[repo]
    try:
        response = fetch_json(github_url(repo))
    except (HTTPError, URLError, OSError, ValueError) as error:
        errors[f"GitHub {repo}"] = fetch_error(error)
        cache[repo] = None
        return None
    if not isinstance(response, dict) or not response.get("tag_name"):
        errors[f"GitHub {repo}"] = "latest release response has no tag_name"
        cache[repo] = None
        return None
    value = {
        "repo": repo,
        "tag_name": str(response["tag_name"]),
        "html_url": safe_url(response.get("html_url"))
        or f"https://github.com/{repo}/releases",
    }
    cache[repo] = value
    return value


def github_release_details(
    repo: str, tag: str, cache: dict[str, dict | None], errors: dict[str, str]
) -> dict | None:
    key = f"{repo}#release:{tag}"
    if key in cache:
        return cache[key]
    try:
        value = fetch_json(github_url(repo, tag))
    except (HTTPError, URLError, OSError, ValueError) as error:
        errors[f"GitHub release {repo}@{tag}"] = fetch_error(error)
        cache[key] = None
        return None
    if not isinstance(value, dict):
        errors[f"GitHub release {repo}@{tag}"] = "release response is not an object"
        cache[key] = None
        return None
    cache[key] = value
    return value


def github_release_for_version(
    repo: str,
    version: str,
    cache: dict[str, dict | None],
    errors: dict[str, str],
) -> dict | None:
    tags = tuple(dict.fromkeys((version, f"v{version}")))
    failures = []
    for tag in tags:
        key = f"{repo}#release:{tag}"
        if key in cache:
            if cache[key] is not None:
                return cache[key]
            continue
        try:
            value = fetch_json(github_url(repo, tag))
        except (HTTPError, URLError, OSError, ValueError) as error:
            failures.append(f"{tag}: {fetch_error(error)}")
            cache[key] = None
            continue
        if isinstance(value, dict):
            cache[key] = value
            return value
        failures.append(f"{tag}: release response is not an object")
        cache[key] = None
    errors[f"GitHub release {repo}@{version}"] = "; ".join(failures)
    return None


def latest_npm(
    package: str, cache: dict[str, dict | None], errors: dict[str, str]
) -> dict | None:
    if package in cache:
        return cache[package]
    url = f"https://registry.npmjs.org/{quote(package, safe='')}/latest"
    try:
        value = fetch_json(url)
    except (HTTPError, URLError, OSError, ValueError) as error:
        errors[f"npm {package}"] = fetch_error(error)
        cache[package] = None
        return None
    if not isinstance(value, dict) or not value.get("version"):
        errors[f"npm {package}"] = "registry response has no version"
        cache[package] = None
        return None
    cache[package] = value
    return value


def current_version(
    tool: dict, npm_global: dict[str, str]
) -> tuple[str | None, str | None]:
    package = tool.get("package_name")
    if (
        tool.get("release_adapter") == "npm"
        and tool.get("owner", "").startswith("npm global")
        and package in npm_global
    ):
        return normalize_version(npm_global[package]), None
    command = tool.get("version_command")
    if not isinstance(command, list) or not command:
        return None, None
    output, error = command_result([str(part) for part in command])
    if error:
        return None, error
    return extract_version(output, tool.get("version_pattern")) or normalize_version(
        tool.get("known_version")
    ), None


def candidate_source(tool: dict) -> str:
    adapter = tool.get("release_adapter", "unknown")
    identity = (
        tool.get("package_name")
        or tool.get("brew_name")
        or tool.get("github_repo")
        or adapter
    )
    return f"{adapter}:{identity}"


def changelog_link(tool: dict, release: dict | None = None) -> str | None:
    if (
        release
        and release.get("html_url")
        and urlparse(release["html_url"]).hostname == "github.com"
    ):
        return safe_url(release["html_url"])
    return safe_url(tool.get("changelog_url") or tool.get("release_source"))


def brew_link(tool: dict) -> str | None:
    name = tool.get("brew_name")
    if not name:
        return None
    kind = "cask" if tool.get("brew_kind") == "cask" else "formula"
    return f"https://formulae.brew.sh/{kind}/{quote(name, safe='-') }"


def enrich_notes(
    tool: dict,
    candidate: dict,
    github_cache: dict[str, dict | None],
    errors: dict[str, str],
) -> tuple[str, str | None, bool]:
    release = candidate.get("release")
    repo = (release or {}).get("repo") or tool.get("github_repo")
    if release and repo and release.get("tag_name"):
        details = github_release_details(
            repo, str(release["tag_name"]), github_cache, errors
        )
        if details is None:
            return "", changelog_link(tool, release), False
        release = details
    elif repo:
        release = github_release_for_version(
            repo, str(candidate["new"]), github_cache, errors
        )
    if release:
        return str(release.get("body") or ""), changelog_link(tool, release), True
    changelog = safe_url(tool.get("changelog_url"))
    if changelog and changelog.lower().endswith((".md", ".txt")):
        try:
            return fetch_text(changelog), changelog, True
        except (HTTPError, URLError, OSError) as error:
            errors[f"changelog {tool['id']}"] = fetch_error(error)
    return "", changelog_link(tool), False


def collect_candidates(
    tools: list[dict],
    npm_global: dict[str, str],
    brew: dict[str, dict],
    errors: dict[str, str],
) -> tuple[list[dict], dict[str, dict | None]]:
    npm_cache: dict[str, dict | None] = {}
    github_cache: dict[str, dict | None] = {}
    native_latest: dict[str, str] = {}

    for tool in tools:
        check = tool.get("native_check")
        if not isinstance(check, list) or not check:
            continue
        output, error = command_result([str(part) for part in check])
        if error:
            errors[f"native check {tool['id']}"] = error
            continue
        match = ARROW_RE.search(output)
        if match:
            native_latest[tool["id"]] = normalize_version(match.group(2)) or ""
        else:
            versions = VERSION_RE.findall(output)
            if len(versions) >= 2:
                native_latest[tool["id"]] = normalize_version(versions[-1]) or ""
            else:
                errors[f"native check {tool['id']}"] = (
                    "no current -> latest version found"
                )

    candidates = []
    for tool in tools:
        adapter = tool.get("release_adapter", "unknown")
        current, current_error = current_version(tool, npm_global)
        if current_error and tool.get("id") not in {"model-catalogs"}:
            errors[f"version {tool['id']}"] = current_error
        latest = None
        release = None
        if adapter == "npm" and tool.get("package_name"):
            metadata = latest_npm(tool["package_name"], npm_cache, errors)
            if metadata:
                latest = normalize_version(str(metadata.get("version")))
        elif adapter == "homebrew" and tool.get("brew_name"):
            metadata = brew.get(tool["brew_name"])
            if metadata:
                latest = metadata.get("new")
                current = current or metadata.get("installed")
        elif adapter == "github" and tool.get("github_repo"):
            release = latest_github(tool["github_repo"], github_cache, errors)
            if release:
                latest = normalize_version(str(release.get("tag_name")))
        elif adapter == "native_axi":
            latest = native_latest.get(tool["id"])
        if latest and (current or not tool.get("pinned")) and is_newer(current, latest):
            candidates.append(
                {
                    "tool": tool,
                    "current": current or "unknown",
                    "new": latest,
                    "source": candidate_source(tool),
                    "release": release,
                }
            )
    return candidates, github_cache


def classify(tool: dict, notes: str) -> str:
    if tool.get("release_adapter") == "unknown":
        return "Unknown source"
    if SECURITY_RE.search(notes) or tool.get("risk") in {"R3", "R4"}:
        return "Action required"
    if tool.get("risk") == "R0":
        return "Informational"
    return "Review"


def state_key(candidate: dict) -> str:
    return f"{candidate['tool']['id']}|{candidate['source']}|{candidate['new']}"


def make_unknown_rows(
    tools: list[dict], errors: dict[str, str], npm_global: dict[str, str]
) -> list[dict]:
    rows = []
    for tool in tools:
        if tool.get("release_adapter") == "unknown":
            current, _ = current_version(tool, npm_global)
            rows.append(
                {
                    "tool": tool,
                    "current": current or "unknown",
                    "new": "unknown",
                    "reason": "No allowlisted machine-readable release source is configured.",
                    "link": safe_url(tool.get("release_source")),
                }
            )
    unknown_ids = {
        tool.get("id") for tool in tools if tool.get("release_adapter") == "unknown"
    }
    for source, error in errors.items():
        if (
            source.startswith("version ")
            and source.removeprefix("version ") in unknown_ids
        ):
            continue
        rows.append(
            {
                "tool": {
                    "name": source,
                    "risk": "R1",
                    "rollback_note": "Retry the read-only source check later.",
                },
                "current": "unknown",
                "new": "unknown",
                "reason": error,
                "link": None,
            }
        )
    return rows


def entry_markdown(candidate: dict) -> str:
    tool = candidate["tool"]
    link = safe_url(candidate.get("link"))
    notes = (
        candidate.get("notes")
        or "No release-note excerpt was available from the allowlisted source."
    )
    source = f"[release notes](<{link}>)" if link else "release source unavailable"
    return "\n".join(
        [
            f"### {escape_markdown(str(tool.get('name', tool.get('id', 'tool'))), 160)}",
            f"- Version: `{candidate['current']}` -> `{candidate['new']}`",
            f"- Source: {source}",
            f"- Risk: `{escape_markdown(str(tool.get('risk', 'unknown')), 40)}` - {escape_markdown(str(tool.get('risk_reason', '')))}",
            f"- Rollback: {escape_markdown(str(tool.get('rollback_note', 'Not documented.')))}",
            f"- Release notes: {escape_markdown(notes)}",
        ]
    )


def unknown_markdown(row: dict) -> str:
    tool = row["tool"]
    link = safe_url(row.get("link"))
    source = f"[source](<{link}>)" if link else "source unavailable"
    return "\n".join(
        [
            f"### {escape_markdown(str(tool.get('name', 'source')), 160)}",
            f"- Version: `{row['current']}` -> `{row['new']}`",
            f"- Source: {source}",
            f"- Reason: {escape_markdown(str(row.get('reason', 'Unknown source.')))}",
            f"- Rollback: {escape_markdown(str(tool.get('rollback_note', 'Not documented.')))}",
        ]
    )


def render_digest(
    selected: list[dict],
    unknown: list[dict],
    due: bool,
    generated: dt.datetime,
) -> str:
    groups = {name: [] for name in ("Action required", "Review", "Informational")}
    for candidate in selected:
        groups[classify(candidate["tool"], candidate.get("notes", ""))].append(
            candidate
        )
    alerts = [
        candidate
        for candidate in selected
        if classify(candidate["tool"], candidate.get("notes", "")) == "Action required"
        and SECURITY_RE.search(candidate.get("notes", ""))
    ]
    lines = [
        "# AI tool update digest",
        "",
        f"Generated: `{timestamp(generated)}`",
        "",
    ]
    for alert in alerts:
        lines.append(
            f"**ALERT:** {escape_markdown(alert['tool'].get('name', 'tool'))} has a security-sensitive or compatibility-sensitive release. Review before any manual change."
        )
    if alerts:
        lines.append("")
    if not due and not selected:
        lines.extend(
            [
                "No grouped digest is due today. Pending items will be included on the next Monday run.",
                "",
            ]
        )
    for heading in ("Action required", "Review", "Informational"):
        lines.extend([f"## {heading}", ""])
        if groups[heading]:
            for candidate in groups[heading]:
                lines.extend([entry_markdown(candidate), ""])
        else:
            lines.extend(["None.", ""])
    lines.extend(["## Unknown source", ""])
    if unknown:
        for row in unknown:
            lines.extend([unknown_markdown(row), ""])
    else:
        lines.extend(["None.", ""])
    return "\n".join(lines).rstrip() + "\n"


def self_test() -> None:
    assert extract_version("tool v1.2.3") == "1.2.3"
    assert is_newer("1.2.3", "1.2.4")
    assert not is_newer("1.2.4", "1.2.3")
    escaped = escape_markdown("bad `text`\n- execute: $HOME")
    assert "\\`" in escaped and "\\-" in escaped
    assert "execute" in escaped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[1]
    parser.add_argument(
        "--inventory", type=Path, default=root / "ai-tool-update-inventory.json"
    )
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--force",
        action="store_true",
        help="render pending items now instead of waiting for Monday",
    )
    parser.add_argument(
        "--self-test", action="store_true", help="run built-in assertions and exit"
    )
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print("self-test: ok")
        return 0

    generated = now_utc()
    tools = load_inventory(args.inventory)
    errors: dict[str, str] = {}
    npm_global = collect_npm_global(errors)
    brew = collect_brew(errors)
    candidates, github_cache = collect_candidates(tools, npm_global, brew, errors)
    state = read_json(args.state, {"schema": 1, "releases": {}})
    if not isinstance(state, dict):
        state = {"schema": 1, "releases": {}}
    releases = state.setdefault("releases", {})
    if not isinstance(releases, dict):
        releases = {}
        state["releases"] = releases

    selected = []
    for candidate in candidates:
        key = state_key(candidate)
        record = releases.get(key)
        is_first_seen = not isinstance(record, dict)
        if is_first_seen or not record.get("notes_fetched"):
            notes, link, notes_fetched = enrich_notes(
                candidate["tool"], candidate, github_cache, errors
            )
            if is_first_seen:
                record = {
                    "tool": candidate["tool"]["id"],
                    "source": candidate["source"],
                    "version": candidate["new"],
                    "first_seen": timestamp(generated),
                    "notified_at": None,
                }
            record.update(
                {
                    "last_seen": timestamp(generated),
                    "notes": notes,
                    "notes_fetched": notes_fetched,
                    "link": link
                    or brew_link(candidate["tool"])
                    or safe_url(candidate["tool"].get("release_source")),
                }
            )
            releases[key] = record
        else:
            record["last_seen"] = timestamp(generated)
        candidate["notes"] = str(record.get("notes") or "")
        candidate["link"] = (
            record.get("link")
            or brew_link(candidate["tool"])
            or safe_url(candidate["tool"].get("release_source"))
        )
        candidate["urgent"] = bool(SECURITY_RE.search(candidate["notes"]))
        if record.get("notes_fetched") and record.get("notified_at") is None and (
            args.force or generated.weekday() == 0 or candidate["urgent"]
        ):
            selected.append(candidate)

    due = (
        args.force
        or generated.weekday() == 0
        or any(candidate.get("urgent") for candidate in selected)
    )
    unknown = (
        make_unknown_rows(tools, errors, npm_global)
        if (args.force or generated.weekday() == 0)
        else []
    )
    digest = render_digest(selected, unknown, due, generated)
    write_text(args.output, digest)
    for candidate in selected:
        releases[state_key(candidate)]["notified_at"] = timestamp(generated)
    state["schema"] = 1
    state["last_run"] = timestamp(generated)
    state["last_output"] = str(args.output)
    write_json(args.state, state)
    print(args.output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"ai-tool-update-digest: {error}", file=sys.stderr)
        raise SystemExit(1)
