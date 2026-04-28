#!/usr/bin/env bash
# factory.sh - set up Factory Droid CLI and generate local config from cli-proxy-api.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Setting up Factory Droid ==="

# Install Factory CLI if not already present
if ! command -v droid &>/dev/null; then
  echo "Installing Factory Droid CLI ..."
  curl -fsSL https://app.factory.ai/cli | sh
else
  echo "Factory Droid CLI already installed."
fi

# Run the cli-proxy-api sync helper if Python is available and config exists
if command -v python3 &>/dev/null; then
  SYNC_SCRIPT="$REPO_ROOT/scripts/factory-sync-cli-proxy.py"
  PROXY_CONFIG="$HOME/.cli-proxy-api/config.yaml"

  if [[ -f "$SYNC_SCRIPT" && -f "$PROXY_CONFIG" ]]; then
    echo "Generating local Factory settings from cli-proxy-api ..."
    python3 "$SYNC_SCRIPT" "$PROXY_CONFIG"
  else
    echo "NOTE: cli-proxy-api config not found at $PROXY_CONFIG."
    echo "      Run this profile after setting up cli-proxy-api."
  fi
else
  echo "WARNING: python3 not found. Cannot run factory-sync-cli-proxy.py."
fi

echo "=== Factory profile done ==="
