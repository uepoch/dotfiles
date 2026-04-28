#!/usr/bin/env bash
# link.sh - GNU Stow helper for symlinking dotfiles into $HOME.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

link_stow_packages() {
  local packages=("$@")
  local stow_dir="$REPO_ROOT/stow"

  if ! command -v stow &>/dev/null; then
    echo "ERROR: GNU Stow is not installed. Install it first."
    return 1
  fi

  for pkg in "${packages[@]}"; do
    if [[ -d "$stow_dir/$pkg" ]]; then
      printf "Stowing '%s' ...\n" "$pkg"
      stow --dir="$stow_dir" --target="$HOME" --no-folding --verbose=1 -R "$pkg" 2>&1 || {
        echo "WARNING: stow $pkg had conflicts. Check above."
      }
    else
      echo "WARNING: stow package '$pkg' not found in $stow_dir"
    fi
  done
}

backup_and_link() {
  local target="$1"
  if [[ -e "$target" && ! -L "$target" ]]; then
    printf "Backing up existing file: %s -> %s.bak\n" "$target" "$target"
    mv "$target" "$target.bak"
  fi
}
