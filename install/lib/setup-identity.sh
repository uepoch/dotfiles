#!/usr/bin/env bash
# setup-identity.sh - configure git and jj user identity.
#
# Reads name/email from (priority order):
#   1. DOTFILES_USER_NAME / DOTFILES_USER_EMAIL env vars
#   2. --name / --email arguments
#   3. Interactive prompt
#
# Then writes to:
#   - git config --global user.name / user.email
#   - ~/.jjconfig.toml [user] table

set -euo pipefail

_IDENTITY_NAME=""
_IDENTITY_EMAIL=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)   _IDENTITY_NAME="$2";  shift 2 ;;
    --email)  _IDENTITY_EMAIL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Env vars override args
if [[ -n "${DOTFILES_USER_NAME:-}" ]];  then _IDENTITY_NAME="$DOTFILES_USER_NAME"; fi
if [[ -n "${DOTFILES_USER_EMAIL:-}" ]]; then _IDENTITY_EMAIL="$DOTFILES_USER_EMAIL"; fi

# Interactive prompt if still empty
if [[ -z "$_IDENTITY_NAME" ]]; then
  _existing_git_name=$(git config --global user.name 2>/dev/null || true)
  if [[ -n "$_existing_git_name" ]]; then
    _IDENTITY_NAME="$_existing_git_name"
    echo "Using existing git user.name: $_IDENTITY_NAME"
  else
    read -rp "Enter your name for git/jj: " _IDENTITY_NAME
  fi
fi

if [[ -z "$_IDENTITY_EMAIL" ]]; then
  _existing_git_email=$(git config --global user.email 2>/dev/null || true)
  if [[ -n "$_existing_git_email" ]]; then
    _IDENTITY_EMAIL="$_existing_git_email"
    echo "Using existing git user.email: $_IDENTITY_EMAIL"
  else
    read -rp "Enter your email for git/jj: " _IDENTITY_EMAIL
  fi
fi

# --- Git config ---
_existing_name=$(git config --global user.name 2>/dev/null || true)
_existing_email=$(git config --global user.email 2>/dev/null || true)

if [[ -z "$_existing_name" ]]; then
  git config --global user.name "$_IDENTITY_NAME"
  echo "Set git user.name = $_IDENTITY_NAME"
else
  echo "git user.name already set: $_existing_name (skipping)"
fi

if [[ -z "$_existing_email" ]]; then
  git config --global user.email "$_IDENTITY_EMAIL"
  echo "Set git user.email = $_IDENTITY_EMAIL"
else
  echo "git user.email already set: $_existing_email (skipping)"
fi

# --- jj config ---
_JJCONFIG="$HOME/.jjconfig.toml"

if command -v jj &>/dev/null; then
  _jj_name=""
  _jj_email=""
  if [[ -f "$_JJCONFIG" ]]; then
    _jj_name=$(grep -E '^\s*name\s*=' "$_JJCONFIG" 2>/dev/null | head -1 | sed -E 's/.*=\s*"?([^"]*)"?.*/\1/' || true)
    _jj_email=$(grep -E '^\s*email\s*=' "$_JJCONFIG" 2>/dev/null | head -1 | sed -E 's/.*=\s*"?([^"]*)"?.*/\1/' || true)
  fi

  if [[ -z "$_jj_name" || -z "$_jj_email" ]]; then
    # Build [user] section
    if [[ ! -f "$_JJCONFIG" ]] || ! grep -q '^\[user\]' "$_JJCONFIG"; then
      printf '\n[user]\n' >> "$_JJCONFIG"
    fi
    if [[ -z "$_jj_name" ]]; then
      printf 'name = "%s"\n' "$_IDENTITY_NAME" >> "$_JJCONFIG"
      echo "Set jj user.name = $_IDENTITY_NAME"
    fi
    if [[ -z "$_jj_email" ]]; then
      printf 'email = "%s"\n' "$_IDENTITY_EMAIL" >> "$_JJCONFIG"
      echo "Set jj user.email = $_IDENTITY_EMAIL"
    fi
  else
    echo "jj [user] already configured (name=$_jj_name, email=$_jj_email) (skipping)"
  fi
else
  echo "jj not installed yet; skipping jjconfig. Re-run after installing jj."
fi

unset _IDENTITY_NAME _IDENTITY_EMAIL _existing_git_name _existing_git_email
unset _existing_name _existing_email _JJCONFIG _jj_name _jj_email
