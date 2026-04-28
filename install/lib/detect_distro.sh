#!/usr/bin/env bash
# detect_distro.sh - identify the running Linux distribution.
# Outputs a single word: arch, ubuntu, debian, fedora, rhel, opensuse, or unknown.

detect_distro() {
  if [[ -f /etc/arch-release ]]; then
    echo "arch"
  elif [[ -f /etc/fedora-release ]]; then
    echo "fedora"
  elif [[ -f /etc/redhat-release ]]; then
    # Could be RHEL, CentOS, Rocky, Alma
    echo "rhel"
  elif [[ -f /etc/debian_version ]]; then
    if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
      echo "ubuntu"
    else
      echo "debian"
    fi
  elif [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "$ID" in
      opensuse*|sles) echo "opensuse" ;;
      *) echo "unknown" ;;
    esac
  else
    echo "unknown"
  fi
}
