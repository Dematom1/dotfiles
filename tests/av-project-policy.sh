#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

policy="$repo/scripts/av-firstmate-policy.sh"
fm_home="$tmp/firstmate"
canonical="$fm_home/projects/canonical"
isolated="$tmp/canonical-isolated"
unregistered="$tmp/unregistered"
lookalike="$tmp/canonical"
arbitrary="$tmp/arbitrary"
mkdir -p "$fm_home/data" "$fm_home/projects" "$fm_home/state" "$arbitrary"
cat > "$fm_home/data/projects.md" <<'EOF'
- canonical [no-mistakes] - registered project
- spoof [no-mistakes] - symlink candidate
EOF

init_repo() {
  local path=$1
  git init -q "$path"
  git -C "$path" config user.email test@example.invalid
  git -C "$path" config user.name test
  printf '%s\n' "$path" > "$path/README"
  git -C "$path" add README
  git -C "$path" commit -q -m initial
  git -C "$path" remote add origin https://github.com/example/canonical.git
}

init_repo "$canonical"
init_repo "$unregistered"
init_repo "$lookalike"
git -C "$canonical" worktree add -q -b fm-isolated "$isolated"
mkdir -p "$isolated/subdir"
ln -s "$unregistered" "$fm_home/projects/spoof"

vendor="$tmp/vendor-av"
args_log="$tmp/vendor-args"
cat > "$vendor" <<'EOF'
#!/usr/bin/env bash
printf '<%s>\n' "$@" > "$VENDOR_ARGS"
printf 'vendor-ok\n'
EOF
chmod +x "$vendor"

run_allowed() {
  local dir=$1 task=${2-}
  if [ -n "$task" ]; then
    (cd "$dir" && FM_HOME="$fm_home" AV_VENDOR_CLI="$vendor" FM_TASK_ID="$task" \
      "$policy" inject +SAFE_NAME -- approved-tool --flag value)
  else
    (cd "$dir" && FM_HOME="$fm_home" AV_VENDOR_CLI="$vendor" \
      "$policy" inject +SAFE_NAME -- approved-tool --flag value)
  fi
}

output=$(VENDOR_ARGS="$args_log" run_allowed "$canonical")
[[ "$output" == vendor-ok ]] || fail "registered canonical clone was denied"
[[ "$(<"$args_log")" == $'<inject>\n<+SAFE_NAME>\n<-->\n<approved-tool>\n<--flag>\n<value>' ]] \
  || fail "policy changed the av request instead of forwarding it"

cat > "$fm_home/state/task-1.meta" <<EOF
project=$canonical
worktree=$isolated
kind=ship
EOF
output=$(VENDOR_ARGS="$args_log" run_allowed "$isolated/subdir" task-1)
[[ "$output" == vendor-ok ]] || fail "verified isolated copy was denied"

expect_denied() {
  local dir=$1 label=$2 task=${3-}
  set +e
  if [ -n "$task" ]; then
    output=$(cd -L "$dir" && FM_HOME="$fm_home" AV_VENDOR_CLI="$vendor" FM_TASK_ID="$task" \
      "$policy" --version 2>&1)
  else
    output=$(cd -L "$dir" && FM_HOME="$fm_home" AV_VENDOR_CLI="$vendor" \
      "$policy" --version 2>&1)
  fi
  status=$?
  set -e
  [[ $status -eq 126 ]] || fail "$label returned $status instead of 126"
  [[ "$output" == av\ unavailable:* ]] || fail "$label did not fail closed: $output"
}

expect_denied "$arbitrary" "arbitrary directory"
expect_denied "$unregistered" "unregistered repository"
expect_denied "$lookalike" "remote-name-only lookalike"
expect_denied "$isolated" "isolated copy without task identity"
expect_denied "$fm_home/projects/spoof" "registered symlink spoof"

# The path below resolves to the canonical clone, but its logical spelling is a
# symlink. Create it after the direct checks so the canonical fixture stays real.
ln -s "$canonical" "$tmp/canonical-link"
expect_denied "$tmp/canonical-link" "working-directory symlink spoof"

printf '%s\n' "Automic Vault Firstmate project policy checks passed"
