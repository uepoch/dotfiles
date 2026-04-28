#!/usr/bin/env bash
# packages.sh - generic package install helpers.

# install_packages <distro> <pkg1> [pkg2] ...
install_packages() {
  local distro="$1"; shift
  local pkgs=("$@")

  case "$distro" in
    arch)
      if (( $+commands[pacman] )); then
        printf "Installing via pacman: %s\n" "${pkgs[*]}"
        sudo pacman -S --needed --noconfirm "${pkgs[@]}"
      fi
      ;;
    ubuntu|debian)
      if (( $+commands[apt-get] )); then
        printf "Installing via apt: %s\n" "${pkgs[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y "${pkgs[@]}"
      fi
      ;;
    fedora)
      if (( $+commands[dnf] )); then
        printf "Installing via dnf: %s\n" "${pkgs[*]}"
        sudo dnf install -y "${pkgs[@]}"
      fi
      ;;
    rhel)
      if (( $+commands[dnf] )); then
        printf "Installing via dnf: %s\n" "${pkgs[*]}"
        sudo dnf install -y "${pkgs[@]}"
      elif (( $+commands[yum] )); then
        printf "Installing via yum: %s\n" "${pkgs[*]}"
        sudo yum install -y "${pkgs[@]}"
      fi
      ;;
    opensuse)
      if (( $+commands[zypper] )); then
        printf "Installing via zypper: %s\n" "${pkgs[*]}"
        sudo zypper install -y "${pkgs[@]}"
      fi
      ;;
    *)
      echo "WARNING: unsupported distro '$distro'. Please install manually: ${pkgs[*]}"
      ;;
  esac
}
