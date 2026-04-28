# 60-tools.zsh - third-party tool init hooks (guarded by availability).

# starship prompt
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi

# zoxide (z command)
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi

# direnv
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
fi

# atuin (enhanced history)
if (( $+commands[atuin] )); then
  eval "$(atuin init zsh)"
fi

# try-rs (sandbox helper)
_try_rs_zsh="${XDG_CONFIG_HOME:-$HOME/.config}/try-rs/try-rs.zsh"
[[ -f "$_try_rs_zsh" ]] && source "$_try_rs_zsh"
unset _try_rs_zsh
