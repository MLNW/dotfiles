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

install_marketplace() {
  repo=$1
  shift

  claude plugin marketplace add "$repo" || { printf 'marketplace add failed: %s\n' "$repo" >&2; return; }
  for plugin in "$@"; do
    claude plugin install "$plugin" || printf 'plugin install failed: %s\n' "$plugin" >&2
  done
}

install_marketplace 'mattpocock/skills' \
  'mattpocock-skills@mattpocock'

install_marketplace 'DietrichGebert/ponytail' \
  'ponytail@ponytail'

install_marketplace 'JuliusBrussee/caveman' \
  'caveman@caveman'
