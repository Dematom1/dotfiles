# Preserve command precedence within each trust class while ensuring a
# user-writable PATH entry can never shadow a protected executable.
_dotfiles_order_path_safely() {
  local entry ancestor
  local -a protected_path user_path
  local -i is_protected

  for entry in "${(@)path}"; do
    # Empty and relative entries resolve through the current working directory.
    # Drop them so changing directories cannot introduce command shadowing.
    if [[ -z "$entry" || "$entry" != /* ]]; then
      continue
    elif [[ -d "$entry" ]]; then
      is_protected=1
      ancestor="$entry"
      while true; do
        if [[ -w "$ancestor" ]]; then
          is_protected=0
          break
        fi
        [[ "$ancestor" == / ]] && break
        ancestor="${ancestor:h}"
      done

      if (( is_protected )); then
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
unfunction _dotfiles_order_path_safely
