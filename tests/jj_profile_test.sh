#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_fake() {
  local path="$1"
  local body="$2"
  cat > "$path" <<SCRIPT
#!/usr/bin/env bash
$body
SCRIPT
  chmod +x "$path"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
home="$tmp/home"
mkdir -p "$fake_bin" "$home"
export HOME="$home"
export COMMAND_LOG="$tmp/commands.log"

make_fake "$fake_bin/sudo" 'printf "sudo:%s\\n" "$*" >> "$COMMAND_LOG"; "$@"'
make_fake "$fake_bin/pacman" 'printf "pacman:%s\\n" "$*" >> "$COMMAND_LOG"'
make_fake "$fake_bin/jj" 'exit 0'
make_fake "$fake_bin/git" '
if [[ "$*" == "config --global user.name" ]]; then
  printf "%s\\n" "Existing User"
elif [[ "$*" == "config --global user.email" ]]; then
  printf "%s\\n" "existing@example.com"
else
  printf "git:%s\\n" "$*" >> "$COMMAND_LOG"
fi'

PATH="$fake_bin:/usr/bin:/bin" bash "$REPO_ROOT/install/profiles/jj.sh" </dev/null

grep -q 'pacman:-S --needed --noconfirm jujutsu' "$COMMAND_LOG" || \
  fail "Arch jj profile did not install Jujutsu through pacman"
grep -q 'name = "Existing User"' "$home/.jjconfig.toml" || \
  fail "JJ name was not seeded from existing Git identity"
grep -q 'email = "existing@example.com"' "$home/.jjconfig.toml" || \
  fail "JJ email was not seeded from existing Git identity"

# With no flags, environment, or Git identity, redirected stdin must fail instead of hanging.
: > "$COMMAND_LOG"
rm -f "$home/.jjconfig.toml"
make_fake "$fake_bin/git" 'exit 0'
if output=$(PATH="$fake_bin:/usr/bin:/bin" DOTFILES_USER_NAME='' DOTFILES_USER_EMAIL='' \
  bash "$REPO_ROOT/install/profiles/jj.sh" </dev/null 2>&1); then
  fail "Unattended jj profile succeeded without identity"
fi
[[ "$output" == *"no interactive terminal"* ]] || fail "Missing identity failure lacked guidance"
[[ ! -s "$COMMAND_LOG" ]] || fail "JJ profile installed packages before identity preflight"

echo "jj_profile_test.sh: PASS"
