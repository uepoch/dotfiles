#!/usr/bin/env zsh

setopt NO_UNSET PIPE_FAIL

fail() {
  print -u2 "FAIL: $*"
  exit 1
}

assert_binding() {
  local sequence="$1"
  local expected="$2"
  local actual

  actual=$(bindkey -M emacs "$sequence" 2>/dev/null) ||
    fail "missing binding for ${(qqq)sequence}"
  [[ "$actual" == *" $expected" ]] ||
    fail "expected ${(qqq)sequence} to use $expected, got $actual"
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  grep -Fqx -- "$expected" "$file" ||
    fail "expected $file to contain ${(qqq)expected}"
}

repo_root="${TEAM_DOTFILES_ROOT:-${0:A:h:h}}"
test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT

export HOME="$test_home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export TEAM_ZSH_DIR="$repo_root/stow/config/.config/team-zsh"
export TERM="${TERM:-xterm-256color}"
[[ "$TERM" == dumb ]] && export TERM=xterm-256color

fake_bin="$HOME/fake-bin"
mkdir -p \
  "$fake_bin" \
  "$HOME/.local/bin" \
  "$HOME/.cargo/bin" \
  "$HOME/go/bin" \
  "$HOME/.bun/bin" \
  "$HOME/.grok/bin" \
  "$HOME/.local/share/pnpm" \
  "$HOME/.asdf/shims" \
  "$XDG_CONFIG_HOME/team-dotfiles"

cat > "$HOME/.zshrc.local" <<'LOCAL'
export TEAM_LOCAL_LOADED=1
alias claudex='false'
LOCAL

cat > "$XDG_CONFIG_HOME/team-dotfiles/proxy.env" <<EOF_PROXY
export CLI_PROXY_API_URL='http://proxy.test:8317'
export CLI_PROXY_API_KEY='test-key-not-a-real-credential'
export ZAI_API_KEY='test-zai-not-a-real-credential'
export PROXY_ENV_LOADED=1
EOF_PROXY
chmod 600 "$XDG_CONFIG_HOME/team-dotfiles/proxy.env"

source "$repo_root/stow/zsh/.zshenv"
source "$repo_root/stow/zsh/.zshrc"

[[ "${PROXY_ENV_LOADED:-}" == 1 ]] || fail "secure proxy environment was not loaded"
[[ "${TEAM_LOCAL_LOADED:-}" == 1 ]] || fail "local override was not loaded"
(( ! $+aliases[claudex] && $+functions[claudex] )) ||
  fail "legacy claudex alias was not replaced by the shared function"

assert_binding '^[[A' history-search-backward
assert_binding '^[[B' history-search-forward
assert_binding '^R' atuin-search
assert_binding '^T' fzf-file-widget
assert_binding '^[c' fzf-cd-widget
assert_binding '^[[1;5D' backward-word
assert_binding '^[[1;5C' forward-word
assert_binding '^[[H' beginning-of-line
assert_binding '^[[F' end-of-line
assert_binding '^[[3~' delete-char
assert_binding '^[[3;5~' kill-word
assert_binding '^H' backward-kill-word
assert_binding '^[[Z' reverse-menu-complete
assert_binding '^K' kill-line
assert_binding '^U' backward-kill-line

typeset -A seen_paths
for entry in "${path[@]}"; do
  [[ -z "${seen_paths[$entry]:-}" ]] || fail "duplicate PATH entry: $entry"
  seen_paths[$entry]=1
done
asdf_shims="$HOME/.asdf/shims"
[[ -n "${seen_paths[$asdf_shims]:-}" ]] ||
  fail "asdf shims are missing from non-login interactive PATH"

[[ "$CONTAINER_RUNTIME" == podman ]] || fail "Podman was not selected as container runtime"
(( $+functions[vf] )) || fail "vf function is unavailable"
mkcd >/dev/null 2>&1
[[ $? -eq 2 ]] || fail "mkcd without an argument did not return usage status"

# alias_cmd validates every definition before creating aliases and silently
# skips a valid group when its guarded command is unavailable.
unalias alias_cmd_good alias_cmd_bad 2>/dev/null || true
alias_cmd definitely-not-installed 'alias_cmd_good=definitely-not-installed --flag' ||
  fail "alias_cmd rejected a valid alias definition"
(( ! $+aliases[alias_cmd_good] )) || fail "alias created for a missing command"
alias_cmd clear 'alias_cmd_good=clear' 'malformed-definition' >/dev/null 2>&1
[[ $? -eq 2 ]] || fail "malformed alias did not return usage status"
(( ! $+aliases[alias_cmd_good] )) || fail "partial aliases were created before validation failed"
alias_cmd clear '=clear' >/dev/null 2>&1
[[ $? -eq 2 ]] || fail "empty alias name was accepted"

# An unsafe private environment file must be skipped before any modules load.
unsafe_home="$test_home/unsafe-home"
mkdir -p "$unsafe_home/.config/team-dotfiles"
cat > "$unsafe_home/.config/team-dotfiles/proxy.env" <<'UNSAFE'
export UNSAFE_PROXY_ENV_LOADED=1
UNSAFE
chmod 644 "$unsafe_home/.config/team-dotfiles/proxy.env"
unsafe_warning=$(
  HOME="$unsafe_home" \
  XDG_CONFIG_HOME="$unsafe_home/.config" \
  TEAM_ZSH_DIR="$test_home/no-modules" \
  zsh -fc 'source "$1"; [[ -z "${UNSAFE_PROXY_ENV_LOADED:-}" ]]' \
    _ "$repo_root/stow/zsh/.zshrc" 2>&1
) || fail "unsafe proxy environment was sourced"
[[ "$unsafe_warning" == *'skipping unsafe proxy environment file'* ]] ||
  fail "unsafe proxy environment did not emit a warning"

# Fake proxy and Claude commands record only non-secret behavior. curl consumes
# its header configuration from stdin so credentials never appear in argv logs.
cat > "$fake_bin/curl" <<'CURL'
#!/usr/bin/env zsh
[[ "$*" == *'--header @-'* ]] && cat >/dev/null
print -r -- "$*" >> "$FAKE_CURL_LOG"
if [[ "${FAKE_CURL_FAIL:-0}" == 1 ]]; then
  return 22
fi
if [[ "$*" == *'/healthz'* ]]; then
  print -r -- '{"status":"ok"}'
  return 0
fi
cat "$FAKE_MODELS_FILE"
CURL
cat > "$fake_bin/claude" <<'CLAUDE'
#!/usr/bin/env zsh
{
  print -r -- "base=$ANTHROPIC_BASE_URL"
  print -r -- "token_set=$([[ -n "$ANTHROPIC_AUTH_TOKEN" ]] && print yes || print no)"
  print -r -- "model=$ANTHROPIC_MODEL"
  print -r -- "subagent=$CLAUDE_CODE_SUBAGENT_MODEL"
  print -r -- "effort=$CLAUDE_CODE_ALWAYS_ENABLE_EFFORT"
  print -r -- "concurrency=$CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY"
  print -r -- "tool_search=$ENABLE_TOOL_SEARCH"
  print -r -- "http_proxy_set=$([[ -n "${HTTP_PROXY:-}${http_proxy:-}" ]] && print yes || print no)"
  print -r -- "no_proxy=$NO_PROXY"
  print -r -- "args=${(j:|:)@}"
} > "$FAKE_CLAUDE_LOG"
return "${FAKE_CLAUDE_STATUS:-0}"
CLAUDE
cat > "$fake_bin/python3" <<'PYTHON'
#!/usr/bin/env zsh
if [[ "$1" == -c ]]; then
  /usr/bin/python3 "$@"
else
  print -r -- "${(j:|:)@}" > "$FAKE_PYTHON_LOG"
  return "${FAKE_PYTHON_STATUS:-0}"
fi
PYTHON
chmod +x "$fake_bin/curl" "$fake_bin/claude" "$fake_bin/python3"

export FAKE_CURL_LOG="$test_home/curl.log"
export FAKE_CLAUDE_LOG="$test_home/claude.log"
export FAKE_PYTHON_LOG="$test_home/python.log"
export FAKE_MODELS_FILE="$test_home/models.json"
cat > "$FAKE_MODELS_FILE" <<'MODELS'
{"data":[{"id":"gpt-5.6-sol"},{"id":"glm-5.2"},{"id":"gpt-5.6-sol-extra"}]}
MODELS
: > "$FAKE_CURL_LOG"

path=("$fake_bin" $path)
rehash

models=$(cli_proxy_models) || fail "cli_proxy_models failed"
[[ "$models" == $'gpt-5.6-sol\nglm-5.2\ngpt-5.6-sol-extra' ]] ||
  fail "cli_proxy_models returned unexpected models"
cli_proxy_has_model gpt-5.6-sol || fail "exact proxy model was not found"
cli_proxy_has_model gpt-5.6 >/dev/null 2>&1 && fail "partial proxy model matched"

unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL
unset CLAUDE_CODE_SUBAGENT_MODEL
export CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=0
export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=9
export ENABLE_TOOL_SEARCH=true
export HTTP_PROXY='http://untrusted-proxy.test:8080'
export http_proxy="$HTTP_PROXY"
claudex --print 'hello world' || fail "claudex default model invocation failed"
assert_file_contains "$FAKE_CLAUDE_LOG" 'base=http://proxy.test:8317/v1'
assert_file_contains "$FAKE_CLAUDE_LOG" 'token_set=yes'
assert_file_contains "$FAKE_CLAUDE_LOG" 'model=gpt-5.6-sol'
assert_file_contains "$FAKE_CLAUDE_LOG" 'subagent=gpt-5.6-sol'
assert_file_contains "$FAKE_CLAUDE_LOG" 'effort=1'
assert_file_contains "$FAKE_CLAUDE_LOG" 'concurrency=3'
assert_file_contains "$FAKE_CLAUDE_LOG" 'tool_search=false'
assert_file_contains "$FAKE_CLAUDE_LOG" 'http_proxy_set=no'
assert_file_contains "$FAKE_CLAUDE_LOG" 'no_proxy=127.0.0.1,localhost,::1'
assert_file_contains "$FAKE_CLAUDE_LOG" 'args=--print|hello world'
grep -Fq -- '--noproxy' "$FAKE_CURL_LOG" ||
  fail "proxy requests did not bypass outbound proxy settings"
if grep -Fq -- "$CLI_PROXY_API_KEY" "$FAKE_CURL_LOG"; then
  fail "proxy key appeared in curl arguments"
fi
[[ -z "${ANTHROPIC_BASE_URL:-}" && -z "${ANTHROPIC_AUTH_TOKEN:-}" &&
  -z "${ANTHROPIC_MODEL:-}" ]] || fail "proxy environment leaked into the shell"
[[ "$CLAUDE_CODE_ALWAYS_ENABLE_EFFORT" == 0 &&
  "$CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY" == 9 &&
  "$ENABLE_TOOL_SEARCH" == true ]] || fail "Claude defaults leaked into the shell"
[[ "$HTTP_PROXY" == 'http://untrusted-proxy.test:8080' &&
  "$http_proxy" == "$HTTP_PROXY" ]] || fail "proxy variables leaked out of wrapper scope"

claudez gpt-5.6-sol --dangerously-skip-permissions ||
  fail "positional model override failed"
assert_file_contains "$FAKE_CLAUDE_LOG" 'model=gpt-5.6-sol'
assert_file_contains "$FAKE_CLAUDE_LOG" 'args=--dangerously-skip-permissions'

claudez --model gpt-5.6-sol --print prompt || fail "explicit --model failed"
assert_file_contains "$FAKE_CLAUDE_LOG" 'model=gpt-5.6-sol'
assert_file_contains "$FAKE_CLAUDE_LOG" 'args=--print|prompt'

claudex --print --model glm-5.2 prompt ||
  fail "model override after another argument failed"
assert_file_contains "$FAKE_CLAUDE_LOG" 'model=glm-5.2'
assert_file_contains "$FAKE_CLAUDE_LOG" 'subagent=glm-5.2'
assert_file_contains "$FAKE_CLAUDE_LOG" 'args=--print|prompt'

export FAKE_CLAUDE_STATUS=37
claudex --print status-test >/dev/null 2>&1
[[ $? -eq 37 ]] || fail "claudex did not preserve Claude's exit status"
unset FAKE_CLAUDE_STATUS

before_claude_log=$(<"$FAKE_CLAUDE_LOG")
claudex --model missing-model --print nope >/dev/null 2>&1
[[ $? -eq 1 ]] || fail "missing model did not fail"
[[ "$(<"$FAKE_CLAUDE_LOG")" == "$before_claude_log" ]] ||
  fail "Claude ran for an unavailable model"

export FAKE_CURL_FAIL=1
claudex --print nope >/dev/null 2>&1
[[ $? -eq 1 ]] || fail "failed proxy health check did not stop Claude"
unset FAKE_CURL_FAIL

mv "$fake_bin/claude" "$fake_bin/claude.off"
saved_path=("${path[@]}")
path=("$fake_bin")
rehash
claudex --print nope >/dev/null 2>&1
[[ $? -eq 127 ]] || fail "missing Claude command did not return 127"
path=("${saved_path[@]}")
unset saved_path
mv "$fake_bin/claude.off" "$fake_bin/claude"
chmod +x "$fake_bin/claude"
rehash

saved_team_dotfiles_root="${TEAM_DOTFILES_ROOT:-}"
unset TEAM_DOTFILES_ROOT
factory_proxy_sync custom-config.yaml || fail "factory_proxy_sync failed"
assert_file_contains "$FAKE_PYTHON_LOG" \
  "$repo_root/scripts/factory-sync-cli-proxy.py|custom-config.yaml"
export TEAM_DOTFILES_ROOT="$saved_team_dotfiles_root"
unset saved_team_dotfiles_root

provider_root="$test_home/provider-root"
mkdir -p "$provider_root/scripts"
: > "$provider_root/scripts/cli-proxy-provider.py"
TEAM_DOTFILES_ROOT="$provider_root" \
  cli_proxy_configure_provider zai --dry-run ||
  fail "cli_proxy_configure_provider failed"
assert_file_contains "$FAKE_PYTHON_LOG" \
  "$provider_root/scripts/cli-proxy-provider.py|zai|--dry-run"

print "check-zsh.zsh: PASS"
