#!/usr/bin/env bash
# Drive a built generation's `av` launcher on synthetic repos.
# usage: av-launcher.sh GENERATION OUT_DIR
# The signed vendor CLI is never run: allow cases execute the generation's policy
# script with a recording stub, refuse cases go through the installed wrapper.
set -euo pipefail

generation=${1:?usage: av-launcher.sh GENERATION OUT_DIR}
out=${2:?usage: av-launcher.sh GENERATION OUT_DIR}
repo=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
wrapper="$generation/home-path/bin/av"
mkdir -p "$out"
failed=0
pass() { echo "av $1: PASS"; }
fail() { echo "av $1: FAIL - $2"; failed=1; }

# 1. The wrapper on PATH drops caller overrides and execs the store policy.
[[ -x "$wrapper" ]] || { fail wrapper "no $wrapper"; exit 1; }
cp "$wrapper" "$out/av-wrapper.sh"
policy=$(awk '$1 == "exec" { print $3 }' "$wrapper")
if [[ "$(sed -n 2p "$wrapper")" == "unset AV_VENDOR_CLI" && "$policy" == /nix/store/*-av-firstmate-policy.sh ]] \
  && cmp -s "$policy" "$repo/scripts/av-firstmate-policy.sh"; then
  pass "wrapper (unsets AV_VENDOR_CLI, execs $policy, matches the repo copy)"
else
  fail wrapper "unexpected wrapper or stale policy copy, see $out/av-wrapper.sh"
fi

# 2. The repo's synthetic-repo suite (allow + refuse + Git env overrides)
#    against the built policy rather than the working-tree copy.
if AV_POLICY="$policy" "$repo/tests/av-project-policy.sh" > "$out/policy-suite.log" 2>&1; then
  pass "policy suite on built script ($(tail -1 "$out/policy-suite.log"))"
else
  fail "policy suite" "see $out/policy-suite.log"
fi

# 3. Refusals through the installed wrapper itself, from a synthetic HOME.
tmp=$(mktemp -d)
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"
fm="$home/agent-workspace"
mkdir -p "$fm/data" "$fm/projects" "$fm/state" "$home/Code" "$tmp/arbitrary"
printf -- '- dotfiles [no-mistakes] - registered project\n' > "$fm/data/projects.md"
new_repo() {
  git init -q "$1"
  git -C "$1" -c user.email=v@example.invalid -c user.name=v commit -q --allow-empty -m init
  git -C "$1" remote add origin "$2"
}
new_repo "$fm/projects/dotfiles" https://github.com/example/dotfiles.git
new_repo "$tmp/unregistered" https://github.com/example/unregistered.git
new_repo "$home/Code/infrastructure" https://github.com/example/infrastructure.git
git -C "$fm/projects/dotfiles" worktree add -q -b verify "$tmp/isolated"
forged="remote.origin.url=https://github.com/dematom-labs/infrastructure.git"

refuse() {
  local label=$1 dir=$2 status output
  shift 2
  if output=$(cd "$dir" && env -i PATH=/usr/bin:/bin HOME="$home" "$@" "$wrapper" --version 2>&1); then
    status=0
  else
    status=$?
  fi
  printf '%s: exit %s: %s\n' "$label" "$status" "$output" >> "$out/wrapper-refusals.log"
  if [[ $status -eq 126 && "$output" == "av unavailable: "* ]]; then
    pass "refuses $label ($output)"
  else
    fail "refuses $label" "exit $status: $output"
  fi
}
refuse "arbitrary directory" "$tmp/arbitrary"
refuse "unregistered repo" "$tmp/unregistered"
refuse "isolated copy without task" "$tmp/isolated"
refuse "forged task id" "$tmp/isolated" FM_TASK_ID=missing-task
refuse "GIT_CONFIG_PARAMETERS forged infrastructure origin" "$home/Code/infrastructure" \
  "GIT_CONFIG_PARAMETERS='$forged'"
refuse "GIT_DIR pointed at another repo" "$tmp/arbitrary" GIT_DIR="$fm/projects/dotfiles/.git"

exit "$failed"
