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
test_home="$tmp/home"
fm_home="$test_home/agent-workspace"
managed="$fm_home/projects/dotfiles"
canonical="$test_home/Code/dotfiles"
infrastructure="$test_home/Code/infrastructure"
isolated="$tmp/canonical-isolated"
unregistered="$tmp/unregistered"
lookalike="$tmp/canonical"
arbitrary="$tmp/arbitrary"
forged="$tmp/forged"
mkdir -p "$fm_home/data" "$fm_home/projects" "$fm_home/state" "$test_home/Code" "$arbitrary"
cat > "$fm_home/data/projects.md" <<'EOF'
- dotfiles [no-mistakes] - registered project
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

init_repo "$managed"
init_repo "$canonical"
init_repo "$infrastructure"
mkdir -p "$infrastructure/subdir"
git -C "$infrastructure" remote set-url origin https://github.com/dematom-labs/infrastructure.git
init_repo "$unregistered"
init_repo "$lookalike"
init_repo "$forged"
git -C "$managed" worktree add -q -b fm-isolated "$isolated"
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

invoke_policy() {
  local dir=$1 task=$2
  shift 2
  (cd -L "$dir" && env "${home_env[@]}" "${git_env[@]}" AV_VENDOR_CLI="$vendor" FM_TASK_ID="$task" \
    VENDOR_ARGS="$args_log" "$policy" "$@")
}

run_allowed() {
  local output
  output=$(invoke_policy "$1" "${2-}" inject +SAFE_NAME -- approved-tool --flag value)
  [[ "$output" == vendor-ok ]] || fail "registered path was denied: $1"
  [[ "$(<"$args_log")" == $'<inject>\n<+SAFE_NAME>\n<-->\n<approved-tool>\n<--flag>\n<value>' ]] \
    || fail "policy changed the av request instead of forwarding it"
}

expect_denied() {
  local dir=$1 label=$2 task=${3-} output status
  rm -f "$args_log"
  if output=$(invoke_policy "$dir" "$task" --version 2>&1); then
    fail "$label was allowed"
  else
    status=$?
  fi
  [[ $status -eq 126 ]] || fail "$label returned $status instead of 126"
  [[ "$output" == av\ unavailable:* ]] || fail "$label did not fail closed: $output"
  [[ ! -e "$args_log" ]] || fail "$label reached the vendor CLI"
}

cat > "$fm_home/state/task-1.meta" <<EOF
project=$managed
worktree=$isolated
kind=ship
EOF
cat > "$fm_home/state/path-spoof.meta" <<EOF
project=$managed
worktree=$unregistered
kind=ship
EOF
ln -s "$canonical" "$tmp/canonical-link"
ln -s "$isolated" "$tmp/isolated-link"
cat > "$fm_home/state/symlink-spoof.meta" <<EOF
project=$managed
worktree=$tmp/isolated-link
kind=ship
EOF
git -C "$unregistered" worktree add -q -b spoof "$tmp/unrelated-copy"
cat > "$fm_home/state/common-spoof.meta" <<EOF
project=$managed
worktree=$tmp/unrelated-copy
kind=ship
EOF

for mode in explicit unset empty; do
  case "$mode" in
    explicit) home_env=("HOME=$test_home" "FM_HOME=$fm_home") ;;
    unset) home_env=(-u FM_HOME "HOME=$test_home") ;;
    empty) home_env=("HOME=$test_home" FM_HOME=) ;;
  esac
  run_allowed "$canonical"
  run_allowed "$infrastructure"
  git -C "$infrastructure" remote set-url origin git@github.com:dematom-labs/infrastructure.git
  run_allowed "$infrastructure"
  git -C "$infrastructure" remote set-url origin https://github.com/dematom-labs/infrastructure.git
  run_allowed "$managed"
  run_allowed "$tmp/canonical-link"
  run_allowed "$isolated/subdir" task-1
  run_allowed "$tmp/isolated-link/subdir" task-1

  run_allowed "$infrastructure/subdir"
  expect_denied "$infrastructure" "task-marked canonical infrastructure" task-1
  expect_denied "$arbitrary" "arbitrary directory"
  expect_denied "$unregistered" "unregistered repository"
  expect_denied "$lookalike" "remote-name-only lookalike"
  expect_denied "$isolated" "isolated copy without task identity"
  expect_denied "$fm_home/projects/spoof" "registered symlink spoof"
  expect_denied "$unregistered" "task path mismatch" task-1
  expect_denied "$unregistered" "unlinked task path spoof" path-spoof
  expect_denied "$isolated" "metadata symlink spoof" symlink-spoof
  expect_denied "$tmp/unrelated-copy" "Git common directory spoof" common-spoof
done

# Caller-controlled Git variables must not redirect root discovery or config.
for variable in GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM \
  GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_PARAMETERS \
  GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES \
  GIT_DISCOVERY_ACROSS_FILESYSTEM; do
  git_env=("$variable=$infrastructure/.git")
  case "$variable" in
    GIT_CONFIG|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM) git_env=("$variable=$tmp/forged.gitconfig") ;;
    GIT_CONFIG_COUNT) git_env=(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url GIT_CONFIG_VALUE_0=https://github.com/dematom-labs/infrastructure.git) ;;
    GIT_CONFIG_KEY_0|GIT_CONFIG_VALUE_0) git_env=(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url GIT_CONFIG_VALUE_0=https://github.com/dematom-labs/infrastructure.git "$variable=$forged") ;;
    GIT_CONFIG_PARAMETERS) git_env=("$variable='remote.origin.url=https://github.com/dematom-labs/infrastructure.git'") ;;
    GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|GIT_INDEX_FILE|GIT_OBJECT_DIRECTORY|GIT_CEILING_DIRECTORIES) git_env=("$variable=$forged") ;;
    GIT_DISCOVERY_ACROSS_FILESYSTEM) git_env=("$variable=1") ;;
  esac
  expect_denied "$arbitrary" "environment override $variable"
done

git -C "$infrastructure" remote set-url origin https://github.com/example/infrastructure.git
expect_denied "$infrastructure" "wrong infrastructure origin"
git -C "$infrastructure" remote set-url origin https://github.com/Dematom1/infrastructure.git
expect_denied "$infrastructure" "old infrastructure origin"
git -C "$infrastructure" remote set-url origin https://github.com/dematom-labs/infrastructure.git
git -C "$infrastructure" config --add remote.origin.url https://github.com/example/infrastructure.git
expect_denied "$infrastructure" "ambiguous infrastructure origin"
git -C "$infrastructure" config --unset-all remote.origin.url
git -C "$infrastructure" config --add remote.origin.url https://github.com/dematom-labs/infrastructure.git

mv "$infrastructure" "$tmp/infrastructure-real"
ln -s "$tmp/infrastructure-real" "$infrastructure"
expect_denied "$infrastructure" "symlinked canonical infrastructure"
rm "$infrastructure"

git -C "$tmp/infrastructure-real" worktree add -q -b infrastructure-linked "$infrastructure"
expect_denied "$infrastructure" "linked canonical infrastructure worktree"

printf '%s\n' "Automic Vault Firstmate project policy checks passed"
