#!/usr/bin/env python3
"""Shared, secret-safe file and YAML helpers for cli-proxy tooling."""

from __future__ import annotations

import contextlib
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import sys
import tempfile
from typing import Any, Iterator, Mapping

try:
    import yaml
except ImportError:  # pragma: no cover - exercised by command-line environments
    yaml = None


class ProxyToolError(RuntimeError):
    """An expected, user-facing tooling error."""


_EXPECTED_UNSET = object()
BACKUP_RETENTION_COUNT = 3
_BACKUP_TIMESTAMP_PATTERN = re.compile(r"^\d{8}T\d{6}\.\d{6}Z$")


if yaml is not None:
    class _UniqueKeyLoader(yaml.SafeLoader):
        pass


    def _construct_unique_mapping(loader: Any, node: Any, deep: bool = False) -> Any:
        loader.flatten_mapping(node)
        mapping: dict[Any, Any] = {}
        for key_node, value_node in node.value:
            key = loader.construct_object(key_node, deep=deep)
            try:
                duplicate = key in mapping
            except TypeError as exc:
                raise ValueError("YAML mapping key is not hashable") from exc
            if duplicate:
                raise ValueError("YAML contains duplicate mapping keys")
            mapping[key] = loader.construct_object(value_node, deep=deep)
        return mapping


    _UniqueKeyLoader.add_constructor(
        yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
        _construct_unique_mapping,
    )


def require_yaml() -> None:
    if yaml is None:
        raise ProxyToolError("PyYAML is required (install the python-yaml/pyyaml package)")


def validate_yaml_text(text: str) -> dict[str, Any]:
    """Parse YAML without ever including potentially secret input in errors."""
    require_yaml()
    try:
        value = yaml.load(text, Loader=_UniqueKeyLoader)  # type: ignore[union-attr]
    except Exception as exc:
        raise ProxyToolError("YAML validation failed") from exc
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ProxyToolError("YAML configuration must contain a top-level mapping")
    return value


def read_yaml(path: Path) -> tuple[str, dict[str, Any]]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ProxyToolError(f"Unable to read YAML file: {path}") from exc
    return text, validate_yaml_text(text)


def read_json(path: Path, *, default: Any = None) -> Any:
    if not path.exists() and default is not None:
        return default
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise ProxyToolError(f"Unable to read valid JSON file: {path}") from exc


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def atomic_write(
    path: Path,
    content: str,
    *,
    mode: int = 0o600,
    expected_content: str | None | object = _EXPECTED_UNSET,
) -> None:
    """Atomically replace a file, fsyncing data and enforcing its final mode."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        if expected_content is not _EXPECTED_UNSET:
            try:
                current = path.read_text(encoding="utf-8") if path.exists() else None
            except OSError as exc:
                raise ProxyToolError(
                    f"Unable to verify file before atomic update: {path}"
                ) from exc
            if current != expected_content:
                raise ProxyToolError(f"File changed during update; retry: {path}")
        os.replace(temporary_path, path)
        os.chmod(path, mode)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except Exception:
        with contextlib.suppress(FileNotFoundError):
            temporary_path.unlink()
        raise


def backup_file(path: Path) -> Path | None:
    """Create a timestamped, private backup immediately before a mutation."""
    if not path.exists():
        return None
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    backup = path.with_name(f"{path.name}.bak.{stamp}")
    try:
        shutil.copy2(path, backup)
        os.chmod(backup, 0o600)
    except OSError as exc:
        raise ProxyToolError(f"Unable to back up file: {path}") from exc
    return backup


def prune_generated_backups(
    path: Path, *, retain: int = BACKUP_RETENTION_COUNT
) -> None:
    """Retain only the newest generated regular-file backups for one target."""
    prefix = f"{path.name}.bak."
    backups: list[Path] = []
    try:
        entries = path.parent.iterdir()
        for candidate in entries:
            name = candidate.name
            if not name.startswith(prefix):
                continue
            stamp = name[len(prefix):]
            if not _BACKUP_TIMESTAMP_PATTERN.fullmatch(stamp):
                continue
            if candidate.is_symlink() or not candidate.is_file():
                continue
            backups.append(candidate)
        backups.sort(key=lambda candidate: candidate.name, reverse=True)
        for stale in backups[max(retain, 0):]:
            stale.unlink()
    except OSError as exc:
        raise ProxyToolError(f"Unable to prune backups for file: {path}") from exc


def write_if_changed(
    path: Path,
    content: str,
    *,
    mode: int = 0o600,
    backup: bool = True,
    expected_content: str | None | object = _EXPECTED_UNSET,
) -> bool:
    current: str | None = None
    if path.exists():
        try:
            current = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise ProxyToolError(f"Unable to read file before update: {path}") from exc
    if expected_content is not _EXPECTED_UNSET and current != expected_content:
        raise ProxyToolError(f"File changed during update; retry: {path}")
    changed = current != content
    if changed:
        if backup:
            backup_file(path)
        atomic_write(
            path,
            content,
            mode=mode,
            expected_content=expected_content,
        )
        if backup:
            try:
                prune_generated_backups(path)
            except ProxyToolError:
                print(
                    "WARNING: unable to prune generated backups after successful update.",
                    file=sys.stderr,
                )
    elif path.exists():
        os.chmod(path, mode)
    else:
        atomic_write(
            path,
            content,
            mode=mode,
            expected_content=expected_content,
        )
    return changed


@contextlib.contextmanager
def file_lock(target: Path) -> Iterator[None]:
    """Serialize mutations associated with target using a sibling advisory lock."""
    target.parent.mkdir(parents=True, exist_ok=True)
    lock_path = target.with_name(f".{target.name}.lock")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def yaml_quote(value: str) -> str:
    """JSON strings are valid YAML double-quoted scalars."""
    return json.dumps(value, ensure_ascii=False)


def _lines(text: str) -> list[str]:
    return text.splitlines(keepends=True)


def _newline_for(lines: list[str]) -> str:
    return "\r\n" if any(line.endswith("\r\n") for line in lines) else "\n"


def top_section_bounds(lines: list[str], key: str) -> tuple[int, int] | None:
    pattern = re.compile(rf"^{re.escape(key)}\s*:")
    start = next((index for index, line in enumerate(lines) if pattern.match(line)), None)
    if start is None:
        return None
    top_key = re.compile(r"^[A-Za-z0-9_.-]+\s*:")
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if top_key.match(lines[index]):
            end = index
            break
    return start, end


def replace_top_scalar(text: str, key: str, value: str) -> str:
    lines = _lines(text)
    newline = _newline_for(lines)
    pattern = re.compile(rf"^({re.escape(key)}\s*:)\s*.*?(\s+#.*)?(?:\r?\n)?$")
    for index, line in enumerate(lines):
        match = pattern.match(line)
        if match:
            comment = match.group(2) or ""
            lines[index] = f"{match.group(1)} {yaml_quote(value)}{comment}{newline}"
            return "".join(lines)
    prefix = "" if not text or text.endswith(("\n", "\r")) else newline
    return text + prefix + f"{key}: {yaml_quote(value)}{newline}"


def replace_top_sequence(text: str, key: str, values: list[str]) -> str:
    lines = _lines(text)
    newline = _newline_for(lines)
    bounds = top_section_bounds(lines, key)
    items = [f"  - {yaml_quote(value)}{newline}" for value in values]
    if bounds is None:
        prefix = "" if not text or text.endswith(("\n", "\r")) else newline
        return text + prefix + f"{key}:{newline}" + "".join(items)
    start, end = bounds
    key_line = lines[start].rstrip("\r\n")
    tail = key_line.split(":", 1)[1]
    value_part, separator, comment = tail.partition("#")
    if value_part.strip():
        comment_suffix = f" # {comment.strip()}" if separator else ""
        lines[start] = f"{key}:{comment_suffix}{newline}"
        bounds = top_section_bounds(lines, key)
        assert bounds is not None
        start, end = bounds
    item_indices = [
        index for index in range(start + 1, end) if re.match(r"^\s+-\s+", lines[index])
    ]
    if item_indices:
        first = item_indices[0]
        lines[first] = items[0]
        for index in reversed(item_indices[1:]):
            del lines[index]
        if len(items) > 1:
            lines[first + 1 : first + 1] = items[1:]
    else:
        lines[start + 1 : start + 1] = items
    return "".join(lines)


def replace_nested_scalar(text: str, section: str, key: str, value: str) -> str:
    lines = _lines(text)
    newline = _newline_for(lines)
    bounds = top_section_bounds(lines, section)
    if bounds is None:
        prefix = "" if not text or text.endswith(("\n", "\r")) else newline
        return text + prefix + f"{section}:{newline}  {key}: {yaml_quote(value)}{newline}"
    start, end = bounds
    pattern = re.compile(rf"^(\s+{re.escape(key)}\s*:)\s*.*?(\s+#.*)?(?:\r?\n)?$")
    for index in range(start + 1, end):
        match = pattern.match(lines[index])
        if match:
            comment = match.group(2) or ""
            lines[index] = f"{match.group(1)} {yaml_quote(value)}{comment}{newline}"
            return "".join(lines)
    lines[start + 1 : start + 1] = [f"  {key}: {yaml_quote(value)}{newline}"]
    return "".join(lines)


def is_placeholder_secret(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return True
    normalized = value.strip().lower()
    markers = ("your-api-key", "example", "replace-me", "changeme", "********")
    return any(marker in normalized for marker in markers)


def first_real_secret(values: Any) -> str | None:
    if not isinstance(values, list):
        return None
    for value in values:
        if not is_placeholder_secret(value):
            return str(value)
    return None


def parse_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    result: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ProxyToolError(f"Unable to read environment file: {path}") from exc
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        try:
            parsed = shlex.split(value, comments=False, posix=True)
        except ValueError:
            parsed = []
        result[key] = parsed[0] if len(parsed) == 1 else value
    return result


def update_env_text(existing: str, updates: Mapping[str, str]) -> str:
    """Update shell env assignments while preserving unrelated lines."""
    lines = existing.splitlines()
    remaining = dict(updates)
    replaced: set[str] = set()
    assignment = re.compile(r"^(\s*(?:export\s+)?)([A-Za-z_][A-Za-z0-9_]*)=")
    output: list[str] = []
    for line in lines:
        match = assignment.match(line)
        if match and match.group(2) in updates:
            key = match.group(2)
            if key not in replaced:
                output.append(f"export {key}={shlex.quote(updates[key])}")
                replaced.add(key)
                remaining.pop(key, None)
        else:
            output.append(line)
    for key, value in remaining.items():
        output.append(f"export {key}={shlex.quote(value)}")
    return "\n".join(output).rstrip("\n") + "\n"
