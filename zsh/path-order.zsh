# Preserve command precedence within each trust class while ensuring a
# user-writable PATH entry can never shadow a protected executable.
_dotfiles_order_path_safely() {
  local entry
  local -a protected_path user_path

  for entry in "${(@)path}"; do
    # Empty and relative entries resolve through the current working directory.
    # Drop them so changing directories cannot introduce command shadowing.
    if [[ -z "$entry" || "$entry" != /* ]]; then
      continue
    elif [[ -d "$entry" && ! -w "$entry" ]]; then
      protected_path+=("$entry")
    else
      user_path+=("$entry")
    fi
  done

  typeset -gU path PATH
  path=("${(@)protected_path}" "${(@)user_path}")
}

_dotfiles_order_path_safely
unfunction _dotfiles_order_path_safely
