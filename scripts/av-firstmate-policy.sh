#!/usr/bin/env bash
# Gate the managed `av` command on Firstmate's registered project identity.
# This only gates CLI availability. It never changes `av` arguments or policy.
set -euo pipefail

AV_VENDOR_CLI=${AV_VENDOR_CLI:-/usr/local/bin/av}

fail() {
  printf 'av unavailable: %s\n' "$1" >&2
  exit 126
}

absolute_dir() {
  local path=$1
  [ -d "$path" ] || return 1
  CDPATH='' cd -P -- "$path" && pwd -P
}

# A trusted path may not contain a symlink at any component. Firstmate and Git
# provide the identity binding; this check prevents a second spelling of it.
contains_symlink() {
  local path=$1 rest component current=/
  case "$path" in
    /*) rest=${path#/} ;;
    *) return 1 ;;
  esac
  while [ -n "$rest" ]; do
    case "$rest" in
      */*) component=${rest%%/*}; rest=${rest#*/} ;;
      *) component=$rest; rest= ;;
    esac
    [ -n "$component" ] || continue
    current="$current$component"
    [ ! -L "$current" ] || return 0
    current="$current/"
  done
  return 1
}

same_path() {
  [ "$1" = "$2" ]
}

field() {
  local key=$1 line value count=0
  while IFS= read -r line; do
    case "$line" in
      "$key"=*)
        count=$((count + 1))
        value=${line#*=}
        ;;
    esac
  done < "$META"
  [ "$count" -eq 1 ] || return 1
  printf '%s\n' "$value"
}

registered_project() {
  local candidate=$1 name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in
      *[!A-Za-z0-9._-]*) continue ;;
    esac
    candidate="$PROJECTS/$name"
    [ -d "$candidate" ] || continue
    [ ! -L "$candidate" ] || continue
    contains_symlink "$candidate" && continue
    candidate_root=$(absolute_dir "$candidate") || continue
    same_path "$candidate_root" "$candidate" || continue
    [ -d "$candidate/.git" ] || continue
    [ ! -L "$candidate/.git" ] || continue
    git_root=$(git -C "$candidate" rev-parse --path-format=absolute --show-toplevel 2>/dev/null) || continue
    same_path "$git_root" "$candidate" || continue
    candidate_common=$(git -C "$candidate" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
    same_path "$candidate_common" "$candidate/.git" || continue
    if same_path "$candidate" "$1"; then
      REGISTERED_COMMON=$candidate_common
      return 0
    fi
  done < <(awk '
    /^[[:space:]]*-[[:space:]]+[A-Za-z0-9._-]+([[:space:]]+\[[^]]*\])?[[:space:]]+-/ { print $2 }
  ' "$REGISTRY")
  return 1
}

[ -x "$AV_VENDOR_CLI" ] || fail "the signed vendor CLI is not executable"
FM_HOME=${FM_HOME:-${HOME:?}/agent-workspace}
[ "${FM_HOME#/}" != "$FM_HOME" ] || fail "Firstmate home must be absolute"
[ ! -L "$FM_HOME" ] || fail "Firstmate home is a symlink"
contains_symlink "$FM_HOME" && fail "Firstmate home contains a symlink"
FM_HOME=$(absolute_dir "$FM_HOME") || fail "Firstmate home is not a directory"

DATA="$FM_HOME/data"
PROJECTS="$FM_HOME/projects"
STATE="$FM_HOME/state"
REGISTRY="$DATA/projects.md"
[ -d "$DATA" ] && [ -d "$PROJECTS" ] && [ -d "$STATE" ] || fail "Firstmate home is incomplete"
for path in "$DATA" "$PROJECTS" "$STATE" "$REGISTRY"; do
  [ ! -L "$path" ] || fail "Firstmate identity path is a symlink"
done
[ -f "$REGISTRY" ] || fail "Firstmate project registry is missing"

PWD_PHYSICAL=$(pwd -P) || fail "working directory cannot be resolved"
contains_symlink "$PWD_PHYSICAL" && fail "working directory contains a symlink"

CURRENT_ROOT=$(git -C "$PWD_PHYSICAL" rev-parse --path-format=absolute --show-toplevel 2>/dev/null) ||
  fail "working directory is not a Git worktree"
CURRENT_ROOT=$(absolute_dir "$CURRENT_ROOT") || fail "Git worktree root cannot be resolved"

# A canonical registered clone is allowed without a task marker. The registry
# and the real Git common directory are both required; neither basename nor
# remote URL is used as identity.
if registered_project "$CURRENT_ROOT"; then
  exec "$AV_VENDOR_CLI" "$@"
fi

TASK_ID=${FM_TASK_ID:-}
case "$TASK_ID" in
  ''|*[!A-Za-z0-9._-]*) fail "isolated copy has no valid Firstmate task identity" ;;
esac
META="$STATE/$TASK_ID.meta"
[ -f "$META" ] || fail "Firstmate task identity is missing"
[ ! -L "$META" ] || fail "Firstmate task metadata is a symlink"
contains_symlink "$META" && fail "Firstmate task metadata contains a symlink"

PROJECT_META_INPUT=$(field project) || fail "Firstmate task metadata has no unique project binding"
WORKTREE_META_INPUT=$(field worktree) || fail "Firstmate task metadata has no unique worktree binding"
KIND_META=$(field kind) || fail "Firstmate task metadata has no unique task kind"
case "$KIND_META" in ship|scout) ;; *) fail "task is not an isolated Firstmate worker" ;; esac
case "$PROJECT_META_INPUT:$WORKTREE_META_INPUT" in
  /*:/*) ;;
  *) fail "Firstmate task paths must be absolute" ;;
esac
[ ! -L "$PROJECT_META_INPUT" ] && [ ! -L "$WORKTREE_META_INPUT" ] || fail "Firstmate task path is a symlink"
contains_symlink "$PROJECT_META_INPUT" && fail "Firstmate project path contains a symlink"
contains_symlink "$WORKTREE_META_INPUT" && fail "Firstmate worktree path contains a symlink"
PROJECT_META=$(absolute_dir "$PROJECT_META_INPUT") || fail "Firstmate project binding is not a directory"
WORKTREE_META=$(absolute_dir "$WORKTREE_META_INPUT") || fail "Firstmate worktree binding is not a directory"
same_path "$PROJECT_META_INPUT" "$PROJECT_META" || fail "Firstmate project path is not physical"
same_path "$WORKTREE_META_INPUT" "$WORKTREE_META" || fail "Firstmate worktree path is not physical"

registered_project "$PROJECT_META" || fail "task project is not a registered canonical clone"
same_path "$CURRENT_ROOT" "$WORKTREE_META" || fail "working directory is not the bound isolated copy"
[ -f "$WORKTREE_META/.git" ] || fail "bound path is not a linked Git worktree"
[ ! -L "$WORKTREE_META/.git" ] || fail "bound Git metadata is a symlink"

WORKTREE_COMMON=$(git -C "$WORKTREE_META" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
  fail "isolated copy has no Git identity"
same_path "$WORKTREE_COMMON" "$REGISTERED_COMMON" ||
  fail "isolated copy is not cryptographically bound to the registered clone"

listed=0
while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      listed_path=${line#worktree }
      [ "$listed_path" = "$WORKTREE_META" ] && listed=1
      ;;
  esac
done < <(git -C "$PROJECT_META" worktree list --porcelain 2>/dev/null)
[ "$listed" -eq 1 ] || fail "isolated copy is not registered by Git"

exec "$AV_VENDOR_CLI" "$@"
