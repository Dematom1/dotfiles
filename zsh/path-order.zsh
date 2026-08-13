# Preserve command precedence within each trust class while ensuring a
# user-writable PATH entry can never shadow a protected executable.
_dotfiles_path_chain_is_protected() {
  local ancestor=$1

  while true; do
    [[ -w "$ancestor" ]] && return 1
    [[ "$ancestor" == / ]] && return 0
    ancestor="${ancestor:h}"
  done
}

_dotfiles_order_path_safely() {
  local entry physical
  local -a protected_path user_path

  for entry in "${(@)path}"; do
    # Empty and relative entries resolve through the current working directory.
    # Drop them so changing directories cannot introduce command shadowing.
    if [[ -z "$entry" || "$entry" != /* ]]; then
      continue
    elif [[ -d "$entry" ]]; then
      physical=$(cd -q -- "$entry" && pwd -P) || physical=""
      # Both spellings matter: the physical target may be replaceable, and a
      # symlink with a protected target may itself sit below a writable parent.
      if [[ -n "$physical" ]] \
        && _dotfiles_path_chain_is_protected "$entry" \
        && _dotfiles_path_chain_is_protected "$physical"; then
        protected_path+=("$entry")
      else
        user_path+=("$entry")
      fi
    else
      user_path+=("$entry")
    fi
  done

  typeset -gU path PATH
  path=("${(@)protected_path}" "${(@)user_path}")
}

_dotfiles_order_path_safely
unfunction _dotfiles_order_path_safely _dotfiles_path_chain_is_protected
