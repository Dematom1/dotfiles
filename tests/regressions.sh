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
chmod +x "$tmp/failing-axi" "$tmp/unsupported-axi" "$tmp/broken-probe-axi" \
  "$tmp/ambiguous-probe-axi" "$tmp/empty-probe-axi" "$tmp/explicitly-unsupported-axi"

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

for tool in ambiguous-probe-axi empty-probe-axi; do
  set +e
  output=$(cd "$repo" && just _setup-axi-hooks "$tmp/$tool" 2>&1)
  status=$?
  set -e
  [[ $status -eq 1 ]] || fail "$tool returned $status instead of 1"
  [[ $output == *"unrecognized output"* ]] || fail "$tool output was not rejected"
  [[ $output != *"no setup hooks"* ]] || fail "$tool was reported as unsupported hooks"
done

output=$(cd "$repo" && just _setup-axi-hooks "$tmp/explicitly-unsupported-axi" 2>&1)
[[ $output == *"no setup hooks"* ]] || fail "explicit zero-exit unsupported output was not identified"
[[ ! -e "$tmp/explicitly-unsupported-ran" ]] || fail "explicitly unsupported setup hooks were executed"

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
for command in gh jq node npm curl pi herdr treehouse no-mistakes gh-axi; do
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

INIT_ZSH="$repo/zsh/init.zsh" TEST_TMP="$tmp" zsh -f <<'EOF'
fzf() { return 0 }
direnv() { return 0 }
zoxide() { return 0 }
atuin() { return 0 }
kubectl() { return 0 }
add-zsh-hook() { : }
zle() { : }
bindkey() { : }
source "$INIT_ZSH"

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
EOF

echo "shell regressions OK"
