#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

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
