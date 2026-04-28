# 10-history.zsh - history file and behavior.

HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=100000
SAVEHIST=100000

# Ensure history dir exists (atuin will still take over interactive search,
# but we keep a local file as a safety net).
[[ -d "${HISTFILE:h}" ]] || mkdir -p "${HISTFILE:h}"

setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY
