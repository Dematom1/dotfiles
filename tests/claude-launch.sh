#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

profile=darwinConfigurations.personal.config.home-manager.users.laszlohoranszky
aliases=$(nix eval --raw "$repo#$profile.programs.zsh.shellAliases" \
  --apply 'aliases: builtins.toJSON aliases')
[[ $aliases != *headroom* ]] \
  || fail "generated Claude shell aliases still route through Headroom"

activation=$(nix build --no-link --print-out-paths \
  "$repo#$profile.home.activationPackage")
home="$tmp/home"
zdot="$tmp/zdot"
mkdir -p "$home/Code" "$home/.local/bin" "$tmp/bin" "$zdot"
ln -s "$repo" "$home/Code/dotfiles"
for file in .zshenv .zprofile .zshrc; do
  cp -L "$activation/home-files/$file" "$zdot/$file"
done

for command in fzf direnv zoxide atuin kubectl; do
  cat > "$tmp/bin/$command" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$tmp/bin/$command"
done

cat > "$home/.local/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0" > "$CLAUDE_MARKER"
printf '%s\n' '2.1.test'
EOF
cat > "$home/.local/bin/headroom" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' invoked > "$HEADROOM_MARKER"
exit 99
EOF
chmod +x "$home/.local/bin/claude" "$home/.local/bin/headroom"

output=$(
  HOME="$home" ZDOTDIR="$zdot" CLAUDE_MARKER="$tmp/claude" \
    HEADROOM_MARKER="$tmp/headroom" PATH="$tmp/bin:/usr/bin:/bin" \
    zsh -lic '
      [[ "$(command -v claude)" == "$HOME/.local/bin/claude" ]] || exit 11
      claude --version
    ' 2>&1
) || fail "generated login shell could not start Claude: $output"
[[ $output == *2.1.test* ]] || fail "generated login shell did not start Claude"
[[ -s "$tmp/claude" ]] || fail "generated login shell did not execute the Claude launcher"
[[ ! -e "$tmp/headroom" ]] || fail "generated login shell invoked Headroom"

echo "Claude launch regression OK"
