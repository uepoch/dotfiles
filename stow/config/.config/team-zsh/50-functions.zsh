# 50-functions.zsh - shell utility functions.

mkcd() {
  mkdir -p "$1" && cd "$1"
}
