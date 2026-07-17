#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v zsh >/dev/null 2>&1 || fail "zsh is required"
command -v shellcheck >/dev/null 2>&1 || fail "shellcheck is required"
command -v stow >/dev/null 2>&1 || fail "GNU Stow is required"

bash_files=(
  bootstrap.sh
  install/lib/*.sh
  install/profiles/*.sh
  install/distros/*.sh
  tests/*_test.sh
  scripts/check.sh
)
zsh_files=(
  stow/zsh/.zshenv
  stow/zsh/.zprofile
  stow/zsh/.zshrc
  stow/config/.config/team-zsh/*.zsh
  tests/check-zsh.zsh
)

for file in "${bash_files[@]}"; do
  bash -n "$file"
done
for file in "${zsh_files[@]}"; do
  zsh -n "$file"
done

shellcheck --external-sources --exclude=SC1091,SC2016 "${bash_files[@]}"

bash tests/packages_test.sh
bash tests/link_test.sh
bash tests/jj_profile_test.sh
bash tests/factory_profile_test.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  --start-directory tests \
  --pattern 'test_*.py'
TEAM_DOTFILES_ROOT="$REPO_ROOT" TERM=xterm-256color \
  zsh -f -i -c 'source "$TEAM_DOTFILES_ROOT/tests/check-zsh.zsh"'

temporary_home=$(mktemp -d)
trap 'rm -rf "$temporary_home"' EXIT
stow --simulate \
  --dir="$REPO_ROOT/stow" \
  --target="$temporary_home" \
  --no-folding \
  -R zsh config

git diff --check
echo "check.sh: PASS"
