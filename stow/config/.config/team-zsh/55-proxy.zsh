# 55-proxy.zsh - local CLI proxy checks and Claude wrappers.

_cli_proxy_require_config() {
  if [[ -z "${CLI_PROXY_API_URL:-}" || -z "${CLI_PROXY_API_KEY:-}" ]]; then
    print -u2 'cli proxy: set CLI_PROXY_API_URL and CLI_PROXY_API_KEY'
    return 2
  fi
  if (( ! $+commands[curl] )); then
    print -u2 'cli proxy: curl is required'
    return 127
  fi
}

_cli_proxy_v1_url() {
  _cli_proxy_require_config || return
  local base_url="${CLI_PROXY_API_URL%/}"
  [[ "$base_url" == */v1 ]] || base_url="$base_url/v1"
  print -r -- "$base_url"
}

_cli_proxy_get() {
  setopt localoptions noxtrace

  local url="$1"
  _cli_proxy_require_config || return
  print -r -- "Authorization: Bearer $CLI_PROXY_API_KEY" | \
    command curl --noproxy '*' --fail --silent --show-error \
      --connect-timeout 2 \
      --max-time 5 \
      --header @- \
      --url "$url"
}

cli_proxy_health() {
  local base_url health_url
  base_url=$(_cli_proxy_v1_url) || return
  health_url="${base_url%/v1}/healthz"
  command curl --noproxy '*' --fail --silent --show-error \
    --connect-timeout 2 \
    --max-time 5 \
    --url "$health_url" >/dev/null
}

cli_proxy_models() {
  local base_url response
  base_url=$(_cli_proxy_v1_url) || return
  response=$(_cli_proxy_get "$base_url/models") || return

  if (( $+commands[python3] )); then
    print -rn -- "$response" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for item in data.get("data", []):
    model = item.get("id") if isinstance(item, dict) else None
    if isinstance(model, str):
        print(model)
'
    return
  fi

  print -u2 'cli proxy: python3 is required to parse the model list'
  return 127
}

cli_proxy_has_model() {
  if (( $# != 1 )) || [[ -z "$1" ]]; then
    print -u2 'usage: cli_proxy_has_model <model>'
    return 2
  fi

  local available_model models
  models=$(cli_proxy_models) || return
  for available_model in "${(@f)models}"; do
    [[ "$available_model" == "$1" ]] && return 0
  done
  return 1
}

claude_via_proxy() {
  if (( $# < 1 )) || [[ -z "$1" ]]; then
    print -u2 'usage: claude_via_proxy <model> [claude arguments ...]'
    return 2
  fi
  if (( ! $+commands[claude] )); then
    print -u2 'claude via proxy: claude is required'
    return 127
  fi

  local model="$1"
  shift

  _cli_proxy_require_config || return
  if ! cli_proxy_health; then
    print -u2 'claude via proxy: proxy health check failed'
    return 1
  fi
  if ! cli_proxy_has_model "$model"; then
    print -u2 -- "claude via proxy: model is unavailable: $model"
    return 1
  fi

  local base_url
  base_url="${CLI_PROXY_API_URL%/}"
  [[ "$base_url" == */v1 ]] && base_url="${base_url%/v1}"
  (
    setopt localoptions noxtrace
    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
    export NO_PROXY='127.0.0.1,localhost,::1'
    export no_proxy="$NO_PROXY"
    export ANTHROPIC_BASE_URL="$base_url"
    export ANTHROPIC_AUTH_TOKEN="$CLI_PROXY_API_KEY"
    export ANTHROPIC_MODEL="$model"
    export CLAUDE_CODE_SUBAGENT_MODEL="$model"
    export CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1
    export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3
    export ENABLE_TOOL_SEARCH=false
    command claude "$@"
  )
}

_claude_proxy_wrapper() {
  local default_model="$1"
  local model="$default_model"
  local -a claude_args
  shift

  if (( $# > 0 )) &&
    [[ "$1" == gpt-* || "$1" == glm-* || "$1" == claude-* ]]; then
    model="$1"
    shift
  fi

  while (( $# > 0 )); do
    if [[ "$1" == --model ]]; then
      if (( $# < 2 )) || [[ -z "$2" ]]; then
        print -u2 'claude proxy wrapper: --model requires a value'
        return 2
      fi
      model="$2"
      shift 2
    elif [[ "$1" == --model=* ]]; then
      model="${1#--model=}"
      if [[ -z "$model" ]]; then
        print -u2 'claude proxy wrapper: --model requires a value'
        return 2
      fi
      shift
    else
      claude_args+=("$1")
      shift
    fi
  done

  claude_via_proxy "$model" "${claude_args[@]}"
}

claudex() {
  _claude_proxy_wrapper gpt-5.6-sol "$@"
}

claudez() {
  _claude_proxy_wrapper glm-5.2 "$@"
}

_team_dotfiles_repo_root() {
  local root
  if [[ -n "${TEAM_DOTFILES_ROOT:-}" ]]; then
    root="${TEAM_DOTFILES_ROOT:A}"
  else
    root="${${(%):-%x}:A:h:h:h:h:h}"
  fi

  if [[ ! -d "$root/scripts" ]]; then
    print -u2 -- "team dotfiles: unable to locate repository scripts from $root"
    return 1
  fi
  print -r -- "$root"
}

_team_dotfiles_python_script() {
  if (( $# < 1 )); then
    return 2
  fi
  if (( ! $+commands[python3] )); then
    print -u2 'team dotfiles: python3 is required'
    return 127
  fi

  local root script
  root=$(_team_dotfiles_repo_root) || return
  script="$root/scripts/$1"
  shift

  if [[ ! -f "$script" || ! -r "$script" ]]; then
    print -u2 -- "team dotfiles: script not found: $script"
    return 1
  fi
  python3 "$script" "$@"
}

factory_proxy_sync() {
  _team_dotfiles_python_script factory-sync-cli-proxy.py "$@"
}

cli_proxy_configure_provider() {
  _team_dotfiles_python_script cli-proxy-provider.py "$@"
}
