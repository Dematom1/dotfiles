#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
just_bin=$(command -v just)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

dry_run=$(cd "$repo" && "$just_bin" --justfile "$repo/justfile" --dry-run update 2>&1)
[[ "$dry_run" != *[Mm]emtrace* ]] || fail "update still declares Memtrace work"
[[ "$dry_run" != *kun-agent-workspace* ]] || fail "update still uses the old Firstmate workspace"
[[ "$dry_run" == *'ws="$HOME/agent-workspace"'* ]] || fail "update lost the current Firstmate workspace"

setup_dry_run=$(cd "$repo" && "$just_bin" --justfile "$repo/justfile" --dry-run setup-firstmate 2>&1)
[[ "$setup_dry_run" != *kun-agent-workspace* ]] || fail "setup-firstmate still uses the old Firstmate workspace"
[[ "$setup_dry_run" == *'ws="$HOME/agent-workspace"'* ]] || fail "setup-firstmate lost the current Firstmate workspace"

native_bin="$tmp/native-bin"
mkdir -p "$native_bin"
cat > "$native_bin/herdr" <<'EOF'
#!/usr/bin/env bash
printf 'herdr %s\n' "$*" >> "$HERDR_LOG"
EOF
chmod +x "$native_bin/herdr"
HERDR_LOG="$tmp/native-herdr.log" PATH="$native_bin:/usr/bin:/bin" \
  "$just_bin" --justfile "$repo/justfile" _update-herdr
[[ "$(<"$tmp/native-herdr.log")" == "herdr update" ]] \
  || fail "native Herdr updater was not used without Homebrew"

sandbox="$tmp/sandbox"
bin="$sandbox/bin"
home="$sandbox/home"
stack_log="$sandbox/stack.log"
brew_log="$sandbox/brew.log"
skills_log="$sandbox/skills.log"
mkdir -p "$bin" "$home/agent-workspace/.git" "$sandbox/.agents/skills" "$sandbox/opencode/skills"
cp "$repo/justfile" "$sandbox/justfile"

cat > "$bin/stack" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$STACK_LOG"
if [[ "$name" == git && "$1" == clone ]]; then
  destination="${@: -1}"
  mkdir -p "$destination"
  printf '%s\n' 'name: learning-opportunities' 'description: test' > "$destination/SKILL.md"
fi
if [[ "$name" == git && "$1" == -C ]]; then
  exit 0
fi
if [[ "$name" == *-axi && "$*" == "setup --help" ]]; then
  printf 'usage: %s setup hooks\n' "$name"
fi
EOF
cat > "$bin/rsync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination="${@: -1}"
mkdir -p "$destination"
printf '%s\n' 'name: learning-opportunities' 'description: test' > "$destination/SKILL.md"
EOF
cat > "$bin/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "-y @uidotsh/install" ]]; then
  exit 0
fi
[[ "$1" == -y && "$2" == skills && "$3" == add ]] || exit 1
for arg in "$@"; do
  case "$arg" in
    \*|[Ee]ve|[Pp]rompt[Ss]cript)
      echo "warning: unsupported agent $arg" >&2
      ;;
  esac
done
printf '%s\n' "$*" >> "$SKILLS_LOG"
EOF
cat > "$bin/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$BREW_LOG"
case "$*" in
  "list --formula herdr") exit 0 ;;
  update) exit 0 ;;
  "upgrade herdr")
    status=${BREW_UPGRADE_STATUS:-0}
    if [[ $status -ne 0 ]]; then
      echo "Error: Homebrew failed to upgrade Herdr" >&2
    fi
    exit "$status"
    ;;
  *) exit 1 ;;
esac
EOF
cat > "$bin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Linux\n'
EOF
chmod +x "$bin/stack" "$bin/rsync" "$bin/npx" "$bin/brew" "$bin/uname"
for command in git pi claude herdr treehouse no-mistakes npm; do ln -s stack "$bin/$command"; done
for command in gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi pg-axi docker-axi npm-axi pypi-axi homebrew-axi linear-axi; do
  ln -s stack "$bin/$command"
done
ln -s "$just_bin" "$bin/just"

run_update() {
  local expected_status=$1
  local output status
  set +e
  output=$(cd "$sandbox" && \
    HOME="$home" STACK_LOG="$stack_log" BREW_LOG="$brew_log" SKILLS_LOG="$skills_log" \
    BREW_UPGRADE_STATUS="$expected_status" PATH="$bin:/usr/bin:/bin" just update 2>&1)
  status=$?
  set -e
  printf '%s\n' "$output"
  [[ $status -eq 0 ]] || return "$status"
}

set +e
failed_output=$(run_update 17)
failed_status=$?
set -e
[[ $failed_status -eq 17 ]] || fail "Homebrew Herdr failure returned $failed_status instead of 17"
[[ "$failed_output" != *"warning: unsupported agent"* ]] \
  || fail "unsupported-agent warnings were emitted during the update"
[[ "$failed_output" != *"Everything updated."* ]] \
  || fail "update reported success after Herdr failed"
[[ "$failed_output" != *"FirstMate stack updated."* ]] \
  || fail "FirstMate reported success after Herdr failed"
[[ "$failed_output" == *"error: recipe"* ]] || fail "fatal Herdr failure was not surfaced by just"
[[ "$failed_output" == *"brew"* ]] || fail "Homebrew Herdr failure was not visible"
[[ "$failed_output" == *"herdr"* ]] || fail "Herdr failure was not visible"
[[ "$(grep -Fc 'brew update' "$stack_log" 2>/dev/null || true)" -eq 0 ]] \
  || fail "Homebrew commands were logged by the wrong fixture"
[[ "$(grep -Fc 'treehouse update' "$stack_log" 2>/dev/null || true)" -eq 0 ]] \
  || fail "Treehouse ran after the fatal Herdr update"
[[ "$(grep -Fc 'no-mistakes update' "$stack_log" 2>/dev/null || true)" -eq 0 ]] \
  || fail "no-mistakes ran after the fatal Herdr update"

run_update 0 >/dev/null
run_update 0 >/dev/null
for command in 'list --formula herdr' 'update' 'upgrade herdr'; do
  [[ "$(grep -Fc "$command" "$brew_log")" -eq 3 ]] \
    || fail "Homebrew did not run '$command' for every Herdr update"
done
[[ "$(grep -Fc 'git -C '"$home"'/agent-workspace pull --ff-only' "$stack_log")" -ge 3 ]] \
  || fail "update did not use the current Firstmate workspace"
[[ "$(grep -Fc kun-agent-workspace "$stack_log" || true)" -eq 0 ]] \
  || fail "update used the old Firstmate workspace"
[[ "$(grep -Fc 'treehouse update' "$stack_log")" -eq 2 ]] \
  || fail "successful update did not continue to Treehouse"
[[ "$(grep -Fc 'no-mistakes update' "$stack_log")" -eq 2 ]] \
  || fail "successful update did not continue to no-mistakes"
[[ "$(grep -Fc 'FirstMate stack updated.' "$stack_log" || true)" -eq 0 ]] \
  || fail "test fixture unexpectedly logged recipe output"
[[ "$(grep -Fc 'warning: unsupported agent' "$skills_log" || true)" -eq 0 ]] \
  || fail "unsupported-agent warnings entered the skills invocation log"

printf '%s\n' "just update checks passed"
