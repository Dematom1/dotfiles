#!/usr/bin/env bash
# Build (never switch) what `just rebuild` would activate, plus the flake checks,
# and confirm the activation script wires the m87 and av steps.
# usage: build.sh OUT_DIR [personal|work]   -> writes OUT_DIR/build.env
set -euo pipefail

out=${1:?usage: build.sh OUT_DIR [personal|work]}
profile=${2:-}
repo=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
mkdir -p "$out"
failed=0
pass() { echo "build $1: PASS"; }
fail() { echo "build $1: FAIL - $2"; failed=1; }

# Same profile selection as rebuild.sh.
if [[ -z $profile ]]; then
  profile=personal
  [[ ! -f "$HOME/.config/dotfiles-profile" ]] || profile=$(<"$HOME/.config/dotfiles-profile")
fi

# rebuild.sh's account guard: it refuses to switch when these differ.
user=$(nix eval --raw "$repo#darwinConfigurations.$profile.config.system.primaryUser")
if [[ "$user" == "$(id -un)" ]]; then
  pass "account guard ($profile targets $user)"
else
  echo "build account guard: NOTE - $profile targets $user, not $(id -un); just rebuild would refuse here"
fi

if system=$(nix build "$repo#darwinConfigurations.$profile.system" --no-link --print-out-paths \
  2> "$out/build.log"); then
  pass "darwin system ($system)"
else
  fail "darwin system" "see $out/build.log"
  exit 1
fi
generation=$(nix-store -qR "$system" | grep -- '-home-manager-generation$')
[[ $(wc -l <<<"$generation") -eq 1 ]] || { fail generation "expected one HM generation"; exit 1; }
printf 'PROFILE=%s\nSYSTEM=%s\nGENERATION=%s\n' "$profile" "$system" "$generation" > "$out/build.env"

# Activation order the m87 steps rely on (see home.nix entryBetween).
order=$(sed -n 's/^_iNote "Activating %s" "\(.*\)"$/\1/p' "$generation/activate")
printf '%s\n' "$order" > "$out/activation-order.txt"
expected="writeBoundary m87GithubDiscovery m87DaemonHandoff setupLaunchAgents"
actual=$(grep -xE "${expected// /|}" <<<"$order" | tr '\n' ' ')
if [[ "$actual" == "$expected " ]]; then
  pass "activation order ($expected)"
else
  fail "activation order" "got: $actual"
fi

plist="$generation/LaunchAgents/org.nix-community.home.m87.plist"
home=$(nix eval --raw "$repo#darwinConfigurations.$profile.config.users.users.$user.home")
if plutil -lint "$plist" > /dev/null && grep -q "<string>$home/.m87</string>" "$plist"; then
  pass "managed m87 plist"
else
  fail "managed m87 plist" "missing or not pointing at ~/.m87"
fi
if [[ -x "$generation/home-path/bin/av" ]]; then pass "av wrapper installed"; else fail "av wrapper" "missing"; fi

# Flake checks for this machine (signoff-install, agent-tools-layout, ...).
arch=$(nix eval --raw --impure --expr builtins.currentSystem)
for check in $(nix eval --json "$repo#checks.$arch" --apply builtins.attrNames | jq -r '.[]'); do
  if nix build "$repo#checks.$arch.$check" --no-link 2>> "$out/checks.log"; then
    pass "check $check"
  else
    fail "check $check" "see $out/checks.log"
  fi
done

live=$(readlink /run/current-system || true)
if [[ "$live" == "$system" ]]; then
  echo "build live system: same as this build (rebuild would be a no-op switch)"
else
  echo "build live system: differs ($live); just rebuild would switch to this build"
fi
exit "$failed"
