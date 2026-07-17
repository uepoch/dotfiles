# 05-path.zsh - runtime PATH additions for interactive shells.
# Login-shell PATH is set in .zprofile; this file only adds entries
# that need to be present even in non-login interactive sessions.

typeset -U path PATH

export PNPM_HOME="${PNPM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/pnpm}"

# Re-ensure user-local bins (in case .zprofile was skipped)
for dir in \
  "$HOME/.local/bin" \
  "$HOME/.cargo/bin" \
  "$HOME/go/bin" \
  "$HOME/.bun/bin" \
  "$HOME/.grok/bin" \
  "$PNPM_HOME"; do
  [[ -d "$dir" ]] && path=("$dir" $path)
done

_asdf_shims="${ASDF_DATA_DIR:-$HOME/.asdf}/shims"
[[ -d "$_asdf_shims" ]] && path=("$_asdf_shims" $path)

export PATH
unset dir _asdf_shims
