#!/usr/bin/env bash
# dev.sh - install development toolchain packages.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/install/lib/detect_distro.sh"
source "$REPO_ROOT/install/lib/packages.sh"

distro=$(detect_distro)

echo "=== Installing dev profile on $distro ==="

case "$distro" in
  arch)
    source "$REPO_ROOT/install/distros/pacman.sh"
    install_arch_dev
    ;;
  ubuntu|debian)
    source "$REPO_ROOT/install/distros/apt.sh"
    install_apt_dev
    ;;
  fedora|rhel)
    source "$REPO_ROOT/install/distros/dnf.sh"
    install_dnf_dev
    ;;
  *)
    echo "ERROR: development profile is unsupported on '$distro'." >&2
    exit 1
    ;;
esac

# Initialize rustup if just installed
if command -v rustup >/dev/null 2>&1 && [[ ! -d "$HOME/.rustup" ]]; then
  echo "Initializing rustup stable toolchain ..."
  rustup default stable
fi

# Initialize asdf nodejs plugin if asdf is available
if command -v asdf >/dev/null 2>&1; then
  asdf plugin add nodejs 2>/dev/null || true
  # Read versions from the Stow source; bootstrap links this file into HOME later.
  if [[ -f "$REPO_ROOT/stow/config/.tool-versions" ]]; then
    (cd "$REPO_ROOT/stow/config" && asdf install) 2>/dev/null || true
  fi
fi

echo "=== Dev profile done ==="
