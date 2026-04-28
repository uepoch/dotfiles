# .zshrc - interactive shell entrypoint.
# This file deliberately stays small: it just sources modular fragments
# from $TEAM_ZSH_DIR (default: ~/.config/team-zsh).

: "${TEAM_ZSH_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/team-zsh}"

if [[ -d "$TEAM_ZSH_DIR" ]]; then
  for f in "$TEAM_ZSH_DIR"/*.zsh(N); do
    source "$f"
  done
fi

# Per-user / per-machine overrides (ignored by git when placed in 90-local.zsh)
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
