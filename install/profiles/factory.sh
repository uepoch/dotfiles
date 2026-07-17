#!/usr/bin/env bash
# factory.sh - install Factory Droid and orchestrate cli-proxy-api setup.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../lib/detect_distro.sh
source "$REPO_ROOT/install/lib/detect_distro.sh"
# shellcheck source=../lib/packages.sh
source "$REPO_ROOT/install/lib/packages.sh"

distro="${DOTFILES_DISTRO_OVERRIDE:-$(detect_distro)}"
PROXY_CONFIG="${CLI_PROXY_CONFIG:-$HOME/.cli-proxy-api/config.yaml}"
PROXY_SERVICE="${CLI_PROXY_SERVICE:-cli-proxy-api.service}"
PROXY_SERVICE_OVERRIDE="${CLI_PROXY_SERVICE_OVERRIDE:-$HOME/.config/systemd/user/$PROXY_SERVICE.d/team-dotfiles.conf}"

resolve_repo_script() {
  local override="$1"
  local purpose="$2"
  shift 2
  local candidate

  if [[ -n "$override" ]]; then
    if [[ -f "$override" ]]; then
      printf '%s\n' "$override"
      return 0
    fi
    echo "ERROR: configured $purpose script not found at $override." >&2
    return 1
  fi

  for candidate in "$@"; do
    if [[ -f "$REPO_ROOT/scripts/$candidate" ]]; then
      printf '%s\n' "$REPO_ROOT/scripts/$candidate"
      return 0
    fi
  done

  echo "ERROR: no $purpose script found under $REPO_ROOT/scripts (tried: $*)." >&2
  return 1
}

run_cli_proxy_setup() {
  local setup_script
  setup_script=$(resolve_repo_script "${CLI_PROXY_SETUP_SCRIPT:-}" "cli-proxy setup" \
    cli-proxy-setup.py cli-proxy-init.py factory-cli-proxy-setup.py) || return 1

  echo "Initializing cli-proxy-api configuration ..."
  python3 "$setup_script" --config "$PROXY_CONFIG"

  if [[ ! -f "$PROXY_CONFIG" ]]; then
    echo "ERROR: cli-proxy-api setup did not create the expected config at $PROXY_CONFIG." >&2
    return 1
  fi
}

configure_cli_proxy() {
  local provider_script

  provider_script=$(resolve_repo_script \
    "${CLI_PROXY_PROVIDER_SCRIPT:-${CLI_PROXY_CONFIGURE_SCRIPT:-}}" \
    "cli-proxy provider configuration" \
    cli-proxy-provider.py cli-proxy-configure.py \
    factory-cli-proxy-configure.py) || return 1
  echo "Configuring the Z.AI provider when a key is available ..."
  case "${provider_script##*/}" in
    cli-proxy-provider.py)
      if [[ -t 0 && -t 1 ]]; then
        python3 "$provider_script" zai --config "$PROXY_CONFIG"
      else
        python3 "$provider_script" zai --config "$PROXY_CONFIG" --if-available
      fi
      ;;
    *)
      python3 "$provider_script" --provider zai --config "$PROXY_CONFIG" \
        --if-available
      ;;
  esac
}

sync_factory_models() {
  local sync_script
  sync_script=$(resolve_repo_script "${CLI_PROXY_SYNC_SCRIPT:-}" "Factory model sync" \
    factory-sync-cli-proxy.py cli-proxy-sync.py) || return 1

  if [[ -t 0 && -t 1 ]]; then
    echo "Opening the cli-proxy-api model wizard ..."
    python3 "$sync_script" --config "$PROXY_CONFIG"
  else
    echo "Non-interactive session detected; preserving curated cli-proxy-api model defaults."
    python3 "$sync_script" --config "$PROXY_CONFIG" --non-interactive --yes
  fi
}

wait_for_cli_proxy() {
  local health_url="http://127.0.0.1:8317/healthz"
  local _
  for _ in {1..30}; do
    if curl --noproxy '*' --fail --silent --show-error \
      --connect-timeout 1 --max-time 2 "$health_url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: cli-proxy-api did not become healthy at $health_url." >&2
  return 1
}


echo "=== Setting up Factory Droid on $distro ==="

if [[ "$distro" == arch ]]; then
  install_packages arch gum python-yaml python-ruamel-yaml
  install_aur_packages cli-proxy-api-bin
else
  echo "NOTE: automatic cli-proxy-api package installation is currently supported only on Arch Linux."
fi

# Keep the upstream Droid installer behavior, but fail clearly when curl is
# unavailable and preserve failures from either side of the pipeline.
if ! command -v droid >/dev/null 2>&1; then
  echo "Installing Factory Droid CLI ..."
  require_command curl "install Factory Droid CLI" || exit 1
  curl -fsSL https://app.factory.ai/cli | sh
else
  echo "Factory Droid CLI already installed."
fi

require_command python3 "configure cli-proxy-api and Factory" || exit 1
require_command systemctl "manage the cli-proxy-api user service" || exit 1
require_command curl "check cli-proxy-api health" || exit 1

run_cli_proxy_setup
configure_cli_proxy

if [[ "$PROXY_CONFIG" == *$'\n'* ]]; then
  echo "ERROR: proxy config path must not contain newlines." >&2
  exit 1
fi
escaped_proxy_config=${PROXY_CONFIG//\\/\\\\}
escaped_proxy_config=${escaped_proxy_config//\"/\\\"}
escaped_proxy_config=${escaped_proxy_config//%/%%}
mkdir -p "$(dirname "$PROXY_SERVICE_OVERRIDE")"
override_tmp=$(mktemp "${PROXY_SERVICE_OVERRIDE}.tmp.XXXXXX")
trap 'rm -f "$override_tmp"' EXIT
printf '[Service]\nExecStart=\nExecStart=/usr/bin/cli-proxy-api --config "%s"\n' \
  "$escaped_proxy_config" > "$override_tmp"
chmod 0644 "$override_tmp"
mv -f "$override_tmp" "$PROXY_SERVICE_OVERRIDE"
trap - EXIT

echo "Reloading, enabling, and restarting $PROXY_SERVICE ..."
systemctl --user daemon-reload
systemctl --user enable "$PROXY_SERVICE"
systemctl --user restart "$PROXY_SERVICE"
wait_for_cli_proxy

sync_factory_models

if ! systemctl --user is-active --quiet "$PROXY_SERVICE"; then
  echo "ERROR: $PROXY_SERVICE is not active after setup." >&2
  exit 1
fi

echo "cli-proxy-api service is active."
echo "=== Factory profile done ==="
