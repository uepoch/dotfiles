# 80-plugins.zsh - zsh plugin loading (keep near the end).

# fzf keybindings and completion
_fzf_key=/usr/share/fzf/key-bindings.zsh
_fzf_comp=/usr/share/fzf/completion.zsh
[[ -f "$_fzf_key" ]]  && source "$_fzf_key"
[[ -f "$_fzf_comp" ]] && source "$_fzf_comp"
unset _fzf_key _fzf_comp

# zsh-autosuggestions
_zsh_autosug=/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f "$_zsh_autosug" ]] && source "$_zsh_autosug"
unset _zsh_autosug

# zsh-syntax-highlighting (must be last)
_zsh_syntax=/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
[[ -f "$_zsh_syntax" ]] && source "$_zsh_syntax"
unset _zsh_syntax
