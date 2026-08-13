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

# "<marketplace repo> <plugin>@<marketplace>"
set -- \
  'mattpocock/skills mattpocock-skills@mattpocock' \
  'DietrichGebert/ponytail ponytail@ponytail' \
  'JuliusBrussee/caveman caveman@caveman'

for entry in "$@"; do
  repo=${entry%% *}
  plugin=${entry#* }
  claude plugin marketplace add "$repo" || { printf 'marketplace add failed: %s\n' "$repo" >&2; continue; }
  claude plugin install "$plugin" || printf 'plugin install failed: %s\n' "$plugin" >&2
done
