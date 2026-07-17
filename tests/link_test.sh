#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_fake_stow() {
  local path="$1"
  cat > "$path" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STOW_LOG"
exit "${STOW_EXIT:-0}"
SCRIPT
  chmod +x "$path"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
home="$tmp/home"
fake_bin="$tmp/bin"
mkdir -p "$repo/install/lib" "$repo/stow/zsh" "$repo/stow/config/.config/app" "$home" "$fake_bin"
cp "$SOURCE_REPO_ROOT/install/lib/link.sh" "$repo/install/lib/link.sh"
printf 'managed zshrc\n' > "$repo/stow/zsh/.zshrc"
printf 'managed zprofile\n' > "$repo/stow/zsh/.zprofile"
printf 'managed zshenv\n' > "$repo/stow/zsh/.zshenv"
printf 'managed config\n' > "$repo/stow/config/.config/app/config.toml"
printf 'managed tools\n' > "$repo/stow/config/.tool-versions"
make_fake_stow "$fake_bin/stow"
export HOME="$home"
export PATH="$fake_bin:/usr/bin:/bin"
export STOW_LOG="$tmp/stow.log"
# shellcheck source=../install/lib/link.sh
source "$repo/install/lib/link.sh"

printf 'old zshrc\n' > "$home/.zshrc"
printf 'old zprofile\n' > "$home/.zprofile"
printf 'old zshenv\n' > "$home/.zshenv"
mkdir -p "$home/.config/app"
printf 'old config\n' > "$home/.config/app/config.toml"
printf 'leave me\n' > "$home/unmanaged.txt"

if output=$(link_stow_packages zsh config 2>&1); then
  fail "Default linking succeeded despite regular-file conflicts"
fi
[[ "$output" == *"--migrate-existing"* ]] || fail "Default conflict error lacked migration guidance"
[[ -f "$home/.zshrc" ]] || fail "Default mode modified .zshrc"
[[ -f "$home/.config/app/config.toml" ]] || fail "Default mode modified config conflict"
[[ ! -s "$STOW_LOG" ]] || fail "Default conflict path invoked Stow"

link_stow_packages --migrate-existing zsh config
[[ ! -e "$home/.zshrc" ]] || fail "Migration left conflicting .zshrc in place"
[[ ! -e "$home/.zprofile" ]] || fail "Migration left conflicting .zprofile in place"
[[ ! -e "$home/.zshenv" ]] || fail "Migration left conflicting .zshenv in place"
[[ ! -e "$home/.config/app/config.toml" ]] || fail "Migration left nested config conflict in place"
[[ -f "$home/unmanaged.txt" ]] || fail "Migration touched an unmanaged home file"
[[ $(cat "$home/unmanaged.txt") == "leave me" ]] || fail "Migration changed unmanaged home content"

for original in .zshrc .zprofile .zshenv .config/app/config.toml; do
  backup_count=$(find "$home/$(dirname "$original")" -maxdepth 1 -type f -name "$(basename "$original").bak.*" | wc -l)
  [[ "$backup_count" -eq 1 ]] || fail "Expected one timestamped backup for $original, got $backup_count"
done
[[ $(wc -l < "$STOW_LOG") -eq 2 ]] || fail "Migration did not run Stow simulation and apply exactly once"
grep -q -- '--simulate' "$STOW_LOG" || fail "Migration skipped Stow simulation"

# An unrelated Stow failure must propagate rather than becoming a warning/success.
: > "$STOW_LOG"
export STOW_EXIT=23
if link_stow_packages zsh config >/dev/null 2>&1; then
  fail "Stow failure did not propagate"
else
  status=$?
fi
[[ "$status" -eq 23 ]] || fail "Expected Stow status 23, got $status"

# Failed migration must put every moved file back in its original location.
export STOW_EXIT=23
for backup in "$home"/.zshrc.bak.* "$home"/.zprofile.bak.* "$home"/.zshenv.bak.* \
  "$home"/.config/app/config.toml.bak.*; do
  [[ -e "$backup" ]] && rm "$backup"
done
printf 'restore me\n' > "$home/.zshrc"
if link_stow_packages --migrate-existing zsh config >/dev/null 2>&1; then
  fail "Migration succeeded despite Stow failure"
fi
[[ -f "$home/.zshrc" ]] || fail "Failed migration did not restore .zshrc"
[[ $(cat "$home/.zshrc") == "restore me" ]] || fail "Failed migration changed restored content"
rm "$home/.zshrc"

# Migration refuses symlinks instead of moving them.
export STOW_EXIT=0
ln -s "$tmp/elsewhere" "$home/.zshrc"
if output=$(link_stow_packages --migrate-existing zsh config 2>&1); then
  fail "Migration accepted a conflicting symlink"
fi
[[ -L "$home/.zshrc" ]] || fail "Migration modified a conflicting symlink"
[[ "$output" == *"will not modify"* ]] || fail "Unsafe conflict error was not clear"

# A symlinked parent must not allow migration to move files outside HOME.
rm "$home/.zshrc"
external_config="$tmp/external-config"
mkdir -p "$external_config/app"
printf 'external config\n' > "$external_config/app/config.toml"
mv "$home/.config" "$home/.config.backups"
ln -s "$external_config" "$home/.config"
if output=$(link_stow_packages --migrate-existing zsh config 2>&1); then
  fail "Migration accepted a symlinked parent directory"
fi
[[ -f "$external_config/app/config.toml" ]] || fail "Migration moved a file through a symlinked parent"
[[ $(cat "$external_config/app/config.toml") == "external config" ]] || fail "Migration changed external file content"

# Missing Stow must fail clearly before any migration work.
empty_bin="$tmp/empty-bin"
mkdir -p "$empty_bin"
if output=$(PATH="$empty_bin" link_stow_packages zsh config 2>&1); then
  fail "Linking succeeded without Stow"
fi
[[ "$output" == *"GNU Stow is not installed"* ]] || fail "Missing Stow error was not clear"

echo "link_test.sh: PASS"
