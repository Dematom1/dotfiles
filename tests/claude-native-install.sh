#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d "$repo/.claude-native-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo called >> "$HOME/calls"
[[ "$*" == '-fsSL https://claude.ai/install.sh' ]] || exit 2
case "$INSTALL_MODE" in
  download-failure) exit 22 ;;
  installer-failure) echo 'exit 42' ;;
  no-binary) echo ':' ;;
  success)
    echo 'mkdir -p "$HOME/.local/bin"'
    echo 'printf "#!/bin/sh\nexit 0\n" > "$HOME/.local/bin/claude"'
    echo 'chmod +x "$HOME/.local/bin/claude"'
    ;;
esac
EOF
chmod +x "$tmp/bin/curl"
export HOME="$tmp/home" PATH="$tmp/bin:$PATH" INSTALL_MODE=success
DRY_RUN=1 bash "$repo/scripts/install-claude-native.sh"
test ! -e "$HOME/calls"
bash "$repo/scripts/install-claude-native.sh"
test -x "$HOME/.local/bin/claude"
bash "$repo/scripts/install-claude-native.sh"
test "$(wc -l < "$HOME/calls" | tr -d ' ')" = 1
rm "$HOME/.local/bin/claude"
for INSTALL_MODE in download-failure installer-failure no-binary; do
  export INSTALL_MODE
  if bash "$repo/scripts/install-claude-native.sh" > "$tmp/output" 2>&1; then
    echo "Unexpected installer success: $INSTALL_MODE" >&2
    exit 1
  fi
  grep -q 'ERROR: native Claude Code' "$tmp/output"
done
echo 'Claude native installation checks passed'
