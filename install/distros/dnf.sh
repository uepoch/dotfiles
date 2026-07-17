#!/usr/bin/env bash
# dnf.sh - Fedora / RHEL package lists and install.
# shellcheck disable=SC2154

install_dnf_core() {
  install_packages "$distro" \
    zsh starship fzf ripgrep fd-find bat eza zoxide direnv \
    zsh-autosuggestions zsh-syntax-highlighting \
    neovim tmux git curl wget stow
  # fd-find ships as fdfind on some Fedora versions
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi
}

install_dnf_dev() {
  install_packages "$distro" \
    golang rustup nodejs npm jq just make cmake ninja-build \
    lazygit htop btop uv jujutsu
  if ! command -v bun >/dev/null 2>&1; then
    require_command curl "install bun" || return 1
    curl -fsSL https://bun.sh/install | bash
  fi
}

install_dnf_ops() {
  install_packages "$distro" \
    podman podman-compose buildah skopeo \
    openssh-clients mosh autossh \
    tcpdump lsof strace iputils \
    rsync
}

install_dnf_all() {
  install_dnf_core
  install_dnf_dev
  install_dnf_ops
}
