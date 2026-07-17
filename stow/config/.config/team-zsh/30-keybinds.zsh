# 30-keybinds.zsh - key bindings.

bindkey -e

typeset -A key
zmodload -F zsh/terminfo p:terminfo 2>/dev/null || true
if (( $+terminfo )); then
  key[Up]="${terminfo[kcuu1]:-}"
  key[Down]="${terminfo[kcud1]:-}"
  key[Home]="${terminfo[khome]:-}"
  key[End]="${terminfo[kend]:-}"
  key[Delete]="${terminfo[kdch1]:-}"
fi

[[ -n "${key[Up]:-}" ]] && bindkey "${key[Up]}" history-search-backward
[[ -n "${key[Down]:-}" ]] && bindkey "${key[Down]}" history-search-forward
[[ -n "${key[Home]:-}" ]] && bindkey "${key[Home]}" beginning-of-line
[[ -n "${key[End]:-}" ]] && bindkey "${key[End]}" end-of-line
[[ -n "${key[Delete]:-}" ]] && bindkey "${key[Delete]}" delete-char

for sequence in '^[[A' '^[OA'; do
  bindkey "$sequence" history-search-backward
done
for sequence in '^[[B' '^[OB'; do
  bindkey "$sequence" history-search-forward
done

for sequence in '^[[H' '^[OH' '^[[1~'; do
  bindkey "$sequence" beginning-of-line
done
for sequence in '^[[F' '^[OF' '^[[4~'; do
  bindkey "$sequence" end-of-line
done
bindkey '^[[3~' delete-char

for sequence in '^[[1;5D' '^[[5D'; do
  bindkey "$sequence" backward-word
done
for sequence in '^[[1;5C' '^[[5C'; do
  bindkey "$sequence" forward-word
done

bindkey '^[[3;5~' kill-word
bindkey '^H' backward-kill-word

bindkey '^[b' backward-word
bindkey '^[f' forward-word

bindkey '^[[Z' reverse-menu-complete
bindkey '^K' kill-line
bindkey '^U' backward-kill-line

unset sequence
