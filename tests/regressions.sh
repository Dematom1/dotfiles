#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cat > "$tmp/failing-axi" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "setup --help" ]]; then
  echo "usage: failing-axi setup hooks"
  exit 0
fi
echo "simulated hook failure" >&2
exit 23
EOF

cat > "$tmp/unsupported-axi" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "setup --help" ]]; then
  echo "error: unrecognized command 'setup'"
  exit 2
fi
touch "$tmp/unsupported-ran"
exit 24
EOF

cat > "$tmp/broken-probe-axi" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "setup --help" ]]; then
  echo "simulated capability probe failure" >&2
  exit 42
fi
exit 24
EOF

cat > "$tmp/misleading-probe-axi" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "setup --help" ]]; then
  echo "setup failed while loading config: unsupported command syntax" >&2
  exit 41
fi
exit 24
EOF

cat > "$tmp/incidental-probe-axi" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "setup --help" ]]; then
  echo "setup: unsupported command syntax" >&2
  exit 40
fi
exit 24
EOF

cat > "$tmp/mixed-auth-probe-axi" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "setup --help" ]]; then
  echo "authentication failed while loading configuration" >&2
  echo "unknown command: setup" >&2
  exit 39
fi
exit 24
EOF

cat > "$tmp/mixed-runtime-probe-axi" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "setup --help" ]]; then
  echo "unknown command: setup" >&2
  echo "runtime failure while initializing plugins" >&2
  exit 38
fi
exit 24
EOF

cat > "$tmp/ambiguous-probe-axi" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "setup --help" ]]; then
  echo "usage: ambiguous-probe-axi"
  exit 0
fi
exit 24
EOF

cat > "$tmp/empty-probe-axi" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "setup --help" ]]; then
  exit 0
fi
exit 24
EOF

cat > "$tmp/explicitly-unsupported-axi" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "setup --help" ]]; then
  echo "error: unsupported command 'setup hooks'"
  exit 0
fi
touch "$tmp/explicitly-unsupported-ran"
exit 24
EOF

cat > "$tmp/unknown-command-axi" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "setup --help" ]]; then
  echo "unknown command: setup"
  exit 2
fi
touch "$tmp/unknown-command-ran"
exit 24
EOF

cat > "$tmp/reverse-unsupported-axi" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "setup --help" ]]; then
  echo "'setup hooks' is an unknown subcommand."
  exit 2
fi
touch "$tmp/reverse-unsupported-ran"
exit 24
EOF

cat > "$tmp/quota-axi" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "setup --help" ]]; then
  cat <<'HELP'
usage: quota-axi [auth] [flags]
commands[2]:
  (none)=quota, auth
flags[2]:
  --help, -v/--version
HELP
  exit 0
fi
touch "$tmp/quota-ran"
exit 24
EOF
chmod +x "$tmp/failing-axi" "$tmp/unsupported-axi" "$tmp/broken-probe-axi" \
  "$tmp/misleading-probe-axi" "$tmp/incidental-probe-axi" \
  "$tmp/mixed-auth-probe-axi" "$tmp/mixed-runtime-probe-axi" \
  "$tmp/ambiguous-probe-axi" "$tmp/empty-probe-axi" \
  "$tmp/explicitly-unsupported-axi" "$tmp/unknown-command-axi" \
  "$tmp/reverse-unsupported-axi" "$tmp/quota-axi"

set +e
output=$(cd "$repo" && just _setup-axi-hooks "$tmp/failing-axi" 2>&1)
status=$?
set -e
[[ $status -eq 23 ]] || fail "hook failure returned $status instead of 23"
[[ $output == *"simulated hook failure"* ]] || fail "hook error output was hidden"
[[ $output == *"setup hooks failed"* ]] || fail "hook failure was not reported"

output=$(cd "$repo" && just _setup-axi-hooks "$tmp/unsupported-axi" 2>&1)
[[ $output == *"no setup hooks"* ]] || fail "unsupported hooks were not identified"
[[ ! -e "$tmp/unsupported-ran" ]] || fail "unsupported setup hooks were executed"

set +e
output=$(cd "$repo" && just _setup-axi-hooks "$tmp/broken-probe-axi" 2>&1)
status=$?
set -e
[[ $status -eq 42 ]] || fail "capability probe failure returned $status instead of 42"
[[ $output == *"simulated capability probe failure"* ]] || fail "capability probe error output was hidden"
[[ $output == *"capability probe failed"* ]] || fail "capability probe failure was not reported"
[[ $output != *"no setup hooks"* ]] || fail "capability probe failure was reported as unsupported hooks"

set +e
output=$(cd "$repo" && just _setup-axi-hooks "$tmp/misleading-probe-axi" 2>&1)
status=$?
set -e
[[ $status -eq 41 ]] || fail "misleading probe failure returned $status instead of 41"
[[ $output == *"setup failed while loading config"* ]] || fail "misleading probe error output was hidden"
[[ $output == *"capability probe failed"* ]] || fail "misleading probe failure was not reported"
[[ $output != *"no setup hooks"* ]] || fail "unrelated unsupported-command text suppressed a probe failure"

set +e
output=$(cd "$repo" && just _setup-axi-hooks "$tmp/incidental-probe-axi" 2>&1)
status=$?
set -e
[[ $status -eq 40 ]] || fail "incidental probe failure returned $status instead of 40"
[[ $output == *"setup: unsupported command syntax"* ]] || fail "incidental probe error output was hidden"
[[ $output == *"capability probe failed"* ]] || fail "incidental probe failure was not reported"
[[ $output != *"no setup hooks"* ]] || fail "incidental unsupported-command phrase suppressed a probe failure"

for case in "mixed-auth-probe-axi:39:authentication failed" "mixed-runtime-probe-axi:38:runtime failure"; do
  IFS=: read -r tool expected_status expected_error <<<"$case"
  set +e
  output=$(cd "$repo" && just _setup-axi-hooks "$tmp/$tool" 2>&1)
  status=$?
  set -e
  [[ $status -eq $expected_status ]] || fail "$tool returned $status instead of $expected_status"
  [[ $output == *"$expected_error"* ]] || fail "$tool error output was hidden"
  [[ $output == *"unknown command: setup"* ]] || fail "$tool unsupported-command output was hidden"
  [[ $output == *"capability probe failed"* ]] || fail "$tool failure was not reported"
  [[ $output != *"no setup hooks"* ]] || fail "$tool mixed output suppressed a probe failure"
done

for tool in ambiguous-probe-axi empty-probe-axi; do
  set +e
  output=$(cd "$repo" && just _setup-axi-hooks "$tmp/$tool" 2>&1)
  status=$?
  set -e
  [[ $status -eq 1 ]] || fail "$tool returned $status instead of 1"
  [[ $output == *"unrecognized output"* ]] || fail "$tool output was not rejected"
  [[ $output != *"no setup hooks"* ]] || fail "$tool was reported as unsupported hooks"
done

for tool in explicitly-unsupported-axi unknown-command-axi reverse-unsupported-axi; do
  output=$(cd "$repo" && just _setup-axi-hooks "$tmp/$tool" 2>&1)
  [[ $output == *"no setup hooks"* ]] || fail "$tool explicit unsupported output was not identified"
  [[ ! -e "$tmp/${tool%-axi}-ran" ]] || fail "$tool unsupported setup hooks were executed"
done

output=$(cd "$repo" && just _setup-axi-hooks "$tmp/quota-axi" 2>&1)
[[ $output == *"no setup hooks"* ]] || fail "quota-axi top-level help was not identified"
[[ ! -e "$tmp/quota-ran" ]] || fail "quota-axi setup hooks were executed"

for recipe in update-skills update-ui-skill; do
  output=$(cd "$repo" && just --dry-run "$recipe" 2>&1)
  [[ $output == *"env -u UIDOTSH_TOKEN npx -y @uidotsh/install"* ]] || fail "$recipe does not clear inherited UI credentials"
  [[ $output != *"--token"* ]] || fail "$recipe passes the UI token through argv"
done

! grep -q 'UIDOTSH_TOKEN' "$repo/zsh/secrets.tpl" || fail "UI token remains in credential automation"

replaceable_read_only_path="$tmp/replaceable-read-only-path"
writable_path="$tmp/writable-path"
missing_path="$tmp/missing-path"
symlink_target="$tmp/symlink-target"
mkdir -p "$replaceable_read_only_path" "$writable_path"
mkdir -p "$symlink_target/read-only-path"
chmod 0555 "$replaceable_read_only_path"
chmod 0555 "$symlink_target/read-only-path"
zsh_bin=$(command -v zsh)
protected_path=$(dirname "$zsh_bin")
symlink_path="$tmp/symlink-path"
ln -s "$symlink_target/read-only-path" "$symlink_path"
replaceable_symlink="$tmp/replaceable-symlink"
ln -s "$protected_path" "$replaceable_symlink"
# The single-quoted program expands path inside the child zsh, not this shell.
# shellcheck disable=SC2016
output=$(PATH="$writable_path:$replaceable_read_only_path:$symlink_path:$replaceable_symlink:$protected_path::$writable_path:$missing_path:relative" \
  "$zsh_bin" -dfc 'source "$1"; print -l -- "${path[@]}"' -- "$repo/zsh/path-order.zsh")
expected=$(printf '%s\n' "$protected_path" "$writable_path")
[[ "$output" == "$expected" ]] \
  || fail "shell PATH ordering did not reject relative and replaceable read-only entries, put protected directories first, preserve safe class order, and deduplicate entries"

managed_path=$(sed -n '/^      path=(/,/^      )/p' "$repo/home.nix")
expected_managed_path=$(cat <<'EOF'
      path=(
        "$HOME/.opencode/bin"
        "$HOME/.lmstudio/bin"
        "/usr/local/zig"
        "$HOME/.bun/bin"
        "$HOME/go/bin"
        "$HOME/.local/bin"
        "/etc/profiles/per-user/$USER/bin"
        $path
      )
EOF
)
[[ "$managed_path" == "$expected_managed_path" ]] \
  || fail "managed shell PATH entries no longer preserve historical command precedence"

output=$(cd "$repo" && just --summary)
[[ " $output " == *" refresh-secrets "* ]] \
  || fail "the explicit 1Password refresh recipe is no longer available"

policy_surfaces=()
while IFS= read -r -d '' surface; do
  case "$surface" in
    tests/*|examples/*|*.md|*.lock) continue ;;
    Brewfile|justfile|package.json|*.nix|*.sh|*.bash|*.zsh|*.plist|*.json|*.toml|*.yaml|*.yml|*.conf|*.config|*rc|scripts/*|zsh/*|hosts/*|.github/workflows/*)
      policy_surfaces+=("$repo/$surface")
      ;;
  esac
done < <(git -C "$repo" ls-files -z)
while IFS=$'\t' read -r metadata surface; do
  [[ ${metadata%% *} == 100755 && "$surface" != tests/* && "$surface" != examples/* ]] || continue
  policy_surfaces+=("$repo/$surface")
done < <(git -C "$repo" ls-files --stage)

! grep -Eqi 'DISABLE_TELEMETRY|DISABLE_ERROR_REPORTING|CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' \
  "${policy_surfaces[@]}" \
  || fail "Claude Code diagnostics opt-out was added to managed configuration"
! grep -Eqi 'DETSYS_IDS_TELEMETRY|NIX_INSTALLER_DIAGNOSTIC_ENDPOINT|--diagnostic-endpoint([=[:space:]]|$)|sentry[-_]report[-_]endpoint' \
  "${policy_surfaces[@]}" \
  || fail "Determinate Nix diagnostics opt-out was added to managed configuration"

browser_bin="$tmp/browser-bin"
mkdir -p "$browser_bin"
cat > "$browser_bin/npx" <<'EOF'
#!/usr/bin/env bash
if [[ -n ${SIGNAL_READY-} ]]; then
  printf '%s\n' "$$" > "$SIGNAL_CHILD_PID"
  : > "$SIGNAL_READY"
  exec sleep 30
fi
printf 'args=%s\n' "$*"
printf 'optout=%s\n' "${CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS-}"
EOF
chmod +x "$browser_bin/npx"
node_bin=$(command -v node)
output=$(PATH="$browser_bin:/usr/bin:/bin" "$node_bin" "$repo/scripts/chrome-devtools-mcp.js" --isolated --headless)
[[ "$output" == *"args=-y chrome-devtools-mcp@latest --no-usage-statistics --isolated --headless"* ]] \
  || fail "chrome-devtools-mcp launcher omitted the explicit usage-statistics opt-out"
[[ "$output" == *"optout=1"* ]] \
  || fail "chrome-devtools-mcp launcher omitted the opt-out environment fallback"

signal_ready="$tmp/browser-signal-ready"
signal_child_pid="$tmp/browser-signal-child-pid"
SIGNAL_READY="$signal_ready" SIGNAL_CHILD_PID="$signal_child_pid" \
  PATH="$browser_bin:/usr/bin:/bin" "$node_bin" "$repo/scripts/chrome-devtools-mcp.js" >/dev/null 2>&1 &
browser_wrapper_pid=$!
for _ in {1..100}; do
  [[ -e "$signal_ready" ]] && break
  sleep 0.01
done
[[ -e "$signal_ready" ]] || fail "chrome-devtools-mcp signal probe did not start"
kill -TERM "$browser_wrapper_pid"
set +e
wait "$browser_wrapper_pid"
status=$?
set -e
[[ $status -eq 143 ]] || fail "chrome-devtools-mcp launcher returned $status after SIGTERM instead of 143"
browser_child_pid=$(<"$signal_child_pid")
! kill -0 "$browser_child_pid" 2>/dev/null \
  || fail "chrome-devtools-mcp child remained after forwarded SIGTERM"

! grep -Fqi 'clawdbot' "${policy_surfaces[@]}" \
  || fail "Clawdbot returned on a tracked configuration surface"

output=$(cd "$repo" && just --dry-run update-skills 2>&1)
[[ $(grep -c "skills add .* -g -y --agent '\*'" <<<"$output") -eq 3 ]] || fail "skills installers are not explicit and non-interactive"
[[ $output == *"\$(readlink \"\$link\")"* ]] || fail "skill-link cleanup does not inspect symlink targets"
[[ $output != *"-type l -delete"* ]] || fail "skill-link cleanup removes tool-managed symlinks"

skills_sandbox="$tmp/skills-sandbox"
mkdir -p "$skills_sandbox/.agents/skills/shared" "$skills_sandbox/.agents/skills/fresh" \
  "$skills_sandbox/opencode/skills" "$skills_sandbox/bin"
cp "$repo/justfile" "$skills_sandbox/justfile"
ln -s /tool-managed/shared "$skills_sandbox/opencode/skills/shared"
ln -s ../../.agents/skills/stale "$skills_sandbox/opencode/skills/stale"
cat > "$skills_sandbox/bin/git" <<'EOF'
#!/usr/bin/env bash
destination=${@: -1}
mkdir -p "$destination"
printf '%s\n' 'name: learning-opportunities' 'description: test' > "$destination/SKILL.md"
EOF
cat > "$skills_sandbox/bin/rsync" <<'EOF'
#!/usr/bin/env bash
destination=${@: -1}
mkdir -p "$destination"
printf '%s\n' 'name: learning-opportunities' 'description: test' > "$destination/SKILL.md"
EOF
cat > "$skills_sandbox/bin/memtrace" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$skills_sandbox/bin/npx" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "-y @uidotsh/install" ]]; then
  [[ -z \${UIDOTSH_TOKEN+x} ]] || exit 64
  echo ui >> "$skills_sandbox/ui-installs"
fi
EOF
chmod +x "$skills_sandbox/bin/"*
for recipe in update-skills update-ui-skill; do
  UIDOTSH_TOKEN=automated PATH="$skills_sandbox/bin:$PATH" just --justfile "$skills_sandbox/justfile" "$recipe" >/dev/null
done
[[ $(wc -l < "$skills_sandbox/ui-installs") -eq 2 ]] || fail "UI installers did not run without inherited credentials"
[[ $(readlink "$skills_sandbox/opencode/skills/shared") == /tool-managed/shared ]] || fail "shared-skill linking replaced a tool-managed link"
[[ ! -e "$skills_sandbox/opencode/skills/stale" && ! -L "$skills_sandbox/opencode/skills/stale" ]] || fail "managed stale skill link was preserved"
[[ $(readlink "$skills_sandbox/opencode/skills/fresh") == ../../.agents/skills/fresh ]] || fail "missing shared skill link was not created"

rm -rf "$skills_sandbox/opencode"
UIDOTSH_TOKEN=automated PATH="$skills_sandbox/bin:$PATH" just --justfile "$skills_sandbox/justfile" update-skills >/dev/null
[[ -d "$skills_sandbox/opencode/skills" ]] || fail "skill linking did not create its parent directory"
[[ $(readlink "$skills_sandbox/opencode/skills/fresh") == ../../.agents/skills/fresh ]] || fail "fresh checkout skill link was not created"

rebuild_bin="$tmp/rebuild-bin"
mkdir -p "$rebuild_bin"
cat > "$rebuild_bin/sudo" <<EOF
#!/usr/bin/env bash
touch "$tmp/rebuild-sudo-ran"
EOF
cat > "$rebuild_bin/nix" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == eval && "$2" == --raw ]] || exit 90
printf '%s' laszlohoranszky
EOF
cat > "$rebuild_bin/id" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == -un ]] || exit 91
printf '%s\n' laszlohoranszky
EOF
chmod +x "$rebuild_bin/sudo" "$rebuild_bin/nix" "$rebuild_bin/id"

rebuild_home="$tmp/rebuild-home"
mkdir -p "$rebuild_home/Code/dotfiles"
set +e
output=$(cd "$repo" && HOME="$rebuild_home" PATH="$rebuild_bin:/usr/bin:/bin" ./rebuild.sh 2>&1)
status=$?
set -e
[[ $status -eq 1 ]] || fail "rebuild with an existing directory returned $status instead of 1"
[[ $output == *"Refusing to replace existing non-symlink"* ]] || fail "rebuild did not report the conflicting directory"
[[ ! -e "$rebuild_home/Code/dotfiles/dotfiles" ]] || fail "rebuild nested a symlink in the conflicting directory"
[[ ! -e "$tmp/rebuild-sudo-ran" ]] || fail "rebuild continued after detecting the conflicting directory"

rm -rf "$rebuild_home/Code/dotfiles"
HOME="$rebuild_home" PATH="$rebuild_bin:/usr/bin:/bin" "$repo/rebuild.sh"
[[ -L "$rebuild_home/Code/dotfiles" ]] || fail "rebuild did not link a moved clone"
[[ $(cd "$rebuild_home/Code/dotfiles" && pwd -P) == "$repo" ]] || fail "rebuild linked the moved clone incorrectly"
[[ -e "$tmp/rebuild-sudo-ran" ]] || fail "rebuild did not continue after linking the moved clone"

cat > "$tmp/wezterm-regression.lua" <<'EOF'
local callback
local wezterm = {
  action = {
    IncreaseFontSize = "increase-font-size",
    ResetFontSize = "reset-font-size",
    SendKey = function(value) return value end,
  },
  config_builder = function() return {} end,
  font = function(name) return name end,
  on = function(event, handler)
    assert(event == "user-var-changed")
    callback = handler
  end,
}
package.preload.wezterm = function() return wezterm end
assert(dofile(os.getenv("WEZTERM_CONFIG")))
assert(callback)

local performed = {}
local applied
local window = {}
function window:get_config_overrides() return {} end
function window:perform_action(action) table.insert(performed, action) end
function window:set_config_overrides(overrides) applied = overrides end

for _, value in ipairs({ "not-a-number", "+invalid", "" }) do
  assert(pcall(callback, window, {}, "ZEN_MODE", value))
end
assert(#performed == 0)

callback(window, {}, "ZEN_MODE", "+2")
assert(#performed == 2 and applied.enable_tab_bar == false)
callback(window, {}, "ZEN_MODE", "-1")
assert(performed[3] == "reset-font-size" and applied.enable_tab_bar == true)
callback(window, {}, "ZEN_MODE", "19")
assert(applied.font_size == 19 and applied.enable_tab_bar == false)
EOF
WEZTERM_CONFIG="$repo/.wezterm.lua" nvim --headless -u NONE -l "$tmp/wezterm-regression.lua"

fake_bin="$tmp/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/stack-command" <<'EOF'
#!/usr/bin/env bash
name=${0##*/}
if [[ "$name" == gh-axi && "$*" == "setup --help" ]]; then
  echo "usage: gh-axi setup hooks"
  exit 0
fi
if [[ "$name" == gh-axi && "$*" == "setup hooks" ]]; then
  echo "simulated stack hook failure" >&2
  exit 23
fi
exit 0
EOF
chmod +x "$fake_bin/stack-command"
for command in gh jq node npm curl pi claude herdr treehouse no-mistakes gh-axi; do
  ln -s stack-command "$fake_bin/$command"
done
ln -s "$(command -v just)" "$fake_bin/just"

for recipe in setup-firstmate update-firstmate; do
  home="$tmp/${recipe}-home"
  mkdir -p "$home"
  set +e
  output=$(cd "$repo" && HOME="$home" PATH="$fake_bin:/usr/bin:/bin" just "$recipe" 2>&1)
  status=$?
  set -e
  [[ $status -eq 23 ]] || fail "$recipe returned $status instead of the hook failure"
  [[ $output == *"simulated stack hook failure"* ]] || fail "$recipe hid the hook failure"
  [[ $output != *"Done. Next:"* ]] || fail "$recipe reported setup success after a hook failure"
  [[ $output != *"FirstMate stack updated."* ]] || fail "$recipe reported update success after a hook failure"
done

CHROME_DEVTOOLS_AXI_MCP_PATH="/nix/store/test-browser-launcher/bin/chrome-devtools-mcp" \
  INIT_ZSH="$repo/zsh/init.zsh" TEST_TMP="$tmp" SKETCHYBAR_PWD_FILE="$tmp/sketchybar_pwd" zsh -f <<'EOF'
fzf() { return 0 }
direnv() { return 0 }
zoxide() { return 0 }
atuin() { return 0 }
kubectl() { return 0 }
add-zsh-hook() { : }
zle() { : }
bindkey() { : }
source "$INIT_ZSH"

[[ "$CHROME_DEVTOOLS_AXI_MCP_PATH" == "/nix/store/test-browser-launcher/bin/chrome-devtools-mcp" ]] \
  || { print -u2 "FAIL: live shell replaced the Nix-managed browser launcher"; exit 1; }
[[ "$CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS" == 1 ]] \
  || { print -u2 "FAIL: live shell omitted the browser telemetry opt-out"; exit 1; }

# SketchyBar is macOS-only (see zsh/init.zsh): the function and its chpwd hook are
# defined only under `$OSTYPE == darwin*`. Gate the assertions to match, otherwise
# this whole block fails command-not-found on the headless Linux sandbox.
if [[ "$OSTYPE" == darwin* ]]; then
  victim="$TEST_TMP/sketchybar-victim"
  print -r -- "unchanged" > "$victim"
  rm -f -- "$SKETCHYBAR_PWD_FILE"
  ln -s "$victim" "$SKETCHYBAR_PWD_FILE"
  update_sketchybar_pwd
  [[ ! -L "$SKETCHYBAR_PWD_FILE" ]] || { print -u2 "FAIL: SketchyBar state remained a symlink"; exit 1; }
  [[ "$(<"$SKETCHYBAR_PWD_FILE")" == "$PWD" ]] || { print -u2 "FAIL: SketchyBar state did not contain the current directory"; exit 1; }
  [[ "$(<"$victim")" == "unchanged" ]] || { print -u2 "FAIL: SketchyBar state write followed a symlink"; exit 1; }

  victim_dir="$TEST_TMP/sketchybar-victim-dir"
  mkdir -p "$victim_dir"
  rm -f -- "$SKETCHYBAR_PWD_FILE"
  ln -s "$victim_dir" "$SKETCHYBAR_PWD_FILE"
  update_sketchybar_pwd
  [[ ! -L "$SKETCHYBAR_PWD_FILE" ]] || { print -u2 "FAIL: SketchyBar state remained a directory symlink"; exit 1; }
  [[ -f "$SKETCHYBAR_PWD_FILE" ]] || { print -u2 "FAIL: SketchyBar state did not replace the directory symlink"; exit 1; }
  [[ "$(<"$SKETCHYBAR_PWD_FILE")" == "$PWD" ]] || { print -u2 "FAIL: SketchyBar state did not contain the current directory"; exit 1; }
  victim_entries=("$victim_dir"/*(N))
  [[ ${#victim_entries} -eq 0 ]] || { print -u2 "FAIL: SketchyBar state write followed a directory symlink"; exit 1; }
else
  # Non-macOS: the guard in zsh/init.zsh must leave the helper and hook undefined.
  (( ${+functions[update_sketchybar_pwd]} == 0 )) \
    || { print -u2 "FAIL: update_sketchybar_pwd defined on non-macOS"; exit 1; }
  [[ ${chpwd_functions[(Ie)update_sketchybar_pwd]} -eq 0 ]] \
    || { print -u2 "FAIL: SketchyBar chpwd hook registered on non-macOS"; exit 1; }
fi

repo="$TEST_TMP/deploy-repo"
mkdir -p "$repo"
cd "$repo"
git init -q
git config user.name Test
git config user.email test@example.com
touch tracked
git add tracked
git commit -qm initial
git remote add origin https://github.com/example/example.git

sha=$(git rev-parse --short HEAD)
tag="prod/$sha"
mkdir -p .git/refs/tags
print collision > .git/refs/tags/prod
output=$(deploy prod 2>&1)
rc=$?
[[ $rc -ne 0 ]] || { print -u2 "FAIL: tag creation failure returned success"; exit 1; }
[[ $output == *"Failed to create tag $tag"* ]] || { print -u2 "FAIL: tag creation failure was not reported"; exit 1; }
[[ $output != *"Tag $tag already exists"* ]] || { print -u2 "FAIL: non-existence failure was reported as an existing tag"; exit 1; }

rm .git/refs/tags/prod
git tag "$tag"
output=$(deploy prod 2>&1)
rc=$?
[[ $rc -ne 0 ]] || { print -u2 "FAIL: existing tag returned success"; exit 1; }
[[ $output == *"Tag $tag already exists"* ]] || { print -u2 "FAIL: existing tag was not identified"; exit 1; }

git tag -d "$tag" >/dev/null
rejecting_remote="$TEST_TMP/rejecting-remote.git"
git init --bare -q "$rejecting_remote"
cat > "$rejecting_remote/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$rejecting_remote/hooks/pre-receive"
git remote set-url origin "$rejecting_remote"
output=$(deploy prod 2>&1)
rc=$?
[[ $rc -ne 0 ]] || { print -u2 "FAIL: rejected push returned success"; exit 1; }
[[ $output == *"Push failed; removing local tag $tag"* ]] || { print -u2 "FAIL: rejected push cleanup was not reported"; exit 1; }
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { print -u2 "FAIL: rejected push left the local tag behind"; exit 1; }
EOF

echo "shell regressions OK"
