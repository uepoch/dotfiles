#!/usr/bin/env python3
"""
factory-sync-cli-proxy.py

Reads a local cli-proxy-api config.yaml and generates a Factory Droid
settings.local.json fragment with model entries pointing at the local proxy.

Usage:
    python3 factory-sync-cli-proxy.py [path/to/config.yaml]

The generated file is written to:
    ~/.factory/settings.local.json

It should be merged with factory/settings.template.json to produce the final
~/.factory/settings.json. A simple approach is to use jq or just copy the
template and append the customModels array.
"""

import json
import os
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install it with: pip install pyyaml")
    sys.exit(1)

PROXY_PORT = 8317
PROXY_HOST = "127.0.0.1"
API_KEY_ENV = "CLI_PROXY_API_KEY"
SETTINGS_DIR = os.path.expanduser("~/.factory")
SETTINGS_LOCAL = os.path.join(SETTINGS_DIR, "settings.local.json")


def load_config(path):
    with open(path) as f:
        return yaml.safe_load(f)


def extract_models(config):
    """Extract model alias/name pairs from openai-compatibility sections."""
    models = []
    api_key = os.environ.get(API_KEY_ENV, "")
    base_url = f"http://{PROXY_HOST}:{config.get('port', PROXY_PORT)}/v1"

    for section in config.get("openai-compatibility", []):
        for model_entry in section.get("models", []):
            name = model_entry.get("name", "")
            alias = model_entry.get("alias", name)
            models.append({
                "model": alias,
                "id": f"custom:{alias}-0",
                "index": len(models),
                "baseUrl": base_url,
                "apiKey": api_key,
                "displayName": alias,
                "enableThinking": True,
                "noImageSupport": False,
                "provider": "anthropic",
            })

    return models


def write_local_settings(models):
    os.makedirs(SETTINGS_DIR, exist_ok=True)
    settings = {
        "customModels": models,
    }
    with open(SETTINGS_LOCAL, "w") as f:
        json.dump(settings, f, indent=2)
    print(f"Wrote {len(models)} model(s) to {SETTINGS_LOCAL}")


def main():
    config_path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        "~/.cli-proxy-api/config.yaml"
    )

    if not os.path.isfile(config_path):
        print(f"ERROR: config not found at {config_path}")
        sys.exit(1)

    config = load_config(config_path)
    models = extract_models(config)

    if not models:
        print("No models found in cli-proxy-api config.")
        sys.exit(0)

    write_local_settings(models)
    print(f"\nTo apply: merge {SETTINGS_LOCAL} into ~/.factory/settings.json")
    print(f"Tip: set {API_KEY_ENV} env var before running to populate API keys.")


if __name__ == "__main__":
    main()
