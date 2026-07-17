#!/usr/bin/env bash
# link.sh - GNU Stow helper for symlinking dotfiles into $HOME.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STOW_REGULAR_CONFLICTS=()
STOW_UNSAFE_CONFLICTS=()
declare -A STOW_BACKUPS=()

_append_unique_path() {
  local array_name="$1"
  local candidate="$2"
  local existing

  case "$array_name" in
    STOW_REGULAR_CONFLICTS)
      for existing in "${STOW_REGULAR_CONFLICTS[@]}"; do
        [[ "$existing" == "$candidate" ]] && return 0
      done
      STOW_REGULAR_CONFLICTS+=("$candidate")
      ;;
    STOW_UNSAFE_CONFLICTS)
      for existing in "${STOW_UNSAFE_CONFLICTS[@]}"; do
        [[ "$existing" == "$candidate" ]] && return 0
      done
      STOW_UNSAFE_CONFLICTS+=("$candidate")
      ;;
    *)
      echo "ERROR: unknown conflict list '$array_name'." >&2
      return 1
      ;;
  esac
}

_collect_stow_conflicts() {
  local packages=("$@")
  local stow_dir="$REPO_ROOT/stow"
  local pkg package_dir source relative target parent
  local old_dotglob old_globstar old_nullglob
  local sources=()

  STOW_REGULAR_CONFLICTS=()
  STOW_UNSAFE_CONFLICTS=()

  old_dotglob=$(shopt -p dotglob || true)
  old_globstar=$(shopt -p globstar || true)
  old_nullglob=$(shopt -p nullglob || true)
  shopt -s dotglob globstar nullglob

  for pkg in "${packages[@]}"; do
    package_dir="$stow_dir/$pkg"
    if [[ ! -d "$package_dir" ]]; then
      echo "ERROR: stow package '$pkg' not found in $stow_dir" >&2
      eval "$old_dotglob"; eval "$old_globstar"; eval "$old_nullglob"
      return 1
    fi

    sources=("$package_dir"/**)
    for source in "${sources[@]}"; do
      if [[ -d "$source" && ! -L "$source" ]]; then
        continue
      fi

      relative="${source#"$package_dir"/}"
      if [[ "$relative" == "$source" || -z "$relative" || "$relative" == /* || "$relative" == *../* ]]; then
        echo "ERROR: unsafe path in stow package '$pkg': $source" >&2
        eval "$old_dotglob"; eval "$old_globstar"; eval "$old_nullglob"
        return 1
      fi
      target="$HOME/$relative"

      parent=$(dirname "$target")
      while [[ "$parent" != "$HOME" && "$parent" == "$HOME"/* ]]; do
        if [[ -e "$parent" || -L "$parent" ]]; then
          if [[ -L "$parent" ]]; then
            # Never migrate through a symlinked directory: a lexical HOME path
            # could otherwise move a file located outside HOME.
            _append_unique_path STOW_UNSAFE_CONFLICTS "$parent"
            break
          elif [[ -f "$parent" ]]; then
            _append_unique_path STOW_REGULAR_CONFLICTS "$parent"
            break
          elif [[ ! -d "$parent" ]]; then
            _append_unique_path STOW_UNSAFE_CONFLICTS "$parent"
            break
          fi
        fi
        parent=$(dirname "$parent")
      done

      if [[ -e "$target" || -L "$target" ]]; then
        if [[ -L "$target" ]]; then
          if [[ ! "$target" -ef "$source" ]]; then
            _append_unique_path STOW_UNSAFE_CONFLICTS "$target"
          fi
        elif [[ -f "$target" ]]; then
          _append_unique_path STOW_REGULAR_CONFLICTS "$target"
        else
          _append_unique_path STOW_UNSAFE_CONFLICTS "$target"
        fi
      fi
    done
  done

  eval "$old_dotglob"; eval "$old_globstar"; eval "$old_nullglob"
}

preflight_stow_packages() {
  local migrate_existing="$1"; shift
  local packages=("$@")
  local conflict

  _collect_stow_conflicts "${packages[@]}" || return 1

  if [[ ${#STOW_UNSAFE_CONFLICTS[@]} -gt 0 ]]; then
    echo "ERROR: Stow found conflicts that migration will not modify:" >&2
    for conflict in "${STOW_UNSAFE_CONFLICTS[@]}"; do
      printf '  %s\n' "$conflict" >&2
    done
    echo "Resolve these symlink, directory, or special-file conflicts manually." >&2
    return 1
  fi

  if [[ ${#STOW_REGULAR_CONFLICTS[@]} -gt 0 ]]; then
    if [[ "$migrate_existing" != true ]]; then
      echo "ERROR: existing managed files conflict with the dotfiles packages:" >&2
      for conflict in "${STOW_REGULAR_CONFLICTS[@]}"; do
        printf '  %s\n' "$conflict" >&2
      done
      echo "Re-run with --migrate-existing to create timestamped backups, or resolve them manually." >&2
      return 1
    fi

    echo "Migration will back up these existing managed files:"
    for conflict in "${STOW_REGULAR_CONFLICTS[@]}"; do
      printf '  %s\n' "$conflict"
    done
  fi
}

_backup_stow_conflicts() {
  local timestamp conflict backup

  STOW_BACKUPS=()
  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  for conflict in "${STOW_REGULAR_CONFLICTS[@]}"; do
    if [[ ! -f "$conflict" || -L "$conflict" ]]; then
      echo "ERROR: conflict changed after preflight; refusing to move $conflict" >&2
      return 1
    fi
    backup="$conflict.bak.$timestamp"
    if [[ -e "$backup" || -L "$backup" ]]; then
      echo "ERROR: backup path already exists: $backup" >&2
      return 1
    fi
  done

  for conflict in "${STOW_REGULAR_CONFLICTS[@]}"; do
    backup="$conflict.bak.$timestamp"
    printf 'Backing up existing file: %s -> %s\n' "$conflict" "$backup"
    if ! mv -- "$conflict" "$backup"; then
      _restore_stow_conflicts
      return 1
    fi
    STOW_BACKUPS["$conflict"]="$backup"
  done
}

_restore_stow_conflicts() {
  local conflict backup
  local status=0

  for conflict in "${!STOW_BACKUPS[@]}"; do
    backup="${STOW_BACKUPS[$conflict]}"

    if [[ -L "$conflict" ]]; then
      rm -- "$conflict" || {
        echo "ERROR: failed to remove partial Stow link: $conflict" >&2
        status=1
        continue
      }
    elif [[ -e "$conflict" ]]; then
      echo "ERROR: refusing to overwrite path while restoring backup: $conflict" >&2
      status=1
      continue
    fi

    if [[ -f "$backup" ]]; then
      printf 'Restoring existing file: %s -> %s\n' "$backup" "$conflict" >&2
      mv -- "$backup" "$conflict" || status=1
    fi
  done

  STOW_BACKUPS=()
  return "$status"
}

_run_stow() {
  local simulate="$1"; shift
  local packages=("$@")
  local stow_dir="$REPO_ROOT/stow"
  local status
  local args=(--dir="$stow_dir" --target="$HOME" --no-folding --verbose=1)

  if [[ "$simulate" == true ]]; then
    args+=(--simulate)
  fi

  if stow "${args[@]}" -R "${packages[@]}" 2>&1; then
    return 0
  else
    status=$?
    if [[ "$simulate" == true ]]; then
      echo "ERROR: GNU Stow preflight failed; no links were changed." >&2
    else
      echo "ERROR: GNU Stow failed while linking packages." >&2
    fi
    return "$status"
  fi
}

# link_stow_packages [--migrate-existing] <package> [package ...]
link_stow_packages() {
  local migrate_existing=false
  local packages=()
  local status

  if [[ "${1:-}" == "--migrate-existing" ]]; then
    migrate_existing=true
    shift
  fi
  packages=("$@")

  if ! command -v stow >/dev/null 2>&1; then
    echo "ERROR: GNU Stow is not installed. Install it first." >&2
    return 1
  fi
  if [[ ${#packages[@]} -eq 0 ]]; then
    echo "ERROR: no Stow packages were specified." >&2
    return 1
  fi

  preflight_stow_packages "$migrate_existing" "${packages[@]}" || return 1

  if [[ "$migrate_existing" == true && ${#STOW_REGULAR_CONFLICTS[@]} -gt 0 ]]; then
    _backup_stow_conflicts || return 1
  fi

  if _run_stow true "${packages[@]}"; then
    :
  else
    status=$?
    [[ "$migrate_existing" == true ]] && _restore_stow_conflicts
    return "$status"
  fi

  if _run_stow false "${packages[@]}"; then
    :
  else
    status=$?
    [[ "$migrate_existing" == true ]] && _restore_stow_conflicts
    return "$status"
  fi
}
