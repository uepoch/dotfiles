#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../install/lib/packages.sh
source "$REPO_ROOT/install/lib/packages.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_fake() {
  local path="$1"
  local body="$2"
  cat > "$path" <<SCRIPT
#!/bin/bash
$body
SCRIPT
  chmod +x "$path"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
mkdir -p "$fake_bin"

make_fake "$fake_bin/sudo" 'printf "%s\\n" "$*" >> "$COMMAND_LOG"; "$@"'
make_fake "$fake_bin/pacman" 'printf "pacman:%s\\n" "$*" >> "$COMMAND_LOG"'
export COMMAND_LOG="$tmp/commands.log"

PATH="$fake_bin:/usr/bin:/bin" install_packages arch fzf stow
[[ -s "$COMMAND_LOG" ]] || fail "Arch install did not invoke the fake package manager"
grep -q 'pacman -S --needed --noconfirm fzf stow' "$COMMAND_LOG" || \
  fail "Arch install used unexpected arguments"

# The approved core + ops + jj combination must include all unattended Arch dependencies.
# shellcheck source=../install/distros/pacman.sh
source "$REPO_ROOT/install/distros/pacman.sh"
: > "$COMMAND_LOG"
PATH="$fake_bin:/usr/bin:/bin" install_arch_core
PATH="$fake_bin:/usr/bin:/bin" install_arch_ops
PATH="$fake_bin:/usr/bin:/bin" install_packages arch jujutsu
grep -q 'fzf' "$COMMAND_LOG" || fail "Arch core omitted fzf"
grep -q 'zsh-autosuggestions' "$COMMAND_LOG" || fail "Arch core omitted zsh-autosuggestions"
grep -q 'zsh-syntax-highlighting' "$COMMAND_LOG" || fail "Arch core omitted zsh-syntax-highlighting"
grep -q 'stow' "$COMMAND_LOG" || fail "Arch core omitted Stow"
grep -q 'podman podman-compose' "$COMMAND_LOG" || fail "Arch ops omitted Podman or podman-compose"
grep -q 'jujutsu' "$COMMAND_LOG" || fail "Arch jj omitted Jujutsu"

missing_bin="$tmp/missing-bin"
mkdir -p "$missing_bin"
make_fake "$missing_bin/sudo" 'exit 99'
if output=$(PATH="$missing_bin" install_packages arch fzf 2>&1); then
  fail "Arch install succeeded without pacman"
fi
[[ "$output" == *"required command pacman is unavailable"* ]] || \
  fail "Missing pacman error was not clear: $output"

if output=$(PATH="$fake_bin:/usr/bin:/bin" install_packages unknown fzf 2>&1); then
  fail "Unsupported distro unexpectedly succeeded"
fi
[[ "$output" == *"unsupported distro 'unknown'"* ]] || \
  fail "Unsupported distro error was not clear: $output"

# AUR packages already installed by pacman must not require or invoke a helper.
aur_bin="$tmp/aur-bin"
mkdir -p "$aur_bin"
make_fake "$aur_bin/pacman" '
if [[ "$1" == -Q && "$2" == cli-proxy-api-bin ]]; then exit 0; fi
exit 1'
make_fake "$aur_bin/yay" 'printf "yay:%s\\n" "$*" >> "$COMMAND_LOG"; exit 88'
: > "$COMMAND_LOG"
PATH="$aur_bin:/usr/bin:/bin" install_aur_packages cli-proxy-api-bin
[[ ! -s "$COMMAND_LOG" ]] || fail "Installed AUR package unnecessarily invoked a helper"

# When both helpers exist, yay wins and root delegates to a usable SUDO_USER.
make_fake "$aur_bin/pacman" '[[ "$1" == -Q ]] && exit 1; exit 0'
make_fake "$aur_bin/id" '[[ "$1" == -u && "$2" == tester ]] && { echo 1000; exit 0; }; exit 1'
make_fake "$aur_bin/sudo" '
printf "sudo:%s\\n" "$*" >> "$COMMAND_LOG"
if [[ "$1" == -u ]]; then shift 2; fi
if [[ "${1:-}" == -- ]]; then shift; fi
"$@"'
make_fake "$aur_bin/yay" 'printf "yay:%s\\n" "$*" >> "$COMMAND_LOG"'
make_fake "$aur_bin/paru" 'printf "paru:%s\\n" "$*" >> "$COMMAND_LOG"'
: > "$COMMAND_LOG"
PATH="$aur_bin:/usr/bin:/bin" SUDO_USER=tester install_aur_packages cli-proxy-api-bin another-package
grep -q '^sudo:-u tester -- yay -S --needed --noconfirm cli-proxy-api-bin another-package$' "$COMMAND_LOG" || \
  fail "AUR install did not delegate yay with the expected arguments"
grep -q '^yay:-S --needed --noconfirm cli-proxy-api-bin another-package$' "$COMMAND_LOG" || \
  fail "yay did not receive the expected package arguments"
if grep -q '^paru:' "$COMMAND_LOG"; then
  fail "paru ran even though yay was available"
fi

# With yay absent, paru is selected deterministically.
paru_bin="$tmp/paru-bin"
mkdir -p "$paru_bin"
cp "$aur_bin/pacman" "$aur_bin/id" "$aur_bin/sudo" "$aur_bin/paru" "$paru_bin/"
: > "$COMMAND_LOG"
PATH="$paru_bin" SUDO_USER=tester install_aur_packages cli-proxy-api-bin
grep -q '^paru:-S --needed --noconfirm cli-proxy-api-bin$' "$COMMAND_LOG" || \
  fail "paru was not selected when yay was unavailable"

# Root without a usable original user must fail before invoking the helper.
: > "$COMMAND_LOG"
if output=$(PATH="$aur_bin:/usr/bin:/bin" SUDO_USER='' install_aur_packages cli-proxy-api-bin 2>&1); then
  fail "AUR install ran as root without a usable SUDO_USER"
fi
[[ "$output" == *"refusing to run the AUR helper as root"* ]] || \
  fail "Root refusal error was not clear: $output"
[[ ! -s "$COMMAND_LOG" ]] || fail "Root refusal still invoked an AUR helper"

# Helper failures must propagate to callers.
make_fake "$aur_bin/yay" 'exit 42'
if PATH="$aur_bin:/usr/bin:/bin" SUDO_USER=tester install_aur_packages cli-proxy-api-bin; then
  fail "AUR helper failure did not propagate"
fi

printf 'packages_test.sh: PASS\n'
