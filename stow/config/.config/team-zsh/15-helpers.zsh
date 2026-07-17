# 15-helpers.zsh - reusable helpers for later shell modules.

alias_cmd() {
  if (( $# < 2 )); then
    print -u2 'usage: alias_cmd <command> <alias=expansion> [...]'
    return 2
  fi

  local command_name="$1"
  local alias_spec alias_name alias_expansion
  shift

  if [[ ! "$command_name" =~ '^[A-Za-z0-9_.+-]+$' ]]; then
    print -u2 "alias_cmd: invalid command: ${(qqq)command_name}"
    return 2
  fi

  for alias_spec in "$@"; do
    if [[ "$alias_spec" != *=* ]]; then
      print -u2 "alias_cmd: expected alias=expansion: ${(qqq)alias_spec}"
      return 2
    fi

    alias_name="${alias_spec%%=*}"
    alias_expansion="${alias_spec#*=}"
    if [[ ! "$alias_name" =~ '^[A-Za-z_][A-Za-z0-9_.+-]*$' ||
      -z "$alias_expansion" ]]; then
      print -u2 "alias_cmd: invalid alias definition: ${(qqq)alias_spec}"
      return 2
    fi
  done

  (( $+commands[$command_name] )) || return 0

  for alias_spec in "$@"; do
    alias -- "$alias_spec"
  done
}
