#!/usr/bin/env python3
"""Initialize a private, localhost-only cli-proxy-api configuration."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import secrets
import sys

from cli_proxy_common import (
    ProxyToolError,
    file_lock,
    first_real_secret,
    parse_env_file,
    read_yaml,
    replace_nested_scalar,
    replace_top_scalar,
    replace_top_sequence,
    update_env_text,
    validate_yaml_text,
    write_if_changed,
)

DEFAULT_EXAMPLE = Path("/usr/share/doc/cli-proxy-api-bin/config.example.yaml")


def secure_token() -> str:
    return secrets.token_urlsafe(32)


def initialize(
    *,
    config_path: Path,
    example_path: Path,
    env_path: Path,
    enable_management: bool = False,
) -> tuple[bool, bool]:
    """Initialize config/env files and return their changed states."""
    with file_lock(config_path):
        if config_path.exists():
            config_text, config = read_yaml(config_path)
        else:
            try:
                config_text = example_path.read_text(encoding="utf-8")
            except OSError as exc:
                raise ProxyToolError(f"Unable to read package example: {example_path}") from exc
            config = validate_yaml_text(config_text)

        for key in ("host", "port", "api-keys", "remote-management"):
            if len(re.findall(rf"(?m)^{re.escape(key)}\s*:", config_text)) > 1:
                raise ProxyToolError(
                    f"Proxy config contains duplicate top-level {key} keys"
                )

        env_values = parse_env_file(env_path)
        api_key = first_real_secret(config.get("api-keys"))
        if api_key is None:
            api_key = env_values.get("CLI_PROXY_API_KEY") or secure_token()
            config_text = replace_top_sequence(config_text, "api-keys", [api_key])

        config_text = replace_top_scalar(config_text, "host", "127.0.0.1")

        management_key = env_values.get("CLI_PROXY_MANAGEMENT_KEY")
        remote_management = config.get("remote-management")
        configured_management = (
            remote_management.get("secret-key") if isinstance(remote_management, dict) else None
        )
        if enable_management:
            if not management_key:
                if isinstance(configured_management, str) and configured_management and not configured_management.startswith("$2"):
                    management_key = configured_management
                else:
                    management_key = secure_token()
            config_text = replace_nested_scalar(
                config_text, "remote-management", "secret-key", management_key
            )

        # Validate the exact document before either sensitive file is mutated.
        updated_config = validate_yaml_text(config_text)
        if updated_config.get("host") != "127.0.0.1":
            raise ProxyToolError("Proxy config must bind to 127.0.0.1")
        port = updated_config.get("port", 8317)
        if not isinstance(port, int) or not 1 <= port <= 65535:
            raise ProxyToolError("Proxy port must be an integer between 1 and 65535")
        existing_env = env_path.read_text(encoding="utf-8") if env_path.exists() else ""
        updates = {
            "CLI_PROXY_API_URL": f"http://127.0.0.1:{port}",
            "CLI_PROXY_API_KEY": api_key,
        }
        if management_key:
            updates["CLI_PROXY_MANAGEMENT_KEY"] = management_key
        env_text = update_env_text(existing_env, updates)

        config_changed = write_if_changed(config_path, config_text, mode=0o600)
        env_changed = write_if_changed(env_path, env_text, mode=0o600)
        return config_changed, env_changed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        type=Path,
        default=Path.home() / ".cli-proxy-api" / "config.yaml",
        help="proxy configuration path",
    )
    parser.add_argument(
        "--example",
        type=Path,
        default=DEFAULT_EXAMPLE,
        help="package example copied when --config is absent",
    )
    parser.add_argument(
        "--env-file",
        type=Path,
        default=Path.home() / ".config" / "team-dotfiles" / "proxy.env",
        help="private shell environment file",
    )
    parser.add_argument(
        "--management-key",
        action="store_true",
        help="generate or reuse a private management API key",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        config_changed, env_changed = initialize(
            config_path=args.config.expanduser(),
            example_path=args.example.expanduser(),
            env_path=args.env_file.expanduser(),
            enable_management=args.management_key,
        )
    except ProxyToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(
        "cli-proxy initialization complete "
        f"(config: {'updated' if config_changed else 'unchanged'}, "
        f"environment: {'updated' if env_changed else 'unchanged'})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
