# 99-syntax-highlighting.zsh - sourced explicitly after local overrides.

for _zsh_syntax in \
  /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/share/zsh/plugins/zsh-syntax-highlighting.zsh; do
  if [[ -r "$_zsh_syntax" ]]; then
    source "$_zsh_syntax"
    break
  fi
done
unset _zsh_syntax
