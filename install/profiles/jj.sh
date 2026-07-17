#!/usr/bin/env bash
# jj.sh - install Jujutsu and configure identity for git + jj.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/install/lib/detect_distro.sh"
source "$REPO_ROOT/install/lib/packages.sh"

distro=$(detect_distro)

require_command git "configure Git and Jujutsu identity" || exit 1

# Resolve identity before installing so unattended runs never stop for a prompt.
_identity_name="${DOTFILES_USER_NAME:-}"
_identity_email="${DOTFILES_USER_EMAIL:-}"
_identity_args=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      [[ $# -ge 2 ]] || { echo "ERROR: --name requires a value." >&2; exit 2; }
      _identity_name="$2"
      shift 2
      ;;
    --email)
      [[ $# -ge 2 ]] || { echo "ERROR: --email requires a value." >&2; exit 2; }
      _identity_email="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done

if [[ -z "$_identity_name" ]] && command -v git >/dev/null 2>&1; then
  _identity_name=$(git config --global user.name 2>/dev/null || true)
fi
if [[ -z "$_identity_email" ]] && command -v git >/dev/null 2>&1; then
  _identity_email=$(git config --global user.email 2>/dev/null || true)
fi

if [[ ( -z "$_identity_name" || -z "$_identity_email" ) && ! -t 0 ]]; then
  echo "ERROR: jj identity is incomplete and no interactive terminal is available." >&2
  echo "Provide --name/--email, set DOTFILES_USER_NAME/DOTFILES_USER_EMAIL, or configure git user.name/user.email." >&2
  exit 1
fi

export DOTFILES_USER_NAME="$_identity_name"
export DOTFILES_USER_EMAIL="$_identity_email"

echo "=== Installing Jujutsu (jj) on $distro ==="

case "$distro" in
  arch)
    install_packages arch jujutsu
    ;;
  ubuntu|debian|fedora|rhel)
    if ! command -v jj >/dev/null 2>&1; then
      echo "Installing jujutsu via cargo ..."
      require_command cargo "install Jujutsu" || exit 1
      cargo install --locked jj-cli
    else
      echo "jj already installed."
    fi
    ;;
  *)
    echo "Installing jujutsu via cargo ..."
    require_command cargo "install Jujutsu" || exit 1
    cargo install --locked jj-cli
    ;;
esac

# Configure identity for both git and jj.
source "$REPO_ROOT/install/lib/setup-identity.sh" "${_identity_args[@]}"

unset _identity_name _identity_email _identity_args

echo "=== Jujutsu setup done ==="
