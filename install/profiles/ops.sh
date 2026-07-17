#!/usr/bin/env bash
# ops.sh - install containers/network/ops packages.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/install/lib/detect_distro.sh"
source "$REPO_ROOT/install/lib/packages.sh"

distro=$(detect_distro)

echo "=== Installing ops profile on $distro ==="

case "$distro" in
  arch)
    source "$REPO_ROOT/install/distros/pacman.sh"
    install_arch_ops
    ;;
  ubuntu|debian)
    source "$REPO_ROOT/install/distros/apt.sh"
    install_apt_ops
    ;;
  fedora|rhel)
    source "$REPO_ROOT/install/distros/dnf.sh"
    install_dnf_ops
    ;;
  *)
    echo "ERROR: ops profile is unsupported on '$distro'." >&2
    exit 1
    ;;
esac

echo "=== Ops profile done ==="
