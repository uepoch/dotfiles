# 80-plugins.zsh - interactive integrations loaded before local overrides.

if (( $+commands[fzf] )); then
  if fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  else
    for _fzf_key in \
      /usr/share/fzf/key-bindings.zsh \
      /usr/share/fzf/shell/key-bindings.zsh \
      /usr/share/doc/fzf/examples/key-bindings.zsh; do
      if [[ -r "$_fzf_key" ]]; then
        source "$_fzf_key"
        break
      fi
    done
    for _fzf_comp in \
      /usr/share/fzf/completion.zsh \
      /usr/share/fzf/shell/completion.zsh \
      /usr/share/doc/fzf/examples/completion.zsh; do
      if [[ -r "$_fzf_comp" ]]; then
        source "$_fzf_comp"
        break
      fi
    done
    unset _fzf_key _fzf_comp
  fi
fi

for _zsh_autosug in \
  /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/share/zsh/plugins/zsh-autosuggestions.zsh; do
  if [[ -r "$_zsh_autosug" ]]; then
    source "$_zsh_autosug"
    break
  fi
done
unset _zsh_autosug

if (( $+commands[atuin] )); then
  eval "$(atuin init zsh --disable-up-arrow)"
fi

[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"
