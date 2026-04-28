# .zshenv - sourced for every zsh invocation. Keep minimal and side-effect free.

# XDG base directories
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Where modular team-zsh fragments live
export TEAM_ZSH_DIR="${TEAM_ZSH_DIR:-$XDG_CONFIG_HOME/team-zsh}"

# zsh's own dotfile location (kept at $HOME for compatibility with most distros)
export ZDOTDIR="${ZDOTDIR:-$HOME}"
