#!/usr/bin/env bash
# Drive the built dibs shims against a fake real tool: tests/dibs-shims.sh SHIM_BIN_DIR.
# Run by the dibs-enforcement flake check. Uses a scratch HOME and dibs state, no Docker.
set -euo pipefail
shims=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$work/real" "$work/project"
for tool in docker kind k3d orb orbctl; do
  printf '#!/bin/sh\necho "real-%s $*"\nexit 7\n' "$tool" > "$work/real/$tool"
  chmod +x "$work/real/$tool"
done
# No dibs on this PATH: interception must use the dibs the shims were built with.
path="$shims:$work/real:$(dirname "$(command -v sh)"):$(dirname "$(command -v grep)")"
export HOME=$work DIBS_STATE=$work/state

# Without DIBS_TASK every call is the real tool's: same output and exit status.
for tool in docker kind k3d orb orbctl; do
  set +e
  out=$(cd "$work/project" && env -u DIBS_TASK PATH="$path" "$tool" run -d x 2>&1)
  status=$?
  set -e
  [[ $out == "real-$tool run -d x" && $status == 7 ]] || fail "$tool passthrough: status $status, output: $out"
done

# With DIBS_TASK, creates dibs cannot lease are refused by dibs itself.
expect_refusal() {
  local expected=$1; shift
  set +e
  out=$(cd "$work/project" && DIBS_TASK=probe PATH="$path" "$@" 2>&1)
  status=$?
  set -e
  [[ $status == 2 && $out == *"$expected"* && $out != *real-* ]] \
    || fail "$* under DIBS_TASK: status $status, output: $out"
}
expect_refusal "no adapter for a detached container" docker run -d nginx
expect_refusal "no OrbStack machine adapter" orb create ubuntu box
expect_refusal "no Compose file found" docker compose up -d

# Non-create calls still pass through under DIBS_TASK.
out=$(cd "$work/project" && DIBS_TASK=probe PATH="$path" docker ps 2>&1 || true)
[[ $out == "real-docker ps" ]] || fail "docker ps under DIBS_TASK: $out"

echo "dibs shim checks passed"
