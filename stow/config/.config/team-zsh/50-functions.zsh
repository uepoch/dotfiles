# 50-functions.zsh - shell utility functions.

mkcd() {
  if [[ $# -ne 1 || -z "$1" ]]; then
    print -u2 'usage: mkcd <directory>'
    return 2
  fi

  mkdir -p -- "$1" && cd -- "$1"
}

if (( $+commands[nvim] && $+commands[fzf] )); then
  vf() {
    local selection
    selection=$(fzf) || return
    [[ -n "$selection" ]] && nvim -- "$selection"
  }
fi
