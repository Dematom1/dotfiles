#!/usr/bin/env python3
"""Human approval of the maintained AXI packages' staged npm releases."""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid

PACKAGES = ("argo-workflows-axi", "argocd-axi", "datadog-axi")
REGISTRY = "https://registry.npmjs.org/"


def field(key, value):
    # JSON quoting keeps registry-controlled strings from injecting terminal controls.
    print(f"{key}: {json.dumps(value, ensure_ascii=True)}", flush=True)


def npm(*args, cwd=None):
    result = subprocess.run(
        ["npm", *args, "--registry", REGISTRY, "--logs-max=0", "--loglevel=silent", "--timing=false"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, cwd=cwd,
    )
    if result.returncode:
        raise ValueError(f"npm {' '.join(args[:2])} failed; check npm login and permissions")
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
    commit = next((digest["gitCommit"] for dependency in dependencies
                   if isinstance(dependency, dict)
                   and isinstance(dependency.get("uri"), str)
                   and (dependency["uri"][4:] if dependency["uri"].startswith("git+") else dependency["uri"]).split("@", 1)[0] == source_repository
                   for digest in [dependency.get("digest")]
                   if isinstance(digest, dict)
                   and isinstance(dependency["digest"].get("gitCommit"), str)
                   and dependency["digest"]["gitCommit"]), None)
    run_details = predicate.get("runDetails")
    run_metadata = run_details.get("metadata") if isinstance(run_details, dict) else None
    run_metadata = run_metadata if isinstance(run_metadata, dict) else {}
    field("source_repo", workflow.get("repository", "not provided by npm stage view"))
    field("commit", commit or "not provided by npm stage view")
    field("workflow_run", run_metadata.get("invocationId", "not provided by npm stage view"))
    # npm stage view does not include a file list. Download for inspection only;
    # npm reports the tarball contents as JSON, without extracting or running it.
    with tempfile.TemporaryDirectory(prefix="axi-approve-") as directory:
        contents = npm("stage", "download", stage_id, "--json", cwd=directory)
    tarball = contents[detail["packageName"]]
    if tarball["name"] != detail["packageName"] or tarball["version"] != detail["version"]:
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
        ["op", "read", reference], stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    otp = result.stdout.strip()
    if result.returncode or not re.fullmatch(r"[0-9]{6,8}", otp):
        raise ValueError("1Password OTP read failed; check the reference and desktop app integration")
    result = subprocess.run(
        ["npm", "stage", "approve", stage_id, "--otp", otp,
         "--registry", REGISTRY, "--logs-max=0", "--loglevel=silent", "--timing=false"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    del otp
    if result.returncode:
        raise ValueError("approval failed; check npm permissions or retry with a fresh OTP")


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog=(
        "Set AXI_APPROVE_OP_REF=op://VAULT/ITEM/one-time password. "
        "Run axi-approve in a terminal; each release requires confirmation. "
        "No automatic approval mode is supported."))
    parser.parse_args()
    result = subprocess.run(["npm", "--version"], capture_output=True, text=True)
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)\s*", result.stdout)
    if result.returncode or not match or tuple(map(int, match.groups())) < (11, 19, 0):
        raise ValueError("npm >= 11.19 is required on PATH; rebuild dotfiles and reopen the terminal")
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
    reference = os.environ.get("AXI_APPROVE_OP_REF", "")
    if not reference.startswith("op://") or len(reference.split("/")) < 5:
        raise ValueError("set AXI_APPROVE_OP_REF='op://VAULT/ITEM/one-time password' explicitly; no vault search is performed")
    if not sys.stdin.isatty():
        raise ValueError("run axi-approve in an interactive terminal to confirm each release")
    failed = False
    for item in pending:
        label = f"{item['packageName']}@{item['version']}"
        try:
            stage_id = inspect(item)
            answer = input("Approve this version? [y/N] ").strip().lower()
            if answer not in ("y", "yes"):
                field("result", f"{label}: skipped")
                continue
            approve(stage_id, reference)
            field("result", f"{label}: approved and published")
        except (ValueError, KeyError, TypeError, OSError) as error:
            # Do not print exception details, which could contain dependency secrets.
            failed = True
            field("result", f"{label}: failed")
            field("error", str(error) if isinstance(error, ValueError) else "could not inspect or approve release")
    return int(failed)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError) as error:
        field("error", str(error) if isinstance(error, ValueError) else "could not run npm; check PATH and staged metadata")
        sys.exit(1)
    except (EOFError, KeyboardInterrupt):
        field("result", "cancelled; no further approvals")
        sys.exit(1)
