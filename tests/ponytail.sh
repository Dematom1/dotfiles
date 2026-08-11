#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$tmp/bin"
cat > "$tmp/bin/pi" <<'EOF'
#!/usr/bin/env bash
printf 'pi %s\n' "$*" >> "$PONYTAIL_TEST_LOG"
EOF
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$PONYTAIL_TEST_LOG"
EOF
cat > "$tmp/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
chmod +x "$tmp/bin/pi" "$tmp/bin/claude" "$tmp/bin/uname"

just_bin=$(command -v just)
log="$tmp/invocations"
export PONYTAIL_TEST_LOG="$log"

for _ in 1 2; do
  PATH="$tmp/bin:/usr/bin:/bin" "$just_bin" --justfile "$repo/justfile" _setup-ponytail >/dev/null
done

[[ $(grep -Fxc 'pi install git:github.com/DietrichGebert/ponytail' "$log") -eq 2 ]] \
  || fail "Pi Ponytail source was not reconciled exactly once per setup"
[[ $(grep -Fxc 'claude plugin marketplace add --scope user DietrichGebert/ponytail' "$log") -eq 2 ]] \
  || fail "Claude Ponytail marketplace identity or scope changed"
[[ $(grep -Fxc 'claude plugin install --scope user ponytail@ponytail' "$log") -eq 2 ]] \
  || fail "Claude Ponytail plugin identity or scope changed"

: > "$log"
for _ in 1 2; do
  PATH="$tmp/bin:/usr/bin:/bin" "$just_bin" --justfile "$repo/justfile" _update-ponytail >/dev/null
done

for expected in \
  'pi install git:github.com/DietrichGebert/ponytail' \
  'pi update git:github.com/DietrichGebert/ponytail' \
  'claude plugin marketplace add --scope user DietrichGebert/ponytail' \
  'claude plugin install --scope user ponytail@ponytail' \
  'claude plugin marketplace update ponytail' \
  'claude plugin update ponytail@ponytail'; do
  [[ $(grep -Fxc "$expected" "$log") -eq 2 ]] \
    || fail "repeated update did not reconcile exactly once: $expected"
done

mv "$tmp/bin/claude" "$tmp/claude"
set +e
output=$(PATH="$tmp/bin:/usr/bin:/bin" "$just_bin" --justfile "$repo/justfile" _setup-ponytail 2>&1)
status=$?
set -e
[[ $status -eq 1 ]] || fail "Darwin setup without Claude returned $status instead of 1"
[[ $output == *"missing Claude Code"* ]] || fail "Darwin setup did not report missing Claude Code"

echo "Ponytail setup checks passed"
