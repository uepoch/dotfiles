#!/usr/bin/env bash
# bootstrap.sh - main entry point for setting up team-dotfiles.
# Usage: ./bootstrap.sh [--migrate-existing] [--name NAME] [--email EMAIL] [profile ...]
#   Profiles: core (default), dev, ops, factory, jj, all
#   Example:  ./bootstrap.sh core dev
#             ./bootstrap.sh --migrate-existing --name "Alice" --email "a@b.com" all
#   Env vars: DOTFILES_USER_NAME, DOTFILES_USER_EMAIL override flags.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# shellcheck source=install/lib/detect_distro.sh
source "$SCRIPT_DIR/install/lib/detect_distro.sh"
# shellcheck source=install/lib/link.sh
source "$SCRIPT_DIR/install/lib/link.sh"

# --- Parse arguments ---
PROFILES=()
_BOOTSTRAP_NAME=""
_BOOTSTRAP_EMAIL=""
_MIGRATE_EXISTING=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      [[ $# -ge 2 ]] || { echo "ERROR: --name requires a value." >&2; exit 2; }
      _BOOTSTRAP_NAME="$2"
      shift 2
      ;;
    --email)
      [[ $# -ge 2 ]] || { echo "ERROR: --email requires a value." >&2; exit 2; }
      _BOOTSTRAP_EMAIL="$2"
      shift 2
      ;;
    --migrate-existing)
      _MIGRATE_EXISTING=true
      shift
      ;;
    --*)
      echo "ERROR: unknown option '$1'." >&2
      exit 2
      ;;
    all)
      PROFILES+=(core dev ops factory jj)
      shift
      ;;
    *)
      PROFILES+=("$1")
      shift
      ;;
  esac
done

if [[ ${#PROFILES[@]} -eq 0 ]]; then
  PROFILES=(core)
fi

# Export so child scripts can read them
export DOTFILES_USER_NAME="${DOTFILES_USER_NAME:-$_BOOTSTRAP_NAME}"
export DOTFILES_USER_EMAIL="${DOTFILES_USER_EMAIL:-$_BOOTSTRAP_EMAIL}"

STOW_PACKAGES=(zsh config)
# Fail before package installation or identity changes if existing files would be
# overwritten. Migration mode only records the exact regular files to back up.
preflight_stow_packages "$_MIGRATE_EXISTING" "${STOW_PACKAGES[@]}"

DISTRO=$(detect_distro)
echo "========================================"
echo "  team-dotfiles bootstrap"
echo "  Distro:  $DISTRO"
echo "  Profiles: ${PROFILES[*]}"
echo "  Migrate existing files: $_MIGRATE_EXISTING"
echo "========================================"

# --- Install profiles ---
for profile in "${PROFILES[@]}"; do
  profile_script="$SCRIPT_DIR/install/profiles/${profile}.sh"
  if [[ -f "$profile_script" ]]; then
    echo ""
    echo "--- Running profile: $profile ---"
    bash "$profile_script"
  else
    echo "ERROR: profile '$profile' not found at $profile_script" >&2
    exit 1
  fi
done

if ! command -v zsh >/dev/null 2>&1; then
  echo "ERROR: zsh is unavailable after profile installation; cannot finish Zsh-only setup." >&2
  exit 1
fi
if ! command -v stow >/dev/null 2>&1; then
  echo "ERROR: GNU Stow is unavailable after profile installation; include the core profile or install Stow." >&2
  exit 1
fi

# --- Stow dotfiles ---
echo ""
echo "--- Linking dotfiles via GNU Stow ---"
if [[ "$_MIGRATE_EXISTING" == true ]]; then
  link_stow_packages --migrate-existing "${STOW_PACKAGES[@]}"
else
  link_stow_packages "${STOW_PACKAGES[@]}"
fi

# --- Change default shell to zsh ---
zsh_path=$(command -v zsh)
if [[ "${SHELL:-}" != "$zsh_path" ]]; then
  if ! command -v chsh >/dev/null 2>&1; then
    echo "ERROR: chsh is unavailable; cannot set zsh as the default shell." >&2
    exit 1
  fi
  echo ""
  echo "Changing default shell to zsh ..."
  chsh -s "$zsh_path"
fi

# --- Post-install message ---
echo ""
echo "========================================"
echo "  Bootstrap complete!"
echo ""
echo "  Next steps:"
echo "    1. Log out and back in (or run: exec zsh)"
echo "    2. For local overrides, edit ~/.zshrc.local"
echo "    3. For Factory Droid, run: ./install/profiles/factory.sh"
echo "========================================"
