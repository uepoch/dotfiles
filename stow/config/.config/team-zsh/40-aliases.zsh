# 40-aliases.zsh - curated team aliases.
# Only enabled when the underlying tool is actually installed.

# --- eza (ls replacement) ---
alias_cmd eza \
  'ls=eza --icons --group-directories-first' \
  'll=eza -lah --icons --group-directories-first' \
  'la=eza -la --icons --group-directories-first' \
  'tree=eza --tree --icons'

# --- bat (cat replacement) ---
alias_cmd bat 'cat=bat'

# --- ripgrep / fd ---
alias_cmd rg 'grep=rg'
alias_cmd fd 'find=fd'

# --- editor shortcuts ---
alias_cmd nvim \
  'v=nvim' \
  'vim=nvim' \
  'vz=nvim ~/.zshrc.local'
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
alias_cmd podman \
  'p=podman' \
  'pc=podman compose'
alias_cmd docker 'd=docker'

# --- jujutsu (jj) ---
alias_cmd jj \
  'jl=jj log' \
  'js=jj status' \
  'jd=jj diff'

# --- zellij ---
alias_cmd zellij \
  'zl=zellij list-sessions' \
  'za=zellij attach'

# --- Arch Linux packages ---
alias_cmd pacman \
  'pacup=sudo pacman -Syu' \
  'pacin=sudo pacman -S' \
  'pacs=pacman -Ss' \
  'pacq=pacman -Qs' \
  'pacrm=sudo pacman -Rns'

# --- agent CLIs ---
alias_cmd opencode 'oc=opencode -c'
alias_cmd droid 'dc=droid --resume'
alias_cmd try-rs 'try=try-rs'
