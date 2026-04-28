#!/usr/bin/env bash
# apt.sh - Debian/Ubuntu package lists and install.

install_apt_core() {
  sudo apt-get update -qq
  sudo apt-get install -y \
    zsh starship fzf ripgrep fd-find bat eza zoxide direnv \
    zsh-autosuggestions zsh-syntax-highlighting \
    neovim tmux git curl wget
  # fd-find ships as fdfind on Debian/Ubuntu; create alias
  if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi
  # bat ships as batcat on older Ubuntu; create alias
  if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
  fi
}

install_apt_dev() {
  sudo apt-get install -y \
    golang-go rustup nodejs npm jq just make cmake ninja-build \
    lazygit htop btop uv jujutsu
  # bun is not in apt; install via curl
  if ! command -v bun &>/dev/null; then
    curl -fsSL https://bun.sh/install | bash
  fi
}

install_apt_ops() {
  sudo apt-get install -y \
    podman podman-compose buildah skopeo \
    openssh-client mosh autossh \
    tcpdump lsof strace iputils-ping \
    rsync
}

install_apt_all() {
  install_apt_core
  install_apt_dev
  install_apt_ops
}
