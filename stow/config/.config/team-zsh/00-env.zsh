# 00-env.zsh - editor/pager defaults.

export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export PAGER="${PAGER:-less}"
export LESS="${LESS:--R}"

if (( $+commands[podman] )); then
  export CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"
fi
