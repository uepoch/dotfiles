#!/usr/bin/env bash
# jj.sh - install Jujutsu and configure identity for git + jj.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/install/lib/detect_distro.sh"
source "$REPO_ROOT/install/lib/packages.sh"

distro=$(detect_distro)

echo "=== Installing Jujutsu (jj) on $distro ==="

case "$distro" in
  arch)
    source "$REPO_ROOT/install/distros/pacman.sh"
    sudo pacman -S --needed --noconfirm jujutsu
    ;;
  ubuntu|debian)
    source "$REPO_ROOT/install/distros/apt.sh"
    if ! command -v jj &>/dev/null; then
      echo "Installing jujutsu via cargo (not yet in apt for most releases) ..."
      if command -v cargo &>/dev/null; then
        cargo install --locked jj-cli
      else
        echo "ERROR: cargo not found. Install rustup first: ./install/profiles/dev.sh"
        exit 1
      fi
    else
      echo "jj already installed."
    fi
    ;;
  fedora|rhel)
    source "$REPO_ROOT/install/distros/dnf.sh"
    if ! command -v jj &>/dev/null; then
      echo "Installing jujutsu via cargo ..."
      if command -v cargo &>/dev/null; then
        cargo install --locked jj-cli
      else
        echo "ERROR: cargo not found. Install rustup first: ./install/profiles/dev.sh"
        exit 1
      fi
    else
      echo "jj already installed."
    fi
    ;;
  *)
    echo "Installing jujutsu via cargo ..."
    cargo install --locked jj-cli
    ;;
esac

# Configure identity for both git and jj
source "$REPO_ROOT/install/lib/setup-identity.sh" "$@"

echo "=== Jujutsu setup done ==="
