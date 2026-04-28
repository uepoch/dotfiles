#!/usr/bin/env bash
# dnf.sh - Fedora / RHEL package lists and install.

install_dnf_core() {
  sudo dnf install -y \
    zsh starship fzf ripgrep fd-find bat eza zoxide direnv \
    zsh-autosuggestions zsh-syntax-highlighting \
    neovim tmux git curl wget
  # fd-find ships as fdfind on some Fedora versions
  if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi
}

install_dnf_dev() {
  sudo dnf install -y \
    golang rustup nodejs npm jq just make cmake ninja-build \
    lazygit htop btop uv jujutsu
  if ! command -v bun &>/dev/null; then
    curl -fsSL https://bun.sh/install | bash
  fi
}

install_dnf_ops() {
  sudo dnf install -y \
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
