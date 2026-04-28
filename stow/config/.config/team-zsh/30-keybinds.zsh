# 30-keybinds.zsh - key bindings.

bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Ctrl+Left / Ctrl+Right — jump by word
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word

# Ctrl+Backspace / Ctrl+Delete — delete by word
bindkey '^[[3;5~' kill-word
bindkey '^H' backward-kill-word
