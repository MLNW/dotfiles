#!/usr/bin/env bash
# Render representative Claude Code status payloads and verify key segments.
# Run from this source tree with: bash dot_claude/executable_statusline-smoke.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATUSLINE="$HERE/executable_statusline.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

require() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

strip_ansi() {
  sed $'s/\033\\[[0-9;]*m//g'
}

run_case() {
  local name=$1 payload=$2 expected output plain
  shift 2

  output=$(printf '%s\n' "$payload" | bash "$STATUSLINE")
  plain=$(printf '%s' "$output" | strip_ansi)
  printf '%-12s %s\n' "$name" "${output//$'\n'/ ⏎ }"

  for expected in "$@"; do
    if ! grep -Fq -- "$expected" <<<"$plain"; then
      printf 'FAIL %s: expected %q in %q\n' "$name" "$expected" "$plain" >&2
      exit 1
    fi
  done
}

require bash
require jq
require git
require date
require awk
[ -f "$STATUSLINE" ] || { printf 'statusline not found: %s\n' "$STATUSLINE" >&2; exit 1; }

cat >"$TMPDIR/transcript.jsonl" <<'EOF'
{"type":"assistant","message":{"usage":{"cache_read_input_tokens":800,"cache_creation_input_tokens":100,"input_tokens":100}}}
EOF

now=$(date +%s)

run_case 'compact' \
  '{"model":{"display_name":"Sonnet"},"effort":{"level":"medium"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":12,"context_window_size":200000},"cost":{"total_lines_added":3,"total_lines_removed":1,"total_cost_usd":0.04}}' \
  'Sonnet medium [200k]' 'ctx 12%' '+3/-1' '$0.04'

run_case 'limits' \
  "{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"/tmp\"},\"context_window\":{\"used_percentage\":55,\"context_window_size\":1000000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":60,\"resets_at\":$((now + 9000))},\"seven_day\":{\"used_percentage\":40,\"resets_at\":$((now + 302400))}},\"cost\":{}}" \
  'Opus [1m]' 'ctx 55%' '60%~>120%' '40%~>80%'

run_case 'cache' \
  "{\"model\":{\"display_name\":\"Haiku\"},\"workspace\":{\"current_dir\":\"/tmp\"},\"transcript_path\":\"$TMPDIR/transcript.jsonl\",\"cost\":{}}" \
  'Haiku' 'cache 80%'

# Git info lives on row 2; a linked worktree adds "@<worktree dir>".
git init -q -b main "$TMPDIR/repo"
git -C "$TMPDIR/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$TMPDIR/repo" worktree add -q -b feature "$TMPDIR/wt" >/dev/null

row2() {  # payload -> second row, ANSI stripped ("" when there is only one row)
  printf '%s\n' "$1" | bash "$STATUSLINE" | sed -n 2p | strip_ansi
}
expect_row2() {
  local name=$1 payload=$2 expected=$3 actual
  actual=$(row2 "$payload")
  printf '%-12s row2: %q\n' "$name" "$actual"
  [ "$actual" = "$expected" ] || {
    printf 'FAIL %s: expected row 2 %q, got %q\n' "$name" "$expected" "$actual" >&2; exit 1; }
}

expect_row2 'git' \
  "{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$TMPDIR/repo\"},\"pr\":{\"number\":42},\"cost\":{}}" \
  'main #42'

expect_row2 'worktree' \
  "{\"model\":{\"display_name\":\"Opus\"},\"workspace\":{\"current_dir\":\"$TMPDIR/wt\"},\"cost\":{}}" \
  'feature @wt'

expect_row2 'no-git' \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"cost":{}}' \
  ''

printf 'statusline smoke test passed\n'
