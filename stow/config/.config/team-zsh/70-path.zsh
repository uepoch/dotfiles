# 70-path.zsh - runtime PATH additions for interactive shells.
# Login-shell PATH is set in .zprofile; this file only adds entries
# that need to be present even in non-login interactive sessions.

typeset -U path PATH

# Re-ensure user-local bins (in case .zprofile was skipped)
for dir in \
  "$HOME/.local/bin" \
  "$HOME/.cargo/bin" \
  "$HOME/go/bin" \
  "$HOME/.bun/bin"; do
  [[ -d "$dir" ]] && path=("$dir" $path)
done

export PATH
