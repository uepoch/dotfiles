# .zprofile - login-shell init. PATH bootstrap goes here so it is set once per login.

typeset -U path PATH

# Prepend user-local bins if present
for dir in \
  "$HOME/.local/bin" \
  "$HOME/.cargo/bin" \
  "$HOME/go/bin" \
  "$HOME/.bun/bin"; do
  [[ -d "$dir" ]] && path=("$dir" $path)
done

# asdf shims (works for asdf >= 0.16 binary install)
if [[ -d "${ASDF_DATA_DIR:-$HOME/.asdf}/shims" ]]; then
  path=("${ASDF_DATA_DIR:-$HOME/.asdf}/shims" $path)
fi

export PATH
