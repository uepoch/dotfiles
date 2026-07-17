#!/usr/bin/env bash
# pacman.sh - Arch Linux package lists and install.

install_arch_core() {
  install_packages arch \
    zsh starship fzf ripgrep fd bat eza zoxide direnv atuin \
    zsh-autosuggestions zsh-syntax-highlighting \
    neovim tmux git curl wget stow
}

install_arch_dev() {
  install_packages arch \
    go rustup bun asdf-vm nodejs npm jq just make cmake ninja \
    lazygit htop btop uv jujutsu
}

install_arch_ops() {
  install_packages arch \
    podman podman-compose buildah skopeo \
    openssh mosh autossh \
    tcpdump lsof strace iputils \
    rsync
}

install_arch_all() {
  install_arch_core
  install_arch_dev
  install_arch_ops
}
