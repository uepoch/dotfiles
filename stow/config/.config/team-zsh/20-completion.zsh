# 20-completion.zsh - completion system.

autoload -Uz compinit
# Use a cache file under XDG to keep $HOME clean.
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-${ZSH_VERSION}"
[[ -d "${_zcompdump:h}" ]] || mkdir -p "${_zcompdump:h}"
compinit -d "$_zcompdump"
unset _zcompdump

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
