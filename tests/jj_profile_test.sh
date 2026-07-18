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
export JJ_STATE="$tmp/jj-state"

make_fake "$fake_bin/sudo" 'printf "sudo:%s\\n" "$*" >> "$COMMAND_LOG"; "$@"'
make_fake "$fake_bin/pacman" 'printf "pacman:%s\\n" "$*" >> "$COMMAND_LOG"'
make_fake "$fake_bin/git" '
case "$*" in
  "config --global user.name")
    [[ -n "${GIT_NAME:-}" ]] && printf "%s\\n" "$GIT_NAME"
    ;;
  "config --global user.email")
    [[ -n "${GIT_EMAIL:-}" ]] && printf "%s\\n" "$GIT_EMAIL"
    ;;
  *) printf "git:%s\\n" "$*" >> "$COMMAND_LOG" ;;
esac'
make_fake "$fake_bin/jj" '
printf "jj:" >> "$COMMAND_LOG"
printf "<%s>" "$@" >> "$COMMAND_LOG"
printf "\\n" >> "$COMMAND_LOG"
if [[ "$1 $2 $3" == "config list --user" ]]; then
  key="$4"
  value=$(sed -n "s/^${key}=//p" "$JJ_STATE" 2>/dev/null | head -n1)
  [[ -n "$value" ]] || exit 1
  printf "%s\\n" "$value"
elif [[ "$1 $2 $3" == "config set --user" ]]; then
  key="$4"
  value="$5"
  temporary="${JJ_STATE}.tmp"
  { grep -v "^${key}=" "$JJ_STATE" 2>/dev/null || true; printf "%s=%s\\n" "$key" "$value"; } > "$temporary"
  mv "$temporary" "$JJ_STATE"
fi'

profile_env=(
  PATH="$fake_bin:/usr/bin:/bin"
  DOTFILES_DISTRO_OVERRIDE=arch
)

# Existing Git identity seeds missing jj values through jj config. Quotes and
# spaces remain a single argument, and no TOML file is appended manually.
: > "$COMMAND_LOG"
: > "$JJ_STATE"
env "${profile_env[@]}" \
  GIT_NAME='Existing "Quoted" User' \
  GIT_EMAIL='existing@example.com' \
  bash "$REPO_ROOT/install/profiles/jj.sh" </dev/null > /dev/null

grep -q 'pacman:-S --needed --noconfirm jujutsu' "$COMMAND_LOG" || \
  fail "Arch jj profile did not install Jujutsu through pacman"
grep -Fxq 'user.name=Existing "Quoted" User' "$JJ_STATE" || \
  fail "JJ name was not seeded from existing Git identity"
grep -Fxq 'user.email=existing@example.com' "$JJ_STATE" || \
  fail "JJ email was not seeded from existing Git identity"
grep -Fqx 'jj:<config><set><--user><user.name><Existing "Quoted" User>' "$COMMAND_LOG" || \
  fail "JJ name with spaces and quotes was not passed as one argument"
grep -Fqx 'jj:<config><set><--user><user.email><existing@example.com>' "$COMMAND_LOG" || \
  fail "JJ email was not passed through jj config set"
[[ ! -e "$home/.jjconfig.toml" ]] || \
  fail "JJ identity setup manually created .jjconfig.toml"

# Existing jj identity is queried and never overwritten.
printf '%s\n' \
  'user.name=Already Configured' \
  'user.email=already@example.com' > "$JJ_STATE"
: > "$COMMAND_LOG"
env "${profile_env[@]}" \
  DOTFILES_USER_NAME='Replacement User' \
  DOTFILES_USER_EMAIL='replacement@example.com' \
  GIT_NAME='Git User' \
  GIT_EMAIL='git@example.com' \
  bash "$REPO_ROOT/install/profiles/jj.sh" </dev/null > /dev/null
grep -Fxq 'user.name=Already Configured' "$JJ_STATE" || \
  fail "Existing JJ name was overwritten"
grep -Fxq 'user.email=already@example.com' "$JJ_STATE" || \
  fail "Existing JJ email was overwritten"
grep -Fqx 'jj:<config><list><--user><user.name><-T><value>' "$COMMAND_LOG" || \
  fail "JJ name was not queried through supported user-scoped config list"
grep -Fqx 'jj:<config><list><--user><user.email><-T><value>' "$COMMAND_LOG" || \
  fail "JJ email was not queried through supported user-scoped config list"
if grep -Fq 'jj:<config><get><--user>' "$COMMAND_LOG"; then
  fail "JJ identity setup used unsupported config get --user syntax"
fi
if grep -Fq 'jj:<config><set><--user>' "$COMMAND_LOG"; then
  fail "JJ config set ran despite complete existing identity"
fi
[[ ! -e "$home/.jjconfig.toml" ]] || \
  fail "JJ identity setup appended to .jjconfig.toml"

# With no flags, environment, or Git identity, redirected stdin must fail before
# package installation instead of hanging.
: > "$COMMAND_LOG"
: > "$JJ_STATE"
if output=$(env "${profile_env[@]}" \
  DOTFILES_USER_NAME='' DOTFILES_USER_EMAIL='' GIT_NAME='' GIT_EMAIL='' \
  bash "$REPO_ROOT/install/profiles/jj.sh" </dev/null 2>&1); then
  fail "Unattended jj profile succeeded without identity"
fi
[[ "$output" == *"no interactive terminal"* ]] || \
  fail "Missing identity failure lacked guidance"
[[ ! -s "$COMMAND_LOG" ]] || \
  fail "JJ profile installed packages before identity preflight"

printf 'jj_profile_test.sh: PASS\n'
