#!/usr/bin/env python3
"""Configure owned upstream providers in cli-proxy-api."""

from __future__ import annotations

import argparse
import getpass
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any

from cli_proxy_common import (
    ProxyToolError,
    file_lock,
    is_placeholder_secret,
    parse_env_file,
    read_json,
    read_yaml,
    top_section_bounds,
    update_env_text,
    validate_yaml_text,
    write_if_changed,
    yaml_quote,
)

OWNED_MARKER = "team-dotfiles-managed: zai"
ZAI_BASE_URL = "https://api.z.ai/api/anthropic"
ZAI_MODEL = "glm-5.2"


def _entry_ranges(lines: list[str], start: int, end: int) -> list[tuple[int, int]]:
    starts = [index for index in range(start + 1, end) if re.match(r"^  -(?:\s|$)", lines[index])]
    return [(item, starts[pos + 1] if pos + 1 < len(starts) else end) for pos, item in enumerate(starts)]


def _set_entry_scalar(block: list[str], key: str, value: str) -> list[str]:
    newline = "\r\n" if any(line.endswith("\r\n") for line in block) else "\n"
    pattern = re.compile(
        rf"^(?P<prefix>(?:  -\s+|    ){re.escape(key)}\s*:)\s*.*?(?P<comment>\s+#.*)?(?:\r?\n)?$"
    )
    for index, line in enumerate(block):
        match = pattern.match(line)
        if match:
            block[index] = (
                f"{match.group('prefix')} {yaml_quote(value)}"
                f"{match.group('comment') or ''}{newline}"
            )
            return block
    insertion = 1 if block else 0
    block.insert(insertion, f"    {key}: {yaml_quote(value)}{newline}")
    return block


def _parsed_entry(block: list[str]) -> dict[str, Any]:
    value = validate_yaml_text("claude-api-key:\n" + "".join(block))
    entries = value.get("claude-api-key")
    return entries[0] if isinstance(entries, list) and entries and isinstance(entries[0], dict) else {}


def _ensure_model_mapping(block: list[str]) -> list[str]:
    parsed = _parsed_entry(block)
    models = parsed.get("models")
    if isinstance(models, list) and any(
        isinstance(model, dict)
        and model.get("name") == ZAI_MODEL
        and model.get("alias") == ZAI_MODEL
        for model in models
    ):
        return block

    newline = "\r\n" if any(line.endswith("\r\n") for line in block) else "\n"
    models_index = next((i for i, line in enumerate(block) if re.match(r"^    models\s*:", line)), None)
    if models_index is None:
        block.extend(
            [
                f"    models:{newline}",
                f"      - name: {yaml_quote(ZAI_MODEL)}{newline}",
                f"        alias: {yaml_quote(ZAI_MODEL)}{newline}",
            ]
        )
        return block

    models_line = block[models_index].rstrip("\r\n")
    tail = models_line.split(":", 1)[1]
    value_part, separator, comment = tail.partition("#")
    if value_part.strip():
        comment_suffix = f" # {comment.strip()}" if separator else ""
        block[models_index] = f"    models:{comment_suffix}{newline}"

    model_starts = [
        index
        for index in range(models_index + 1, len(block))
        if re.match(r"^      -(?:\s|$)", block[index])
    ]
    models_end = len(block)
    for index in range(models_index + 1, len(block)):
        if re.match(r"^    [A-Za-z0-9_.-]+\s*:", block[index]):
            models_end = index
            break

    candidate: tuple[int, int] | None = None
    for position, item_start in enumerate(model_starts):
        item_end = model_starts[position + 1] if position + 1 < len(model_starts) else models_end
        item_text = "models:\n" + "".join(block[item_start:item_end])
        try:
            item_value = validate_yaml_text(item_text).get("models", [{}])[0]
        except (ProxyToolError, IndexError, TypeError):
            continue
        if isinstance(item_value, dict) and (
            item_value.get("name") == ZAI_MODEL or item_value.get("alias") == ZAI_MODEL
        ):
            candidate = (item_start, item_end)
            break

    if candidate is not None:
        item_start, item_end = candidate
        name_pattern = re.compile(r"^(\s+-\s+name\s*:)\s*.*?(\s+#.*)?(?:\r?\n)?$")
        alias_pattern = re.compile(r"^(\s+alias\s*:)\s*.*?(\s+#.*)?(?:\r?\n)?$")
        found_name = found_alias = False
        for index in range(item_start, item_end):
            match = name_pattern.match(block[index])
            if match:
                block[index] = f"{match.group(1)} {yaml_quote(ZAI_MODEL)}{match.group(2) or ''}{newline}"
                found_name = True
            match = alias_pattern.match(block[index])
            if match:
                block[index] = f"{match.group(1)} {yaml_quote(ZAI_MODEL)}{match.group(2) or ''}{newline}"
                found_alias = True
        if not found_name:
            block.insert(item_start, f"      - name: {yaml_quote(ZAI_MODEL)}{newline}")
            item_end += 1
        if not found_alias:
            block.insert(item_end, f"        alias: {yaml_quote(ZAI_MODEL)}{newline}")
        return block

    block[models_end:models_end] = [
        f"      - name: {yaml_quote(ZAI_MODEL)}{newline}",
        f"        alias: {yaml_quote(ZAI_MODEL)}{newline}",
    ]
    return block


def _new_owned_entry(api_key: str, newline: str) -> list[str]:
    return [
        f"  - api-key: {yaml_quote(api_key)}{newline}",
        f"    # {OWNED_MARKER}{newline}",
        f"    base-url: {yaml_quote(ZAI_BASE_URL)}{newline}",
        f"    models:{newline}",
        f"      - name: {yaml_quote(ZAI_MODEL)}{newline}",
        f"        alias: {yaml_quote(ZAI_MODEL)}{newline}",
    ]


def upsert_zai_text(text: str, api_key: str) -> str:
    """Return YAML with exactly one marker-owned Z.AI Claude provider entry."""
    validate_yaml_text(text)
    lines = text.splitlines(keepends=True)
    newline = "\r\n" if any(line.endswith("\r\n") for line in lines) else "\n"
    bounds = top_section_bounds(lines, "claude-api-key")
    if bounds is None:
        if lines and not lines[-1].endswith(("\n", "\r")):
            lines[-1] += newline
        if lines and lines[-1].strip():
            lines.append(newline)
        lines.append(f"claude-api-key:{newline}")
        lines.extend(_new_owned_entry(api_key, newline))
        result = "".join(lines)
        validate_yaml_text(result)
        return result

    start, end = bounds
    # Normalize an inline empty sequence so entries can be added beneath it.
    if re.match(r"^claude-api-key\s*:\s*\[\s*\]\s*(?:#.*)?(?:\r?\n)?$", lines[start]):
        comment_match = re.search(r"(\s+#.*?)(?:\r?\n)?$", lines[start])
        lines[start] = f"claude-api-key:{comment_match.group(1) if comment_match else ''}{newline}"
        end = top_section_bounds(lines, "claude-api-key")[1]  # type: ignore[index]
    elif re.match(r"^claude-api-key\s*:\s*\S", lines[start]):
        raise ProxyToolError("claude-api-key must use a block sequence for comment-safe updates")

    ranges = _entry_ranges(lines, start, end)
    owned = [(entry_start, entry_end) for entry_start, entry_end in ranges if OWNED_MARKER in "".join(lines[entry_start:entry_end])]
    if owned:
        first_start, first_end = owned[0]
        block = list(lines[first_start:first_end])
        block = _set_entry_scalar(block, "api-key", api_key)
        block = _set_entry_scalar(block, "base-url", ZAI_BASE_URL)
        block = _ensure_model_mapping(block)
        lines[first_start:first_end] = block
        # Remove additional owned entries from the updated document, back to front.
        bounds = top_section_bounds(lines, "claude-api-key")
        assert bounds is not None
        ranges = _entry_ranges(lines, *bounds)
        duplicate_ranges = [
            item for item in ranges if OWNED_MARKER in "".join(lines[item[0]:item[1]])
        ][1:]
        for duplicate_start, duplicate_end in reversed(duplicate_ranges):
            content_end = duplicate_end
            while content_end > duplicate_start and (
                not lines[content_end - 1].strip()
                or lines[content_end - 1].lstrip().startswith("#")
            ):
                content_end -= 1
            del lines[duplicate_start:content_end]
    else:
        insertion = end
        lines[insertion:insertion] = _new_owned_entry(api_key, newline)

    result = "".join(lines)
    parsed = validate_yaml_text(result)
    entries = parsed.get("claude-api-key")
    if not isinstance(entries, list):
        raise ProxyToolError("claude-api-key must be a list")
    return result


def configure_zai(config_path: Path, api_key: str) -> bool:
    with file_lock(config_path):
        text, _ = read_yaml(config_path)
        updated = upsert_zai_text(text, api_key)
        return write_if_changed(config_path, updated, mode=0o600)


def factory_zai_key(settings_path: Path) -> str | None:
    settings = read_json(settings_path, default={})
    if not isinstance(settings, dict):
        return None
    for entry in settings.get("customModels", []):
        if not isinstance(entry, dict):
            continue
        base_url = str(entry.get("baseUrl", "")).rstrip("/")
        api_key = entry.get("apiKey")
        if base_url == ZAI_BASE_URL and not is_placeholder_secret(api_key):
            return str(api_key)
    return None


def prompt_secret(gum: str) -> str:
    executable = shutil.which(gum)
    if executable:
        completed = subprocess.run(
            [executable, "input", "--password", "--prompt", "Z.AI API key: "],
            check=False,
            text=True,
            capture_output=True,
        )
        if completed.returncode != 0:
            raise ProxyToolError("Z.AI API-key prompt was cancelled")
        return completed.stdout.strip()
    return getpass.getpass("Z.AI API key: ").strip()


def resolve_zai_key(
    *,
    env_name: str,
    env_path: Path,
    settings_path: Path,
    allow_prompt: bool,
    gum: str,
) -> str | None:
    api_key = os.environ.get(env_name, "").strip()
    if not api_key:
        api_key = parse_env_file(env_path).get(env_name, "").strip()
    if not api_key:
        api_key = factory_zai_key(settings_path) or ""
    if not api_key and allow_prompt:
        api_key = prompt_secret(gum)
    return api_key or None


def persist_zai_key(env_path: Path, env_name: str, api_key: str) -> bool:
    with file_lock(env_path):
        current = env_path.read_text(encoding="utf-8") if env_path.exists() else ""
        updated = update_env_text(current, {env_name: api_key})
        return write_if_changed(env_path, updated, mode=0o600)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="provider", required=True)
    zai = subparsers.add_parser("zai", help="configure the Z.AI Anthropic-compatible provider")
    zai.add_argument(
        "--config",
        type=Path,
        default=Path.home() / ".cli-proxy-api" / "config.yaml",
        help="proxy configuration path",
    )
    zai.add_argument(
        "--api-key-env",
        default="ZAI_API_KEY",
        help="environment variable containing the Z.AI API key",
    )
    zai.add_argument(
        "--env-file",
        type=Path,
        default=Path.home() / ".config" / "team-dotfiles" / "proxy.env",
        help="private environment file used to persist the key",
    )
    zai.add_argument(
        "--factory-settings",
        type=Path,
        default=Path.home() / ".factory" / "settings.json",
        help="existing Factory settings used for one-time key migration",
    )
    zai.add_argument(
        "--gum",
        default="gum",
        help="gum executable used for a secure interactive prompt",
    )
    zai.add_argument(
        "--if-available",
        action="store_true",
        help="skip without error when no key can be discovered non-interactively",
    )
    zai.add_argument(
        "--test-mode",
        action="store_true",
        help="use a fixed non-secret placeholder key (intended only for tests)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    api_key = (
        "test-zai-api-key"
        if args.test_mode
        else resolve_zai_key(
            env_name=args.api_key_env,
            env_path=args.env_file.expanduser(),
            settings_path=args.factory_settings.expanduser(),
            allow_prompt=sys.stdin.isatty(),
            gum=args.gum,
        )
    )
    if not api_key:
        if args.if_available:
            print("Z.AI provider not configured: no API key is available.")
            return 0
        print(f"ERROR: {args.api_key_env} is not set", file=sys.stderr)
        return 1
    try:
        changed = configure_zai(args.config.expanduser(), api_key)
        env_changed = persist_zai_key(
            args.env_file.expanduser(), args.api_key_env, api_key
        )
    except ProxyToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(
        "Z.AI provider configuration "
        f"{'updated' if changed else 'already current'}; "
        f"private environment {'updated' if env_changed else 'already current'}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
