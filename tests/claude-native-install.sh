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
  broken-binary|success)
    echo 'mkdir -p "$HOME/.local/bin"'
    echo "printf '#!/bin/sh\nexit ${INSTALL_EXIT:-0}\n' > \"\$HOME/.local/bin/claude\""
    echo 'chmod +x "$HOME/.local/bin/claude"'
    ;;
esac
EOF
chmod +x "$tmp/bin/curl"
export HOME="$tmp/home" PATH="$tmp/bin:$PATH" INSTALL_MODE=success
manual='install it by running: curl -fsSL https://claude.ai/install.sh | bash'

DRY_RUN=1 bash "$repo/scripts/install-claude-native.sh"
test ! -e "$HOME/calls"
bash "$repo/scripts/install-claude-native.sh"
test -x "$HOME/.local/bin/claude"
bash "$repo/scripts/install-claude-native.sh"
test "$(wc -l < "$HOME/calls" | tr -d ' ')" = 1

# A claude that exists but no longer runs is reinstalled.
printf '#!/bin/sh\nexit 1\n' > "$HOME/.local/bin/claude"
bash "$repo/scripts/install-claude-native.sh"
"$HOME/.local/bin/claude"
test "$(wc -l < "$HOME/calls" | tr -d ' ')" = 2

# Every failure warns with the manual command but never fails activation.
rm "$HOME/.local/bin/claude"
for INSTALL_MODE in download-failure installer-failure no-binary broken-binary; do
  export INSTALL_MODE INSTALL_EXIT=1
  if ! bash "$repo/scripts/install-claude-native.sh" > "$tmp/output" 2>&1; then
    echo "Installer failure was fatal: $INSTALL_MODE" >&2
    cat "$tmp/output" >&2
    exit 1
  fi
  grep -qF 'WARNING: native Claude Code was not installed' "$tmp/output"
  grep -qF "$manual" "$tmp/output"
  rm -f "$HOME/.local/bin/claude"
done

# Activation's PATH lacked curl once; the script must survive an empty PATH.
if ! env -i HOME="$HOME" PATH= "$BASH" "$repo/scripts/install-claude-native.sh" > "$tmp/output" 2>&1; then
  echo "Installer was fatal with an empty PATH" >&2
  cat "$tmp/output" >&2
  exit 1
fi
grep -qF 'curl is not on PATH' "$tmp/output"
grep -qF "$manual" "$tmp/output"
echo 'Claude native installation checks passed'
