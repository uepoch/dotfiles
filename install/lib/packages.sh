#!/usr/bin/env bash
# packages.sh - generic package install helpers.

require_command() {
  local command_name="$1"
  local purpose="${2:-continue}"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: required command %q is unavailable; cannot %s.\n' \
      "$command_name" "$purpose" >&2
    return 1
  fi
}

# install_packages <distro> <pkg1> [pkg2] ...
install_packages() {
  local distro="$1"; shift
  local pkgs=("$@")

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    return 0
  fi

  require_command sudo "install packages for $distro" || return 1

  case "$distro" in
    arch)
      require_command pacman "install packages for Arch Linux" || return 1
      printf "Installing via pacman: %s\n" "${pkgs[*]}"
      sudo pacman -S --needed --noconfirm "${pkgs[@]}"
      ;;
    ubuntu|debian)
      require_command apt-get "install packages for Debian/Ubuntu" || return 1
      printf "Installing via apt: %s\n" "${pkgs[*]}"
      sudo apt-get update -qq
      sudo apt-get install -y "${pkgs[@]}"
      ;;
    fedora)
      require_command dnf "install packages for Fedora" || return 1
      printf "Installing via dnf: %s\n" "${pkgs[*]}"
      sudo dnf install -y "${pkgs[@]}"
      ;;
    rhel)
      if command -v dnf >/dev/null 2>&1; then
        printf "Installing via dnf: %s\n" "${pkgs[*]}"
        sudo dnf install -y "${pkgs[@]}"
      elif command -v yum >/dev/null 2>&1; then
        printf "Installing via yum: %s\n" "${pkgs[*]}"
        sudo yum install -y "${pkgs[@]}"
      else
        echo "ERROR: neither dnf nor yum is available; cannot install packages for RHEL." >&2
        return 1
      fi
      ;;
    opensuse)
      require_command zypper "install packages for openSUSE" || return 1
      printf "Installing via zypper: %s\n" "${pkgs[*]}"
      sudo zypper install -y "${pkgs[@]}"
      ;;
    *)
      echo "ERROR: unsupported distro '$distro'. Install manually: ${pkgs[*]}" >&2
      return 1
      ;;
  esac
}

# install_aur_packages <pkg1> [pkg2] ...
# Uses the first available helper in deterministic order (yay, then paru).
# AUR helpers must never run as root; sudo invocations are delegated back to
# the non-root account recorded in SUDO_USER.
install_aur_packages() {
  local requested=("$@")
  local missing=()
  local package helper aur_user aur_uid

  if [[ ${#requested[@]} -eq 0 ]]; then
    return 0
  fi

  require_command pacman "check installed Arch packages" || return 1

  for package in "${requested[@]}"; do
    if pacman -Q "$package" >/dev/null 2>&1; then
      printf 'AUR package already installed: %s\n' "$package"
    else
      missing+=("$package")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  if command -v yay >/dev/null 2>&1; then
    helper=yay
  elif command -v paru >/dev/null 2>&1; then
    helper=paru
  else
    echo "ERROR: neither yay nor paru is available; cannot install AUR packages: ${missing[*]}" >&2
    return 1
  fi

  printf 'Installing via %s: %s\n' "$helper" "${missing[*]}"

  if (( EUID == 0 )); then
    aur_user="${SUDO_USER:-}"
    if [[ -z "$aur_user" || "$aur_user" == root ]]; then
      echo "ERROR: refusing to run the AUR helper as root; rerun as a non-root user or through sudo from that user." >&2
      return 1
    fi

    if ! aur_uid=$(id -u "$aur_user" 2>/dev/null) || [[ "$aur_uid" == 0 ]]; then
      echo "ERROR: SUDO_USER '$aur_user' is not a usable non-root account; refusing to run the AUR helper as root." >&2
      return 1
    fi

    require_command sudo "run $helper as $aur_user" || return 1
    sudo -u "$aur_user" -- "$helper" -S --needed --noconfirm "${missing[@]}"
  else
    "$helper" -S --needed --noconfirm "${missing[@]}"
  fi
}
