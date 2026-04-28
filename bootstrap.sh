#!/usr/bin/env bash
# bootstrap.sh - main entry point for setting up team-dotfiles.
# Usage: ./bootstrap.sh [--name NAME] [--email EMAIL] [profile ...]
#   Profiles: core (default), dev, ops, factory, jj, all
#   Example:  ./bootstrap.sh core dev
#             ./bootstrap.sh --name "Alice" --email "a@b.com" all
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)   _BOOTSTRAP_NAME="$2"; shift 2 ;;
    --email)  _BOOTSTRAP_EMAIL="$2"; shift 2 ;;
    all)      PROFILES+=(core dev ops factory jj); shift ;;
    *)        PROFILES+=("$1"); shift ;;
  esac
done

if [[ ${#PROFILES[@]} -eq 0 ]]; then
  PROFILES=(core)
fi

# Export so child scripts can read them
export DOTFILES_USER_NAME="${DOTFILES_USER_NAME:-$_BOOTSTRAP_NAME}"
export DOTFILES_USER_EMAIL="${DOTFILES_USER_EMAIL:-$_BOOTSTRAP_EMAIL}"

DISTRO=$(detect_distro)
echo "========================================"
echo "  team-dotfiles bootstrap"
echo "  Distro:  $DISTRO"
echo "  Profiles: ${PROFILES[*]}"
echo "========================================"

# --- Install profiles ---
for profile in "${PROFILES[@]}"; do
  profile_script="$SCRIPT_DIR/install/profiles/${profile}.sh"
  if [[ -f "$profile_script" ]]; then
    echo ""
    echo "--- Running profile: $profile ---"
    bash "$profile_script"
  else
    echo "WARNING: profile '$profile' not found at $profile_script"
  fi
done

# --- Stow dotfiles ---
echo ""
echo "--- Linking dotfiles via GNU Stow ---"
STOW_PACKAGES=(zsh config)
link_stow_packages "${STOW_PACKAGES[@]}"

# --- Copy .tool-versions if available ---
if [[ -f "$SCRIPT_DIR/stow/config/.tool-versions" ]]; then
  cp -n "$SCRIPT_DIR/stow/config/.tool-versions" "$HOME/.tool-versions" 2>/dev/null || true
  echo "Copied .tool-versions (skipped if already present)."
fi

# --- Change default shell to zsh ---
if [[ "$SHELL" != "$(command -v zsh)" ]]; then
  echo ""
  echo "Changing default shell to zsh ..."
  chsh -s "$(command -v zsh)"
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
