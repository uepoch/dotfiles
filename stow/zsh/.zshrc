# .zshrc - interactive shell entrypoint.
# This file deliberately stays small: it just sources modular fragments
# from $TEAM_ZSH_DIR (default: ~/.config/team-zsh).

: "${TEAM_ZSH_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/team-zsh}"

# Private proxy credentials are generated outside the repository. Refuse to
# source a file that is accessible to the user's group or to other users.
_team_proxy_env="${XDG_CONFIG_HOME:-$HOME/.config}/team-dotfiles/proxy.env"
if [[ -f "$_team_proxy_env" && -r "$_team_proxy_env" ]]; then
  zmodload -F zsh/stat b:zstat 2>/dev/null
  typeset -a _team_proxy_stat
  if (( $+builtins[zstat] )) &&
    zstat -A _team_proxy_stat +mode -- "$_team_proxy_env" 2>/dev/null; then
    if (( (_team_proxy_stat[1] & 8#77) == 0 )); then
      source "$_team_proxy_env"
    else
      print -u2 -- "warning: skipping unsafe proxy environment file: $_team_proxy_env"
    fi
  else
    print -u2 -- "warning: unable to verify proxy environment permissions: $_team_proxy_env"
  fi
  unset _team_proxy_stat
fi
unset _team_proxy_env

if [[ -d "$TEAM_ZSH_DIR" ]]; then
  for _team_zsh_file in "$TEAM_ZSH_DIR"/*.zsh(N); do
    [[ "${_team_zsh_file:t}" == 90-local.zsh ||
      "${_team_zsh_file:t}" == 99-syntax-highlighting.zsh ]] && continue
    source "$_team_zsh_file"
  done
fi

# Per-user / per-machine overrides.
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Retire legacy aliases when the shared composable wrappers are available.
(( $+functions[claudex] )) && unalias claudex 2>/dev/null
(( $+functions[claudez] )) && unalias claudez 2>/dev/null

# Syntax highlighting must be sourced after all widgets and local overrides.
[[ -f "$TEAM_ZSH_DIR/99-syntax-highlighting.zsh" ]] &&
  source "$TEAM_ZSH_DIR/99-syntax-highlighting.zsh"

unset _team_zsh_file
