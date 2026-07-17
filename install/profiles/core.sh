#!/usr/bin/env bash
# core.sh - install core shell-UX packages for any distro.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../lib/detect_distro.sh
source "$REPO_ROOT/install/lib/detect_distro.sh"
# shellcheck source=../lib/packages.sh
source "$REPO_ROOT/install/lib/packages.sh"

distro=$(detect_distro)

CORE_PACKAGES=(
  zsh
  starship
  fzf
  ripgrep
  fd-find
  bat
  eza
  zoxide
  direnv
  atuin
  neovim
  tmux
  git
  curl
  wget
  stow
)

echo "=== Installing core profile on $distro ==="

case "$distro" in
  arch)
    source "$REPO_ROOT/install/distros/pacman.sh"
    install_arch_core
    ;;
  ubuntu|debian)
    source "$REPO_ROOT/install/distros/apt.sh"
    install_apt_core
    ;;
  fedora|rhel)
    source "$REPO_ROOT/install/distros/dnf.sh"
    install_dnf_core
    ;;
  *)
    install_packages "$distro" "${CORE_PACKAGES[@]}"
    ;;
esac

# Report unexpected plugin layouts after package installation.
if [[ ! -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  echo "WARNING: zsh-autosuggestions was installed but not found at the expected path."
fi
if [[ ! -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  echo "WARNING: zsh-syntax-highlighting was installed but not found at the expected path."
fi

echo "=== Core profile done ==="
