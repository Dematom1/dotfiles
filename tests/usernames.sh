#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

av_bin=$(command -v av) || fail "installed Automic Vault scanner is unavailable"
zsh_bin=$(command -v zsh) || fail "zsh is unavailable"
scan_external_summary=

scan_generated_zsh() {
  local profile=$1
  local scanner=$2
  local generated_zdot=${3-}
  local scan_output scan_status

  set +e
  if [[ -n $generated_zdot ]]; then
    scan_output=$(ZDOTDIR="$generated_zdot" "$zsh_bin" -lic 'exec "$1" scan --json' \
      -- "$scanner" 2>/dev/null)
  else
    scan_output=$("$zsh_bin" -lic 'exec "$1" scan --json' \
      -- "$scanner" 2>/dev/null)
  fi
  scan_status=$?
  set -e
  if [[ $scan_status -ne 0 ]]; then
    echo "$profile profile scanner failed operationally with exit $scan_status" >&2
    return 1
  fi
  jq -e 'type == "object" and (.findings | type == "array")' >/dev/null <<<"$scan_output" || {
    echo "$profile profile scanner did not return JSON" >&2
    return 1
  }
  if [[ -n $generated_zdot ]] && jq -e '
    .findings[]
    | select(.source == "zsh" or .source == "bash+zsh")
  ' >/dev/null <<<"$scan_output"; then
    echo "$profile profile generated zsh configuration triggers a repository-owned Automic Vault warning" >&2
    return 1
  fi
  scan_external_summary=$(jq -c '
    [.findings[]
      | select(.source != "zsh" and .source != "bash+zsh")
      | {source, severity}]
    | group_by([.source, .severity])
    | map({source: .[0].source, severity: .[0].severity, count: length})
    | sort_by([.source, .severity])
  ' <<<"$scan_output") || {
    echo "$profile profile scanner findings could not be summarized" >&2
    return 1
  }
}

scan_generated_zsh baseline "$av_bin" \
  || fail "configured login-shell scanner baseline failed"
baseline_external_summary=$scan_external_summary

# A valid-looking empty report cannot mask an operational scanner failure.
scanner_probe="$tmp/av-operational-error"
cat > "$scanner_probe" <<'EOF'
#!/bin/sh
printf '%s\n' '{"findings":[]}'
exit 1
EOF
chmod +x "$scanner_probe"
scanner_probe_home="$tmp/av-operational-error-home"
mkdir -p "$scanner_probe_home"
: > "$scanner_probe_home/.zshenv"
: > "$scanner_probe_home/.zshrc"
if scan_generated_zsh probe "$scanner_probe" "$scanner_probe_home" 2>/dev/null; then
  fail "generated-profile scanner regression accepted an operational failure"
fi

nix_value() {
  nix eval --raw "$repo#$1"
}

[[ $(nix_value darwinConfigurations.personal.config.system.primaryUser) == laszlohoranszky ]] \
  || fail "personal profile selected the wrong primary user"
[[ $(nix_value darwinConfigurations.personal.config.users.users.laszlohoranszky.home) == /Users/laszlohoranszky ]] \
  || fail "personal profile selected the wrong home"
[[ $(nix_value darwinConfigurations.personal.config.home-manager.users.laszlohoranszky.home.homeDirectory) == /Users/laszlohoranszky ]] \
  || fail "personal Home Manager selected the wrong home"

[[ $(nix_value darwinConfigurations.work.config.system.primaryUser) == laszlo ]] \
  || fail "work profile selected the wrong primary user"
[[ $(nix_value darwinConfigurations.work.config.users.users.laszlo.home) == /Users/laszlo ]] \
  || fail "work profile selected the wrong home"
[[ $(nix_value darwinConfigurations.work.config.home-manager.users.laszlo.home.homeDirectory) == /Users/laszlo ]] \
  || fail "work Home Manager selected the wrong home"

for profile_user in personal:laszlohoranszky work:laszlo; do
  IFS=: read -r profile user <<<"$profile_user"
  prefix="darwinConfigurations.$profile.config.home-manager.users.$user.home.sessionVariables"
  [[ $(nix_value "$prefix.CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS") == 1 ]] \
    || fail "$profile profile did not disable chrome-devtools-mcp usage statistics"
  launcher=$(nix_value "$prefix.CHROME_DEVTOOLS_AXI_MCP_PATH")
  [[ $launcher == /nix/store/*/bin/chrome-devtools-mcp ]] \
    || fail "$profile profile did not select the Nix-managed chrome-devtools-mcp launcher"
  [[ $launcher != *"/Users/"*"/Code/dotfiles"* ]] \
    || fail "$profile profile browser launcher depends on a source checkout path"
  [[ $(nix eval --raw "$repo#darwinConfigurations.$profile.config.homebrew.casks" \
    --apply 'casks: builtins.concatStringsSep "," (map (cask: cask.name) casks)') == \
    *"automic-vault/isotopes/automic-vault"* ]] \
    || fail "$profile profile does not install Automic Vault through Homebrew"
  [[ $(nix eval --raw "$repo#darwinConfigurations.$profile.config.home-manager.users.$user.home.sessionPath" \
    --apply 'paths: builtins.concatStringsSep ":" paths') == *"/usr/local/bin"* ]] \
    || fail "$profile profile does not expose the Automic Vault CLI location on PATH"
  alias_names=$(nix eval --raw "$repo#darwinConfigurations.$profile.config.home-manager.users.$user.programs.zsh.shellAliases" \
    --apply 'aliases: builtins.concatStringsSep "," (builtins.attrNames aliases)')
  if grep -Eqi 'TOKEN|SECRET|PASSWORD|PASS|API_KEY|ACCESS_KEY|PRIVATE_KEY|AUTH' <<<"$alias_names"; then
    fail "$profile profile renders a shell alias that Automic Vault treats as a secret assignment"
  fi
  activation=$(nix build --no-link --print-out-paths \
    "$repo#darwinConfigurations.$profile.config.home-manager.users.$user.home.activationPackage")
  scan_home="$tmp/av-$profile"
  mkdir -p "$scan_home"
  cp -L "$activation/home-files/.zshenv" "$scan_home/.zshenv"
  cp -L "$activation/home-files/.zshrc" "$scan_home/.zshrc"
  chmod u+w "$scan_home/.zshenv" "$scan_home/.zshrc"

  scan_generated_zsh "$profile" "$av_bin" "$scan_home" \
    || fail "$profile profile generated zsh scan failed"
  [[ $scan_external_summary == "$baseline_external_summary" ]] \
    || fail "$profile profile changed external Automic Vault findings"

  [[ -x $launcher ]] || fail "$profile profile browser launcher is not executable"
  node --check "$launcher" >/dev/null \
    || fail "$profile profile browser launcher is not a Node-compatible JavaScript entrypoint"
done

[[ $(nix eval --raw "$repo#darwinConfigurations.personal.config.users.users" \
  --apply 'users: builtins.concatStringsSep "," (builtins.attrNames users)') == laszlohoranszky ]] \
  || fail "personal profile rendered an unexpected user set"
[[ $(nix eval --raw "$repo#darwinConfigurations.work.config.users.users" \
  --apply 'users: builtins.concatStringsSep "," (builtins.attrNames users)') == laszlo ]] \
  || fail "work profile rendered an unexpected user set"

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/nix" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == eval && "$2" == --raw ]] || exit 90
printf '%s\n' "$3" >> "$TEST_NIX_LOG"
case "$3" in
  *'#darwinConfigurations.personal.config.system.primaryUser') printf '%s' laszlohoranszky ;;
  *'#darwinConfigurations.work.config.system.primaryUser') printf '%s' laszlo ;;
  *) exit 91 ;;
esac
EOF
cat > "$fake_bin/id" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == -un ]] || exit 92
printf '%s\n' "$TEST_CURRENT_USER"
EOF
cat > "$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_SUDO_LOG"
EOF
chmod +x "$fake_bin/nix" "$fake_bin/id" "$fake_bin/sudo"

run_rebuild() {
  local current_user=$1
  local profile=${2-__missing__}
  local case_name=$3
  local home="$tmp/home-$case_name"
  mkdir -p "$home/.config"
  if [[ "$profile" != __missing__ ]]; then
    printf '%s\n' "$profile" > "$home/.config/dotfiles-profile"
  fi
  : > "$tmp/nix-$case_name.log"
  rm -f "$tmp/sudo-$case_name.log"
  HOME="$home" \
    TEST_CURRENT_USER="$current_user" \
    TEST_NIX_LOG="$tmp/nix-$case_name.log" \
    TEST_SUDO_LOG="$tmp/sudo-$case_name.log" \
    PATH="$fake_bin:/usr/bin:/bin" \
    "$repo/rebuild.sh"
}

run_rebuild laszlohoranszky __missing__ personal-default
[[ $(<"$tmp/sudo-personal-default.log") == "darwin-rebuild switch --flake $tmp/home-personal-default/Code/dotfiles#personal" ]] \
  || fail "default personal rebuild selected the wrong flake"

run_rebuild laszlo work work
[[ $(<"$tmp/sudo-work.log") == "darwin-rebuild switch --flake $tmp/home-work/Code/dotfiles#work" ]] \
  || fail "work rebuild selected the wrong flake"

set +e
output=$(run_rebuild laszlo __missing__ missing-on-work 2>&1)
status=$?
set -e
[[ $status -eq 1 ]] || fail "missing work profile returned $status instead of 1"
[[ $output == *"profile 'personal' targets macOS account 'laszlohoranszky'"* ]] \
  || fail "missing work profile did not explain the account mismatch"
[[ ! -e "$tmp/sudo-missing-on-work.log" ]] || fail "missing work profile reached darwin-rebuild"

set +e
output=$(run_rebuild laszlohoranszky work wrong-account 2>&1)
status=$?
set -e
[[ $status -eq 1 ]] || fail "wrong-account work profile returned $status instead of 1"
[[ $output == *"profile 'work' targets macOS account 'laszlo'"* ]] \
  || fail "wrong-account work profile did not explain the account mismatch"
[[ ! -e "$tmp/sudo-wrong-account.log" ]] || fail "wrong-account work profile reached darwin-rebuild"

for unsupported in staging ''; do
  case_name=unsupported-${unsupported:-empty}
  set +e
  output=$(run_rebuild laszlo "$unsupported" "$case_name" 2>&1)
  status=$?
  set -e
  [[ $status -eq 1 ]] || fail "unsupported profile '$unsupported' returned $status instead of 1"
  [[ $output == *"Unsupported dotfiles profile"* ]] || fail "unsupported profile '$unsupported' had no clear error"
  [[ ! -s "$tmp/nix-$case_name.log" ]] || fail "unsupported profile '$unsupported' reached Nix evaluation"
  [[ ! -e "$tmp/sudo-$case_name.log" ]] || fail "unsupported profile '$unsupported' reached darwin-rebuild"
done

echo "username regressions OK"
