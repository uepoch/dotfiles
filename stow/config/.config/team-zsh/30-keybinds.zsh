# 30-keybinds.zsh - key bindings.

bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Ctrl+Left / Ctrl+Right — jump by word
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word

# Home / End
bindkey '^[[H'  beginning-of-line
bindkey '^[[F'  end-of-line

# Delete key
bindkey '^[[3~' delete-char

# Ctrl+Backspace / Ctrl+Delete — delete by word
bindkey '^[[3;5~' kill-word
bindkey '^H' backward-kill-word

# Alt+Left / Alt+Right — word jump (tmux / macOS Terminal)
bindkey '^[b' backward-word
bindkey '^[f' forward-word

# Shift+Tab — reverse completion
bindkey '^[[Z' reverse-menu-complete

# Ctrl+K — kill to end of line (already in emacs mode, explicit for clarity)
bindkey '^K' kill-line

# Ctrl+U — kill to beginning of line
bindkey '^U' backward-kill-line
