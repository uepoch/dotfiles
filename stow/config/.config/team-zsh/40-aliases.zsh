# 40-aliases.zsh - curated team aliases.
# Only enabled when the underlying tool is actually installed.

# --- eza (ls replacement) ---
if (( $+commands[eza] )); then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -lah --icons --group-directories-first'
  alias la='eza -la --icons --group-directories-first'
  alias tree='eza --tree --icons'
fi

# --- bat (cat replacement) ---
if (( $+commands[bat] )); then
  alias cat='bat'
fi

# --- ripgrep / fd ---
if (( $+commands[rg] )); then
  alias grep='rg'
fi
if (( $+commands[fd] )); then
  alias find='fd'
fi

# --- editor shortcuts ---
if (( $+commands[nvim] )); then
  alias v='nvim'
  alias vf='nvim $(fzf)'
  alias vz='nvim ~/.zshrc && source ~/.zshrc'
fi
alias c='clear'
alias ..='cd ..'
alias ...='cd ../..'

# --- git ---
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate --all'

# --- containers (podman preferred, docker optional) ---
if (( $+commands[podman] )); then
  alias p='podman'
  alias pc='podman compose'
fi
if (( $+commands[docker] )); then
  alias d='docker'
fi
