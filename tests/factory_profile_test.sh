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
#!/bin/bash
$body
SCRIPT
  chmod +x "$path"
}

line_of() {
  local pattern="$1"
  grep -n -m1 "$pattern" "$COMMAND_LOG" | cut -d: -f1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
home="$tmp/home"
mkdir -p "$fake_bin" "$home"

setup_script="$tmp/cli-proxy-init.py"
configure_script="$tmp/cli-proxy-provider.py"
sync_script="$tmp/factory-sync-cli-proxy.py"
: > "$setup_script"
: > "$configure_script"
: > "$sync_script"

export HOME="$home"
export COMMAND_LOG="$tmp/commands.log"
export PROXY_CONFIG_PATH="$home/.cli-proxy-api/config.yaml"

make_fake "$fake_bin/sudo" '
printf "sudo:%s\\n" "$*" >> "$COMMAND_LOG"
if [[ "$1" == -u ]]; then shift 2; fi
if [[ "${1:-}" == -- ]]; then shift; fi
"$@"'
make_fake "$fake_bin/pacman" '
printf "pacman:%s\\n" "$*" >> "$COMMAND_LOG"
if [[ "$1" == -Q ]]; then exit 1; fi'
make_fake "$fake_bin/yay" 'printf "yay:%s\\n" "$*" >> "$COMMAND_LOG"'
make_fake "$fake_bin/id" '[[ "$1" == -u && "$2" == tester ]] && { echo 1000; exit 0; }; exit 1'
make_fake "$fake_bin/droid" 'exit 0'
make_fake "$fake_bin/curl" '
printf "curl:%s\\n" "$*" >> "$COMMAND_LOG"
[[ "${FAIL_HEALTH:-0}" != 1 ]]'
make_fake "$fake_bin/python3" '
name=${1##*/}
shift
printf "python:%s %s\\n" "$name" "$*" >> "$COMMAND_LOG"
if [[ "$name" == - ]]; then
  exec /usr/bin/python3 - "$@"
fi
case "$name" in
  cli-proxy-init.py)
    mkdir -p "$(dirname "$PROXY_CONFIG_PATH")"
    if [[ -n "${CONFIG_CONTENT+x}" ]]; then
      printf "%s\\n" "$CONFIG_CONTENT" > "$PROXY_CONFIG_PATH"
    else
      printf "port: %s\\n" "${CONFIG_PORT:-8317}" > "$PROXY_CONFIG_PATH"
    fi
    ;;
  factory-sync-cli-proxy.py)
    [[ "${FAIL_SYNC:-0}" != 1 ]] || exit 23
    ;;
esac'
make_fake "$fake_bin/systemctl" '
printf "systemctl:%s\\n" "$*" >> "$COMMAND_LOG"
if [[ "$*" == "--user enable cli-proxy-api.service" && "${FAIL_ENABLE:-0}" == 1 ]]; then
  exit 19
fi
if [[ "$*" == "--user restart cli-proxy-api.service" && "${FAIL_RESTART:-0}" == 1 ]]; then
  exit 20
fi
if [[ "$*" == "--user is-active --quiet cli-proxy-api.service" && "${SERVICE_ACTIVE:-1}" != 1 ]]; then
  exit 3
fi'

profile_env=(
  PATH="$fake_bin:/usr/bin:/bin"
  DOTFILES_DISTRO_OVERRIDE=arch
  SUDO_USER=tester
  CLI_PROXY_SETUP_SCRIPT="$setup_script"
  CLI_PROXY_PROVIDER_SCRIPT="$configure_script"
  CLI_PROXY_SYNC_SCRIPT="$sync_script"
)

# A non-interactive Arch run installs the approved packages, preserves defaults,
# discovers provider credentials without prompting, and orders setup/service/sync correctly.
: > "$COMMAND_LOG"
env "${profile_env[@]}" bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > "$tmp/output"

grep -q 'pacman:-S --needed --noconfirm gum python-yaml python-ruamel-yaml' "$COMMAND_LOG" || \
  fail "Factory profile omitted or changed approved official Arch packages"
if grep -q 'gum-git' "$COMMAND_LOG"; then
  fail "Factory profile used stale gum-git instead of official gum"
fi
grep -q 'yay:-S --needed --noconfirm cli-proxy-api-bin' "$COMMAND_LOG" || \
  fail "Factory profile did not install cli-proxy-api-bin via AUR"
grep -q 'systemctl:--user daemon-reload' "$COMMAND_LOG" || \
  fail "Factory profile did not reload user units"
grep -q 'systemctl:--user enable cli-proxy-api.service' "$COMMAND_LOG" || \
  fail "Factory profile did not enable the user service"
grep -q 'systemctl:--user restart cli-proxy-api.service' "$COMMAND_LOG" || \
  fail "Factory profile did not restart the user service"
grep -q 'curl:--noproxy \* --fail --silent --show-error' "$COMMAND_LOG" || \
  fail "Factory profile did not wait for local proxy health"
grep -Fq 'http://127.0.0.1:8317/healthz' "$COMMAND_LOG" || \
  fail "Factory profile did not use the default configured health port"
grep -q 'systemctl:--user is-active --quiet cli-proxy-api.service' "$COMMAND_LOG" || \
  fail "Factory profile did not verify the user service"
grep -q "^python:cli-proxy-provider.py zai --config $PROXY_CONFIG_PATH --if-available$" \
  "$COMMAND_LOG" || fail "Non-interactive profile did not perform safe provider discovery"
grep -q 'preserving curated cli-proxy-api model defaults' "$tmp/output" || \
  fail "Non-interactive profile did not report preserving curated defaults"
grep -q "^python:factory-sync-cli-proxy.py --config $PROXY_CONFIG_PATH --non-interactive --yes$" "$COMMAND_LOG" || \
  fail "Non-interactive profile did not reuse curated defaults without prompting"
override_file="$HOME/.config/systemd/user/cli-proxy-api.service.d/team-dotfiles.conf"
grep -Fq "ExecStart=/usr/bin/cli-proxy-api --config \"$PROXY_CONFIG_PATH\"" \
  "$override_file" || fail "Factory profile did not bind the service to its proxy config"

setup_line=$(line_of 'python:cli-proxy-init.py --config')
provider_line=$(line_of 'python:cli-proxy-provider.py zai --config')
reload_line=$(line_of 'systemctl:--user daemon-reload')
enable_line=$(line_of 'systemctl:--user enable cli-proxy-api.service')
restart_line=$(line_of 'systemctl:--user restart cli-proxy-api.service')
health_line=$(line_of 'curl:--noproxy')
sync_line=$(line_of 'python:factory-sync-cli-proxy.py')
active_line=$(line_of 'systemctl:--user is-active --quiet')
[[ "$setup_line" -lt "$provider_line" && "$provider_line" -lt "$reload_line" &&
  "$reload_line" -lt "$enable_line" && "$enable_line" -lt "$restart_line" &&
  "$restart_line" -lt "$health_line" && "$health_line" -lt "$sync_line" &&
  "$sync_line" -lt "$active_line" ]] || \
  fail "Factory setup/service/sync/health operations ran out of order"

# A custom config path is propagated to the packaged systemd service through a drop-in.
custom_config="$home/custom proxy/config.yaml"
: > "$COMMAND_LOG"
env "${profile_env[@]}" CLI_PROXY_CONFIG="$custom_config" \
  PROXY_CONFIG_PATH="$custom_config" \
  bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null
grep -Fq "ExecStart=/usr/bin/cli-proxy-api --config \"$custom_config\"" \
  "$override_file" || fail "Custom proxy config was not propagated to systemd"

# Readiness follows a validated non-default port from the initialized config.
: > "$COMMAND_LOG"
env "${profile_env[@]}" CONFIG_PORT=18442 \
  bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null
grep -Fq 'http://127.0.0.1:18442/healthz' "$COMMAND_LOG" || \
  fail "Factory profile ignored the non-default configured health port"
if grep -Fq 'http://127.0.0.1:8317/healthz' "$COMMAND_LOG"; then
  fail "Factory profile retained the hardcoded default health port"
fi

# A missing port uses cli-proxy-init.py's effective default.
: > "$COMMAND_LOG"
env "${profile_env[@]}" CONFIG_CONTENT='host: 127.0.0.1' \
  bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null
grep -Fq 'http://127.0.0.1:8317/healthz' "$COMMAND_LOG" || \
  fail "Factory profile did not use the default health port when port was omitted"

# Non-loopback proxy hosts fail before service startup or model sync.
: > "$COMMAND_LOG"
if env "${profile_env[@]}" CONFIG_CONTENT=$'host: 0.0.0.0\nport: 8317' \
  bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null 2>&1; then
  fail "Factory profile accepted a non-loopback proxy host"
fi
if grep -Eq 'systemctl:--user (daemon-reload|enable|restart)|python:factory-sync-cli-proxy.py|curl:--noproxy' \
  "$COMMAND_LOG"; then
  fail "Factory profile continued after a non-loopback proxy host"
fi

# Invalid ports and malformed YAML fail before service startup or model sync.
for invalid_config in 'port: 0' 'port: 65536' 'port: not-a-number' 'port: ['; do
  : > "$COMMAND_LOG"
  if env "${profile_env[@]}" CONFIG_CONTENT="$invalid_config" \
    bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null 2>&1; then
    fail "Factory profile accepted invalid proxy config: $invalid_config"
  fi
  if grep -Eq 'systemctl:--user (daemon-reload|enable|restart)|python:factory-sync-cli-proxy.py|curl:--noproxy' \
    "$COMMAND_LOG"; then
    fail "Factory profile continued after invalid proxy port: $invalid_config"
  fi
done

# When a pseudo-terminal is available, the profile invokes the sync tool's gum wizard mode.
if command -v script >/dev/null 2>&1; then
  : > "$COMMAND_LOG"
  env "${profile_env[@]}" script -qec     "bash '$REPO_ROOT/install/profiles/factory.sh'" /dev/null     </dev/null > "$tmp/interactive-output"
  grep -Fxq "python:factory-sync-cli-proxy.py --config $PROXY_CONFIG_PATH" "$COMMAND_LOG" || \
    fail "Interactive profile did not invoke the model wizard mode"
  grep -q 'Opening the cli-proxy-api model wizard' "$tmp/interactive-output" || \
    fail "Interactive profile did not announce the model wizard"
fi

# Z.AI is configured only when its key exists; the secret stays in the environment.
: > "$COMMAND_LOG"
env "${profile_env[@]}" ZAI_API_KEY='test-secret' \
  bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null
grep -q "^python:cli-proxy-provider.py zai --config $PROXY_CONFIG_PATH --if-available$" "$COMMAND_LOG" || \
  fail "Z.AI provider setup did not run when ZAI_API_KEY was present"
if grep -q 'test-secret' "$COMMAND_LOG"; then
  fail "ZAI_API_KEY leaked into command arguments"
fi

# Droid installation errors from curl must propagate and stop before setup.
mv "$fake_bin/droid" "$fake_bin/droid.installed"
make_fake "$fake_bin/curl" 'exit 17'
: > "$COMMAND_LOG"
if env "${profile_env[@]}" bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null 2>&1; then
  fail "Factory profile ignored a Droid installer download failure"
fi
if grep -q 'python:cli-proxy-init.py' "$COMMAND_LOG"; then
  fail "Factory profile continued to setup after Droid installation failed"
fi

# Restore installed Droid and verify service/setup failures propagate before sync.
make_fake "$fake_bin/droid" 'exit 0'
make_fake "$fake_bin/curl" '
printf "curl:%s\\n" "$*" >> "$COMMAND_LOG"
[[ "${FAIL_HEALTH:-0}" != 1 ]]'
: > "$COMMAND_LOG"
if env "${profile_env[@]}" FAIL_ENABLE=1 \
  bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null 2>&1; then
  fail "Factory profile ignored systemctl enable failure"
fi

: > "$COMMAND_LOG"
if env "${profile_env[@]}" FAIL_RESTART=1 \
  bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null 2>&1; then
  fail "Factory profile ignored systemctl restart failure"
fi
if grep -q 'python:factory-sync-cli-proxy.py' "$COMMAND_LOG"; then
  fail "Factory profile synced after systemctl restart failed"
fi
if grep -q 'python:factory-sync-cli-proxy.py' "$COMMAND_LOG"; then
  fail "Factory profile synced after systemctl enable failed"
fi

: > "$COMMAND_LOG"
if env "${profile_env[@]}" FAIL_SYNC=1 \
  bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null 2>&1; then
  fail "Factory profile ignored model sync failure"
fi

: > "$COMMAND_LOG"
if env "${profile_env[@]}" SERVICE_ACTIVE=0 \
  bash "$REPO_ROOT/install/profiles/factory.sh" </dev/null > /dev/null 2>&1; then
  fail "Factory profile succeeded with an inactive cli-proxy-api service"
fi

printf 'factory_profile_test.sh: PASS\n'
