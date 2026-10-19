#!/bin/sh
# Install the Claude Code plugins this dotfile repo expects.
# `claude plugin marketplace add` / `install` write extraKnownMarketplaces and
# enabledPlugins into ~/.claude/settings.json themselves, which is why
# dot_claude/modify_settings.json does not manage those keys.
# Reruns whenever the plugin list below changes.
set -eu

if ! command -v claude >/dev/null 2>&1; then
  printf 'claude not installed; skipping plugin setup\n' >&2
  exit 0
fi

settings_file="$HOME/.claude/settings.json"

marketplace_is_configured() {
  [ -f "$settings_file" ] &&
    jq -e --arg repo "$1" '
      .extraKnownMarketplaces? | to_entries[]? |
      select(.value.source.source == "github" and .value.source.repo == $repo)
    ' "$settings_file" >/dev/null
}

plugin_is_enabled() {
  [ -f "$settings_file" ] &&
    jq -e --arg plugin "$1" '.enabledPlugins?[$plugin] == true' "$settings_file" >/dev/null
}

install_plugins() {
  for plugin in "$@"; do
    plugin_is_enabled "$plugin" && continue
    claude plugin install "$plugin" || printf 'plugin install failed: %s\n' "$plugin" >&2
  done
}

install_marketplace() {
  repo=$1
  shift

  if ! marketplace_is_configured "$repo"; then
    claude plugin marketplace add "$repo" || { printf 'marketplace add failed: %s\n' "$repo" >&2; return; }
  fi
  install_plugins "$@"
}

install_marketplace 'mattpocock/skills' \
  'mattpocock-skills@mattpocock'

install_marketplace 'DietrichGebert/ponytail' \
  'ponytail@ponytail'

install_marketplace 'JuliusBrussee/caveman' \
  'caveman@caveman'

install_marketplace 'karanb192/claude-code-hooks'
# Hook guards
install_plugins \
  'case-insensitive-guard@claude-code-hooks' \
  'instructions-audit@claude-code-hooks' \
  'protect-secrets@claude-code-hooks'
# Logging and auditing
install_plugins \
  'cache-tax@claude-code-hooks' \
  'context-hogs@claude-code-hooks' \
  'dead-rules-audit@claude-code-hooks' \
  'session-logger@claude-code-hooks'
