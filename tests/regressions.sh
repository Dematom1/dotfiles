#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

av_probe="$tmp/av-probe"
cat > "$av_probe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"findings":[{"source":"probe","severity":"high","value":"MUST_NOT_LEAK","affected":[{"path":"MUST_NOT_LEAK"}]}]}'
EOF
chmod +x "$av_probe"

output=$("$repo/scripts/av-scan-summary.sh" --scanner "$av_probe")
[[ $output == '{"total":1,"categories":[{"source":"probe","severity":"high","count":1}]}' ]] \
  || fail "Automic Vault operator summary exposed or misreported finding payloads"
[[ $output != *MUST_NOT_LEAK* ]] \
  || fail "Automic Vault operator summary leaked raw finding data"

set +e
output=$("$repo/scripts/av-scan-summary.sh" --require-clean --scanner "$av_probe" 2>&1)
status=$?
set -e
[[ $status -eq 1 ]] || fail "Automic Vault clean acceptance allowed findings"
[[ $output != *MUST_NOT_LEAK* ]] || fail "Automic Vault clean acceptance leaked raw finding data"

av_error_probe="$tmp/av-error-probe"
cat > "$av_error_probe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"findings":[]}'
exit 9
EOF
chmod +x "$av_error_probe"
set +e
output=$("$repo/scripts/av-scan-summary.sh" --scanner "$av_error_probe" 2>&1)
status=$?
set -e
[[ $status -eq 1 ]] || fail "Automic Vault operator summary accepted an operational scanner failure"
[[ $output == *"failed operationally with exit 9"* ]] \
  || fail "Automic Vault operator summary hid the scanner exit state"

mapfile -t git_helpers < <(git config --file "$repo/git/config" --get-all credential.helper)
[[ ${#git_helpers[@]} -eq 2 && -z ${git_helpers[0]} && ${git_helpers[1]} == osxkeychain ]] \
  || fail "tracked Git config does not reset plaintext helpers before selecting macOS Keychain"

python3 "$repo/tests/remove-axi-session-start-hook.py"

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

output=$(cd "$repo" && just --summary)
[[ " $output " == *" refresh-secrets "* ]] \
  || fail "the explicit 1Password refresh recipe is no longer available"

policy_surfaces=()
while IFS= read -r -d '' surface; do
  case "$surface" in
    tests/*|examples/*|*.md|*.lock) continue ;;
    Brewfile|justfile|package.json|*.nix|*.sh|*.bash|*.zsh|*.plist|*.json|*.toml|*.yaml|*.yml|*.conf|*.config|*rc|scripts/*|zsh/*|hosts/*|.github/workflows/*)
      [[ -f "$repo/$surface" ]] || continue
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

skills_sandbox="$tmp/skills-sandbox"
mkdir -p "$skills_sandbox/.agents/skills/shared" "$skills_sandbox/.agents/skills/fresh" \
  "$skills_sandbox/opencode/skills" "$skills_sandbox/home" "$skills_sandbox/bin"
cp "$repo/justfile" "$skills_sandbox/justfile"
mkdir -p "$skills_sandbox/scripts"
cp "$repo/agent-tooling.json" "$skills_sandbox/agent-tooling.json"
cp "$repo/scripts/agent-tooling-reconcile.py" "$skills_sandbox/scripts/agent-tooling-reconcile.py"
ln -s /tool-managed/shared "$skills_sandbox/opencode/skills/shared"
ln -s ../../.agents/skills/stale "$skills_sandbox/opencode/skills/stale"
cat > "$skills_sandbox/bin/npx" <<'EOF'
#!/usr/bin/env bash
EOF
chmod +x "$skills_sandbox/bin/"*
HOME="$skills_sandbox/home" PATH="$skills_sandbox/bin:$PATH" \
  just --justfile "$skills_sandbox/justfile" update-skills >/dev/null
[[ $(readlink "$skills_sandbox/opencode/skills/shared") == /tool-managed/shared ]] || fail "shared-skill linking replaced a tool-managed link"
[[ ! -e "$skills_sandbox/opencode/skills/stale" && ! -L "$skills_sandbox/opencode/skills/stale" ]] || fail "managed stale skill link was preserved"
[[ $(readlink "$skills_sandbox/opencode/skills/fresh") == ../../.agents/skills/fresh ]] || fail "missing shared skill link was not created"

rm -rf "$skills_sandbox/opencode"
HOME="$skills_sandbox/home" PATH="$skills_sandbox/bin:$PATH" \
  just --justfile "$skills_sandbox/justfile" update-skills >/dev/null
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
