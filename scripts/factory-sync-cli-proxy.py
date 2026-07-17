#!/usr/bin/env python3
"""Synchronize selected cli-proxy-api models into Factory settings."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any, Iterable, Mapping, Sequence
from urllib.error import HTTPError, URLError
from urllib.request import build_opener, ProxyHandler, Request

from cli_proxy_common import (
    ProxyToolError,
    atomic_write,
    file_lock,
    first_real_secret,
    json_text,
    parse_env_file,
    read_json,
    read_yaml,
    write_if_changed,
)

CURATED_MODELS = ("gpt-5.5", "gpt-5.4", "gpt-5.3-codex-spark", "gpt-5.6-sol", "glm-5.2")
DISPLAY_OVERRIDES = {
    "gpt-5.5": "gpt-5.5",
    "gpt-5.4": "gpt-5.4",
    "gpt-5.3-codex-spark": "GPT-5.3 Codex Spark",
    "gpt-5.6-sol": "GPT-5.6 SOL",
    "glm-5.2": "GLM-5.2",
}
REFERENCE_KEYS = (
    "modelFavorites",
    "missionOrchestratorModel",
    "missionModelSettings",
    "subagentModelSettings",
    "sessionDefaultSettings",
)
UNSUPPORTED_MODEL = re.compile(
    r"(?:^|[-_/.])(?:embedding|embeddings|embed|image|images|dall-e|imagen|"
    r"moderation|internal|auto[-_]?review|realtime|audio|tts|whisper|"
    r"transcri(?:be|ption)|video)(?:$|[-_/.])",
    re.IGNORECASE,
)
urlopen = build_opener(ProxyHandler({})).open


@dataclass(frozen=True)
class CatalogModel:
    model: str
    owned_by: str = ""
    display_name: str = ""


def provider_for(model: CatalogModel) -> str:
    owner = model.owned_by.lower()
    if owner in {"anthropic", "claude"} or "anthropic" in owner or "claude" in owner:
        return "anthropic"
    if owner == "openai" or "openai" in owner:
        return "openai"
    if model.model.lower().startswith("claude-") or model.model.lower().startswith("glm-"):
        return "anthropic"
    return "openai"


def filter_catalog(payload: Any) -> list[CatalogModel]:
    """Normalize and filter an OpenAI-compatible models response or fixture."""
    raw_models = payload.get("data", []) if isinstance(payload, dict) else payload
    if not isinstance(raw_models, list):
        raise ProxyToolError("Models response must contain a data list")
    result: dict[str, CatalogModel] = {}
    for raw in raw_models:
        if isinstance(raw, str):
            model_id, owner, display_name = raw, "", ""
        elif isinstance(raw, dict):
            model_id = raw.get("id") or raw.get("model") or raw.get("name")
            owner = raw.get("owned_by") or raw.get("ownedBy") or raw.get("provider") or ""
            display_name = raw.get("display_name") or raw.get("displayName") or ""
        else:
            continue
        if not isinstance(model_id, str) or not model_id.strip():
            continue
        model_id = model_id.strip()
        if UNSUPPORTED_MODEL.search(model_id):
            continue
        if isinstance(owner, str) and owner.lower() in {"internal", "system"}:
            continue
        result[model_id] = CatalogModel(
            model=model_id,
            owned_by=str(owner),
            display_name=str(display_name),
        )
    return sorted(result.values(), key=lambda item: (item.model.casefold(), item.model))


def load_models_file(path: Path) -> list[CatalogModel]:
    if str(path) == "-":
        try:
            payload = json.load(sys.stdin)
        except json.JSONDecodeError as exc:
            raise ProxyToolError("Models fixture is not valid JSON") from exc
    else:
        payload = read_json(path)
    return filter_catalog(payload)


def _get_json(url: str, api_key: str, timeout: float) -> Any:
    request = Request(
        url,
        headers={"Authorization": f"Bearer {api_key}", "Accept": "application/json"},
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except HTTPError as exc:
        raise ProxyToolError(f"Proxy request failed with HTTP status {exc.code}: {url}") from exc
    except (URLError, OSError, json.JSONDecodeError) as exc:
        raise ProxyToolError(f"Proxy request failed: {url}") from exc


def fetch_catalog(base_url: str, api_key: str, timeout: float = 5.0) -> list[CatalogModel]:
    api_root = base_url.rstrip("/")
    health_root = re.sub(r"/v1$", "", api_root)
    health_url = f"{health_root}/healthz"
    health_request = Request(health_url, headers={"Accept": "application/json"})
    try:
        with urlopen(health_request, timeout=timeout) as response:
            if not 200 <= response.status < 300:
                raise ProxyToolError(f"Proxy health check failed with HTTP status {response.status}")
    except HTTPError as exc:
        raise ProxyToolError(f"Proxy health check failed with HTTP status {exc.code}") from exc
    except (URLError, OSError) as exc:
        raise ProxyToolError("Proxy health check failed") from exc
    return filter_catalog(_get_json(f"{api_root}/models", api_key, timeout))


def stable_model_id(model_name: str, occupied_ids: set[str] | None = None) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", model_name).strip("-").lower() or "model"
    preferred = f"custom:{slug}-0"
    if not occupied_ids or preferred not in occupied_ids:
        return preferred
    fallback = f"custom:{slug}-cli-proxy-0"
    if fallback not in occupied_ids:
        return fallback
    suffix = 1
    while f"custom:{slug}-cli-proxy-{suffix}" in occupied_ids:
        suffix += 1
    return f"custom:{slug}-cli-proxy-{suffix}"


def default_display_name(model: CatalogModel) -> str:
    return DISPLAY_OVERRIDES.get(model.model, model.display_name or model.model)


def default_extra_args(model: CatalogModel) -> dict[str, Any]:
    effort = "low" if model.model == "gpt-5.5" else "high"
    if provider_for(model) == "anthropic":
        return {"effort": effort, "thinking": {"type": "adaptive"}}
    return {"reasoning": {"effort": effort}}


def make_entry(
    model: CatalogModel,
    *,
    model_id: str,
    base_url: str,
    api_key: str,
    existing: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "model": model.model,
        "id": model_id,
        "index": 0,
        "baseUrl": base_url.rstrip("/"),
        "apiKey": api_key,
        "displayName": default_display_name(model),
        "enableThinking": True,
        "noImageSupport": False,
        "provider": provider_for(model),
        "extraArgs": default_extra_args(model),
    }
    if existing:
        if isinstance(existing.get("displayName"), str):
            entry["displayName"] = existing["displayName"]
        if isinstance(existing.get("extraArgs"), dict):
            entry["extraArgs"] = existing["extraArgs"]
    return entry


def load_state(path: Path) -> dict[str, Any]:
    state = read_json(path, default={})
    if not isinstance(state, dict):
        raise ProxyToolError(f"Selection state must contain a JSON object: {path}")
    return state


def initial_selection(catalog: Sequence[CatalogModel]) -> list[str]:
    available = {item.model for item in catalog}
    return [model for model in CURATED_MODELS if model in available]


def state_selection(state: Mapping[str, Any], catalog: Sequence[CatalogModel]) -> list[str] | None:
    selected = state.get("selectedModels")
    if not isinstance(selected, list):
        return None
    available = {item.model for item in catalog}
    return [item for item in selected if isinstance(item, str) and item in available]


def parse_requested_models(values: Sequence[str] | None) -> list[str] | None:
    if not values:
        return None
    result: list[str] = []
    for value in values:
        for model in value.split(","):
            model = model.strip()
            if model and model not in result:
                result.append(model)
    return result


def validate_selection(selected: Iterable[str], catalog: Sequence[CatalogModel]) -> list[str]:
    available = {item.model for item in catalog}
    result: list[str] = []
    missing: list[str] = []
    for model in selected:
        if model not in available:
            missing.append(model)
        elif model not in result:
            result.append(model)
    if missing:
        raise ProxyToolError("Requested models are unavailable: " + ", ".join(sorted(missing)))
    return result


def gum_select(catalog: Sequence[CatalogModel], preselected: Sequence[str], gum: str = "gum") -> list[str]:
    executable = shutil.which(gum)
    if executable is None:
        raise ProxyToolError("gum is required for interactive selection; use --non-interactive or --models")
    command = [executable, "choose", "--no-limit", "--height", str(min(max(len(catalog), 5), 25))]
    for model in preselected:
        command.extend(["--selected", model])
    command.extend(item.model for item in catalog)
    try:
        completed = subprocess.run(command, check=False, text=True, capture_output=True)
    except OSError as exc:
        raise ProxyToolError("Unable to run gum model selection") from exc
    if completed.returncode != 0:
        raise ProxyToolError("Model selection was cancelled")
    selected = [line for line in completed.stdout.splitlines() if line]
    return validate_selection(selected, catalog)


def confirm_selection(selected: Sequence[str], *, yes: bool, non_interactive: bool) -> None:
    if yes:
        return
    if non_interactive or not sys.stdin.isatty():
        raise ProxyToolError("Refusing to update settings without --yes in non-interactive mode")
    answer = input(f"Write {len(selected)} selected proxy model(s) to Factory settings? [y/N] ")
    if answer.strip().lower() not in {"y", "yes"}:
        raise ProxyToolError("Update cancelled")


def _walk_references(value: Any, path: str, ids: set[str], found: dict[str, list[str]]) -> None:
    if isinstance(value, str) and value in ids:
        found.setdefault(value, []).append(path)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _walk_references(item, f"{path}[{index}]", ids, found)
    elif isinstance(value, dict):
        for key, item in value.items():
            _walk_references(item, f"{path}.{key}", ids, found)


def find_model_references(settings: Mapping[str, Any], ids: set[str]) -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for key in REFERENCE_KEYS:
        if key in settings:
            _walk_references(settings[key], key, ids, found)
    return found


def _looks_like_legacy_managed(entry: Any, base_url: str, api_key: str) -> bool:
    if not isinstance(entry, dict):
        return False
    model = entry.get("model")
    model_id = entry.get("id")
    return (
        isinstance(model, str)
        and isinstance(model_id, str)
        and model in CURATED_MODELS
        and entry.get("baseUrl", "").rstrip("/") == base_url.rstrip("/")
        and entry.get("apiKey") == api_key
        and model_id == stable_model_id(model)
    )


def merge_settings(
    settings: Mapping[str, Any],
    *,
    selected: Sequence[CatalogModel],
    base_url: str,
    api_key: str,
    previous_managed_ids: set[str],
    adopt_legacy: bool = False,
) -> tuple[dict[str, Any], list[str]]:
    """Replace only managed proxy models and preserve every unrelated setting/model."""
    merged = dict(settings)
    raw_custom = settings.get("customModels", [])
    if raw_custom is None:
        raw_custom = []
    if not isinstance(raw_custom, list):
        raise ProxyToolError("Factory customModels must be a list")

    managed_ids = set(previous_managed_ids)
    if adopt_legacy:
        managed_ids.update(
            entry["id"]
            for entry in raw_custom
            if _looks_like_legacy_managed(entry, base_url, api_key)
        )
    existing_managed = {
        entry.get("model"): entry
        for entry in raw_custom
        if isinstance(entry, dict) and entry.get("id") in managed_ids and isinstance(entry.get("model"), str)
    }
    preserved = [
        dict(entry) if isinstance(entry, dict) else entry
        for entry in raw_custom
        if not (isinstance(entry, dict) and entry.get("id") in managed_ids)
    ]
    occupied_ids = {
        entry.get("id") for entry in preserved if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    }

    generated: list[dict[str, Any]] = []
    new_ids: list[str] = []
    for model in sorted(selected, key=lambda item: (item.model.casefold(), item.model)):
        old_entry = existing_managed.get(model.model)
        old_id = old_entry.get("id") if isinstance(old_entry, dict) else None
        if isinstance(old_id, str) and old_id not in occupied_ids:
            model_id = old_id
        else:
            model_id = stable_model_id(model.model, occupied_ids | set(new_ids))
        generated.append(
            make_entry(
                model,
                model_id=model_id,
                base_url=base_url,
                api_key=api_key,
                existing=old_entry,
            )
        )
        new_ids.append(model_id)

    removals = managed_ids - set(new_ids)
    references = find_model_references(settings, removals)
    if references:
        details = "; ".join(
            f"{model_id} at {', '.join(paths)}" for model_id, paths in sorted(references.items())
        )
        raise ProxyToolError(f"Refusing to remove referenced proxy model(s): {details}")

    custom_models = preserved + generated
    for index, entry in enumerate(custom_models):
        if isinstance(entry, dict):
            entry["index"] = index
    merged["customModels"] = custom_models
    return merged, new_ids


def resolve_proxy_details(config_path: Path, env_path: Path) -> tuple[str, str]:
    _, config = read_yaml(config_path)
    port = config.get("port", 8317)
    if not isinstance(port, int):
        raise ProxyToolError("Proxy port must be an integer")
    base_url = f"http://127.0.0.1:{port}/v1"
    api_key = os.environ.get("CLI_PROXY_API_KEY")
    if not api_key:
        api_key = parse_env_file(env_path).get("CLI_PROXY_API_KEY")
    if not api_key:
        api_key = first_real_secret(config.get("api-keys"))
    if not api_key:
        raise ProxyToolError("No cli-proxy API key is configured")
    return base_url, api_key


def file_signature(path: Path) -> tuple[int, int, str] | None:
    if not path.exists():
        return None
    try:
        payload = path.read_bytes()
        stat_result = path.stat()
    except OSError as exc:
        raise ProxyToolError(f"Unable to inspect file before update: {path}") from exc
    return (
        stat_result.st_mtime_ns,
        stat_result.st_size,
        hashlib.sha256(payload).hexdigest(),
    )


def synchronize(
    *,
    settings_path: Path,
    state_path: Path,
    catalog: Sequence[CatalogModel],
    selected_names: Sequence[str],
    base_url: str,
    api_key: str,
) -> tuple[bool, bool, int]:
    selected_map = {item.model: item for item in catalog}
    selected = [selected_map[name] for name in selected_names]
    with file_lock(settings_path), file_lock(state_path):
        settings_signature = file_signature(settings_path)
        state_signature = file_signature(state_path)
        settings_existed = settings_path.exists()
        settings_original = (
            settings_path.read_text(encoding="utf-8") if settings_existed else ""
        )
        state_existed = state_path.exists()
        state_original = state_path.read_text(encoding="utf-8") if state_existed else ""
        state = load_state(state_path)
        previous_ids = {
            item for item in state.get("managedModelIds", []) if isinstance(item, str)
        } if isinstance(state.get("managedModelIds", []), list) else set()
        settings = read_json(settings_path, default={})
        if not isinstance(settings, dict):
            raise ProxyToolError("Factory settings must contain a JSON object")
        merged, managed_ids = merge_settings(
            settings,
            selected=selected,
            base_url=base_url,
            api_key=api_key,
            previous_managed_ids=previous_ids,
            adopt_legacy=not bool(state),
        )
        new_state = {
            "version": 1,
            "selectedModels": list(selected_names),
            "managedModelIds": managed_ids,
        }
        settings_payload = json_text(merged)
        state_payload = json_text(new_state)
        if file_signature(settings_path) != settings_signature:
            raise ProxyToolError("Factory settings changed during synchronization; retry")
        if file_signature(state_path) != state_signature:
            raise ProxyToolError("Factory model state changed during synchronization; retry")

        state_changed = write_if_changed(
            state_path,
            state_payload,
            mode=0o600,
            expected_content=state_original if state_existed else None,
        )
        settings_write_started = False
        try:
            if file_signature(settings_path) != settings_signature:
                raise ProxyToolError("Factory settings changed during synchronization; retry")
            settings_write_started = True
            settings_changed = write_if_changed(
                settings_path,
                settings_payload,
                mode=0o600,
                expected_content=settings_original if settings_existed else None,
            )
        except Exception:
            if settings_write_started:
                try:
                    if settings_existed:
                        atomic_write(
                            settings_path,
                            settings_original,
                            mode=0o600,
                            expected_content=settings_payload,
                        )
                    elif (
                        settings_path.exists()
                        and settings_path.read_text(encoding="utf-8")
                        == settings_payload
                    ):
                        settings_path.unlink()
                except (OSError, ProxyToolError):
                    pass
            if state_changed:
                try:
                    if state_existed:
                        atomic_write(
                            state_path,
                            state_original,
                            mode=0o600,
                            expected_content=state_payload,
                        )
                    elif (
                        state_path.exists()
                        and state_path.read_text(encoding="utf-8") == state_payload
                    ):
                        state_path.unlink()
                except (OSError, ProxyToolError):
                    pass
            raise
        return settings_changed, state_changed, len(managed_ids)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("legacy_config", nargs="?", type=Path, help=argparse.SUPPRESS)
    parser.add_argument(
        "--config", type=Path, default=None, help="proxy configuration path"
    )
    parser.add_argument(
        "--env-file",
        type=Path,
        default=Path.home() / ".config" / "team-dotfiles" / "proxy.env",
        help="private proxy environment file",
    )
    parser.add_argument(
        "--settings",
        type=Path,
        default=Path.home() / ".factory" / "settings.json",
        help="Factory settings path",
    )
    parser.add_argument(
        "--state",
        type=Path,
        default=Path.home() / ".cli-proxy-api" / "factory-models.json",
        help="managed selection state path",
    )
    parser.add_argument("--models", action="append", help="comma-separated model IDs to select")
    parser.add_argument("--models-file", type=Path, help="JSON models response fixture; skips network checks")
    parser.add_argument("--non-interactive", action="store_true", help="reuse state/curated defaults without gum")
    parser.add_argument("--yes", action="store_true", help="confirm settings mutation")
    parser.add_argument("--gum", default="gum", help="gum executable name or path")
    parser.add_argument("--timeout", type=float, default=5.0, help="proxy request timeout in seconds")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    config_path = (args.config or args.legacy_config or Path.home() / ".cli-proxy-api" / "config.yaml").expanduser()
    try:
        base_url, api_key = resolve_proxy_details(config_path, args.env_file.expanduser())
        catalog = (
            load_models_file(args.models_file.expanduser())
            if args.models_file
            else fetch_catalog(base_url, api_key, args.timeout)
        )
        if not catalog:
            raise ProxyToolError("No supported proxy models are available")
        state = load_state(args.state.expanduser())
        requested = parse_requested_models(args.models)
        if requested is not None:
            selected_names = validate_selection(requested, catalog)
        else:
            preselected = state_selection(state, catalog)
            if preselected is None:
                preselected = initial_selection(catalog)
            if args.non_interactive:
                selected_names = preselected
            else:
                selected_names = gum_select(catalog, preselected, args.gum)
        confirm_selection(selected_names, yes=args.yes, non_interactive=args.non_interactive)
        settings_changed, state_changed, count = synchronize(
            settings_path=args.settings.expanduser(),
            state_path=args.state.expanduser(),
            catalog=catalog,
            selected_names=selected_names,
            base_url=base_url,
            api_key=api_key,
        )
    except ProxyToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(
        f"Factory proxy model sync complete: {count} managed model(s); "
        f"settings {'updated' if settings_changed else 'unchanged'}, "
        f"state {'updated' if state_changed else 'unchanged'}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
