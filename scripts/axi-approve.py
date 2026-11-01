#!/usr/bin/env python3
"""Human approval of the maintained AXI packages' staged npm releases."""

import argparse
import getpass
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from functools import cmp_to_key

PACKAGES = ("argo-workflows-axi", "argocd-axi", "datadog-axi")
REGISTRY = "https://registry.npmjs.org/"


def field(key, value):
    # JSON quoting keeps registry-controlled strings from injecting terminal controls.
    print(f"{key}: {json.dumps(value, ensure_ascii=True)}", flush=True)


def npm(*args, cwd=None):
    result = subprocess.run(
        [
            "npm",
            *args,
            "--registry",
            REGISTRY,
            "--logs-max=0",
            "--loglevel=silent",
            "--timing=false",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        cwd=cwd,
    )
    if result.returncode:
        raise ValueError(
            f"npm {' '.join(args[:2])} failed; check npm login and permissions"
        )
    return json.loads(result.stdout)


def inspect(item):
    stage_id = str(uuid.UUID(item["id"]))
    detail = npm("stage", "view", stage_id, "--json")
    for key in ("id", "packageName", "version"):
        if detail[key] != item[key]:
            raise ValueError("stage details do not match the listed release")
    field("package", detail["packageName"])
    field("version", detail["version"])
    field("stage", stage_id)
    field("status", detail.get("status", "unknown"))
    # Preserve all metadata, including provenance fields as the registry evolves.
    field("metadata", json.dumps(detail, ensure_ascii=True))
    provenance = detail.get("provenance")
    predicate = provenance.get("predicate") if isinstance(provenance, dict) else None
    predicate = predicate if isinstance(predicate, dict) else {}
    definition = predicate.get("buildDefinition")
    definition = definition if isinstance(definition, dict) else {}
    parameters = definition.get("externalParameters")
    parameters = parameters if isinstance(parameters, dict) else {}
    workflow = parameters.get("workflow")
    workflow = workflow if isinstance(workflow, dict) else {}
    dependencies = definition.get("resolvedDependencies")
    dependencies = dependencies if isinstance(dependencies, list) else []
    source_repository = workflow.get("repository")
    commit = next(
        (
            digest["gitCommit"]
            for dependency in dependencies
            if isinstance(dependency, dict)
            and isinstance(dependency.get("uri"), str)
            and (
                dependency["uri"][4:]
                if dependency["uri"].startswith("git+")
                else dependency["uri"]
            ).split("@", 1)[0]
            == source_repository
            for digest in [dependency.get("digest")]
            if isinstance(digest, dict)
            and isinstance(dependency["digest"].get("gitCommit"), str)
            and dependency["digest"]["gitCommit"]
        ),
        None,
    )
    run_details = predicate.get("runDetails")
    run_metadata = (
        run_details.get("metadata") if isinstance(run_details, dict) else None
    )
    run_metadata = run_metadata if isinstance(run_metadata, dict) else {}
    field("source_repo", workflow.get("repository", "not provided by npm stage view"))
    field("commit", commit or "not provided by npm stage view")
    field(
        "workflow_run",
        run_metadata.get("invocationId", "not provided by npm stage view"),
    )
    # npm stage view does not include a file list. Download for inspection only;
    # npm reports the tarball contents as JSON, without extracting or running it.
    with tempfile.TemporaryDirectory(prefix="axi-approve-") as directory:
        contents = npm("stage", "download", stage_id, "--json", cwd=directory)
    tarball = contents[detail["packageName"]]
    if (
        tarball["name"] != detail["packageName"]
        or tarball["version"] != detail["version"]
    ):
        raise ValueError("downloaded tarball does not match the staged release")
    if detail.get("shasum") and detail["shasum"] != tarball["shasum"]:
        raise ValueError("downloaded tarball shasum does not match the stage")
    files = tarball["files"]
    if not isinstance(files, list) or not files:
        raise ValueError("npm stage download returned no file list")
    print(f"files[{len(files)}]:", flush=True)
    for entry in files:
        print(f"  - {json.dumps(entry['path'], ensure_ascii=True)}", flush=True)
    return stage_id


def approve(stage_id, reference):
    # Never relay subprocess output: either tool could echo credentials on failure.
    result = subprocess.run(
        ["op", "read", reference],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    otp = result.stdout.strip()
    if result.returncode or not re.fullmatch(r"[0-9]{6,8}", otp):
        raise ValueError(
            "1Password OTP read failed; check the reference and desktop app integration"
        )
    approve_with_otp(stage_id, otp)


def approve_with_otp(stage_id, otp):
    result = subprocess.run(
        [
            "npm",
            "stage",
            "approve",
            stage_id,
            "--otp",
            otp,
            "--registry",
            REGISTRY,
            "--logs-max=0",
            "--loglevel=silent",
            "--timing=false",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    del otp
    if result.returncode:
        raise ValueError(
            "approval failed; check npm permissions or retry with a fresh OTP"
        )


def approve_with_web_auth(stage_id):
    result = subprocess.run(
        [
            "npm", "--auth-type=web", "stage", "approve", stage_id,
            "--registry", REGISTRY,
        ],
        stdin=None,
    )
    if result.returncode:
        raise ValueError("approval failed; check npm permissions or retry")


def compare_versions(left, right):
    def parts(version):
        match = re.fullmatch(
            r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
            r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
            r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?",
            version,
        )
        if not match:
            raise ValueError("staged version is not valid semver")
        major, minor, patch, prerelease = match.groups()
        identifiers = prerelease.split(".") if prerelease else None
        if identifiers and any(
            identifier.isdigit()
            and len(identifier) > 1
            and identifier.startswith("0")
            for identifier in identifiers
        ):
            raise ValueError("staged version is not valid semver")
        return (int(major), int(minor), int(patch)), identifiers

    a_core, a_pre = parts(left)
    b_core, b_pre = parts(right)
    if a_core != b_core:
        return (a_core > b_core) - (a_core < b_core)
    if a_pre is None or b_pre is None:
        return (a_pre is None) - (b_pre is None)
    for a_id, b_id in zip(a_pre, b_pre):
        if a_id == b_id:
            continue
        a_numeric, b_numeric = a_id.isdigit(), b_id.isdigit()
        if a_numeric != b_numeric:
            return -1 if a_numeric else 1
        a_value, b_value = (int(a_id), int(b_id)) if a_numeric else (a_id, b_id)
        return (a_value > b_value) - (a_value < b_value)
    return (len(a_pre) > len(b_pre)) - (len(a_pre) < len(b_pre))


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog=(
            "By default npm web authentication prints a URL for browser approval. "
            "Set AXI_APPROVE_OP_REF=op://VAULT/ITEM/one-time password for 1Password, "
            "or set AXI_APPROVE_AUTH=otp to enter an OTP when prompted. "
            "Run axi-approve in a terminal; each release requires confirmation. "
            "No automatic approval mode is supported."
        ),
    )
    parser.parse_args()
    result = subprocess.run(["npm", "--version"], capture_output=True, text=True)
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)\s*", result.stdout)
    if result.returncode or not match or tuple(map(int, match.groups())) < (11, 19, 0):
        raise ValueError(
            "npm >= 11.19 is required on PATH; rebuild dotfiles and reopen the terminal"
        )
    pending = []
    for package in PACKAGES:
        items = npm("stage", "list", package, "--json")
        if not isinstance(items, list):
            raise ValueError("unexpected npm stage list response (expected an array)")
        for item in items:
            if item["packageName"] != package:
                raise ValueError("npm stage list returned an unexpected package")
            pending.append(item)
    if not pending:
        field("result", "nothing pending")
        return 0
    reference = os.environ.get("AXI_APPROVE_OP_REF")
    typed_otp = os.environ.get("AXI_APPROVE_AUTH") == "otp"
    if not sys.stdin.isatty() or (reference is None and not sys.stdout.isatty()):
        raise ValueError(
            "run axi-approve in an interactive terminal to confirm each release"
        )
    if reference is not None and (
        not reference.startswith("op://") or len(reference.split("/")) < 5
    ):
        raise ValueError("AXI_APPROVE_OP_REF must be an op:// vault reference")
    pending.sort(key=cmp_to_key(lambda left, right: (left["packageName"] > right["packageName"]) - (left["packageName"] < right["packageName"]) or compare_versions(left["version"], right["version"])))
    failed = False
    approved = {}
    for item in pending:
        label = f"{item['packageName']}@{item['version']}"
        try:
            stage_id = inspect(item)
            answer = input("Approve this version? [y/N] ").strip().lower()
            if answer != "y":
                field("result", f"{label}: skipped")
                continue
            if reference is not None:
                approve(stage_id, reference)
            elif typed_otp:
                approve_with_otp(stage_id, getpass.getpass("npm one-time password: "))
            else:
                approve_with_web_auth(stage_id)
            approved[item["packageName"]] = item["version"]
            field("result", f"{label}: approved and published")
        except (ValueError, KeyError, TypeError, OSError) as error:
            # Do not print exception details, which could contain dependency secrets.
            failed = True
            field("result", f"{label}: failed")
            field(
                "error",
                str(error)
                if isinstance(error, ValueError)
                else "could not inspect or approve release",
            )
    for package, version in approved.items():
        tags = npm("dist-tag", "ls", package, "--json")
        if tags.get("latest") != version:
            failed = True
            field("error", f"{package} latest is {tags.get('latest')}; run npm dist-tag add {package}@{version} latest")
    return int(failed)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError) as error:
        field(
            "error",
            str(error)
            if isinstance(error, ValueError)
            else "could not run npm; check PATH and staged metadata",
        )
        sys.exit(1)
    except (EOFError, KeyboardInterrupt):
        field("result", "cancelled; no further approvals")
        sys.exit(1)
