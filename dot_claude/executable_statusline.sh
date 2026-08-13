#!/usr/bin/env bash
# Claude Code status line. Needs: bash, jq, awk, git, date.
# Row 1: <model> <effort> [1m] | ctx x% | cache x% | hh:mm x%~>y% | Day x%~>y% | +a/-r | $cost
# Row 2: <branch> [@worktree] [#pr]   (omitted outside a git repo)
export LC_NUMERIC=C
input=$(cat)
now=$(date +%s)

R=$'\e[0m'; DIM=$'\e[2m'
GRN=$'\e[38;5;114m'; YLW=$'\e[38;5;179m'; ORG=$'\e[38;5;208m'; RED=$'\e[38;5;203m'
BLU=$'\e[38;5;110m'; PUR=$'\e[38;5;140m'

SEPARATOR='•'

RATE_LIMIT_YELLOW_AT=50
RATE_LIMIT_ORANGE_AT=75
RATE_LIMIT_RED_AT=90
FIVE_HOUR_WINDOW_SECONDS=18000
SEVEN_DAY_WINDOW_SECONDS=604800

if ! command -v jq >/dev/null 2>&1; then
  printf '%s' "${DIM}[statusline: jq missing]${R}"; exit 0
fi

# Every dynamic value must remain @sh-encoded before eval executes these assignments.
eval "$(printf '%s' "$input" | jq -r '
  def n(f): if f == null then "" else (f|floor|tostring) end;
  "model="      + (.model.display_name // "" | @sh) + "\n" +
  "effort="     + (.effort.level // "" | @sh) + "\n" +
  "cwd="        + (.workspace.current_dir // .cwd // "" | @sh) + "\n" +
  "pr="         + (n(.pr.number) | @sh) + "\n" +
  "ctx="        + (n(.context_window.used_percentage) | @sh) + "\n" +
  "ctxsize="    + (n(.context_window.context_window_size) | @sh) + "\n" +
  "transcript=" + (.transcript_path // "" | @sh) + "\n" +
  "h5="         + (n(.rate_limits.five_hour.used_percentage) | @sh) + "\n" +
  "h5r="        + (n(.rate_limits.five_hour.resets_at) | @sh) + "\n" +
  "d7="         + (n(.rate_limits.seven_day.used_percentage) | @sh) + "\n" +
  "d7r="        + (n(.rate_limits.seven_day.resets_at) | @sh) + "\n" +
  "added="      + (n(.cost.total_lines_added) | @sh) + "\n" +
  "removed="    + (n(.cost.total_lines_removed) | @sh) + "\n" +
  "cost="       + ((.cost.total_cost_usd // 0) | tostring | @sh)
' 2>/dev/null)"

# Usage: gradient_color value yellow_at orange_at red_at [inverse]
gradient_color() {
  local value=$1 yellow_at=$2 orange_at=$3 red_at=$4 level=0 inverse=0
  local -a colors=("$GRN" "$YLW" "$ORG" "$RED")
  if   [ "$value" -ge "$red_at" ]; then level=3
  elif [ "$value" -ge "$orange_at" ]; then level=2
  elif [ "$value" -ge "$yellow_at" ]; then level=1; fi
  [ "${5:-normal}" = inverse ] && inverse=1
  printf '%s' "${colors[$(( inverse ? 3 - level : level ))]}"
}
fmt_time() { date -d "@$1" "+$2" 2>/dev/null || date -r "$1" "+$2" 2>/dev/null; }

# Linear pace: percent scaled to the full window by fraction elapsed.
# Suppressed in the first 5% of a window, where the extrapolation is noise.
project_limit_usage() {
  local percent=$1 reset_at=$2 window_seconds=$3 elapsed projected_percent
  [ -n "$reset_at" ] || return 1
  elapsed=$(( window_seconds - (reset_at - now) ))
  [ $(( elapsed * 20 )) -ge "$window_seconds" ] || return 1
  projected_percent=$(( percent * window_seconds / elapsed ))
  [ "$projected_percent" -gt 999 ] && projected_percent=999
  [ "$projected_percent" -gt "$percent" ] || return 1
  printf '%s' "$projected_percent"
}

append_segment() { [ -n "$out" ] && out="$out ${DIM}${SEPARATOR}${R} "; out="$out$1"; }

append_limit_segment() {  # percent reset_at window_seconds label
  local percent=$1 reset_at=$2 window_seconds=$3 label=$4 color projected_percent segment
  [ -n "$percent" ] || return
  color=$(gradient_color "$percent" "$RATE_LIMIT_YELLOW_AT" "$RATE_LIMIT_ORANGE_AT" "$RATE_LIMIT_RED_AT")
  segment="${DIM}${label}${R} ${color}${percent}%${R}"
  if projected_percent=$(project_limit_usage "$percent" "$reset_at" "$window_seconds"); then
    segment="$segment${DIM}~>${R}$(gradient_color "$projected_percent" "$RATE_LIMIT_YELLOW_AT" "$RATE_LIMIT_ORANGE_AT" "$RATE_LIMIT_RED_AT")${projected_percent}%${R}"
  fi
  append_segment "$segment"
}

# branch, plus worktree name when in a linked worktree, plus PR number when one is open.
# Rendered on its own row, so long branch/worktree names cost no width on the metrics row.
# One rev-parse for all four values; a second call only for the rare detached HEAD.
git_row() {
  local rev_parse_output branch git_dir common_git_dir top_level
  [ -n "$cwd" ] || return
  rev_parse_output=$(git -C "$cwd" rev-parse --abbrev-ref HEAD --absolute-git-dir \
    --path-format=absolute --git-common-dir --show-toplevel 2>/dev/null) || return
  { read -r branch; read -r git_dir; read -r common_git_dir; read -r top_level; } <<< "$rev_parse_output"
  [ "$branch" != HEAD ] || branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  [ "$git_dir" = "$common_git_dir" ] || branch="${branch} ${DIM}@${R}${BLU}$(basename "$top_level")"
  printf '%s' "${BLU}${branch}${R}${pr:+ ${DIM}#${pr}${R}}"
}

cache_hit_rate() {
  local transcript_path=$1
  [ -f "$transcript_path" ] || return
  tail -n 200 "$transcript_path" 2>/dev/null | jq -rs '
    [ .[] | select(.type == "assistant") | .message.usage | select(. != null) ] | last
    | if . == null then empty
      else (.cache_read_input_tokens // 0) as $r
         | ($r + (.cache_creation_input_tokens // 0) + (.input_tokens // 0)) as $t
         | if $t == 0 then empty else ($r * 100 / $t | floor) end
      end' 2>/dev/null
}

out=""

if [ -n "$model" ]; then
  context_window_label=""
  case "${ctxsize:-0}" in
    0) ;;
    *) context_window_label=$(awk -v s="$ctxsize" 'BEGIN{ if (s>=1000000) printf "%gm", s/1000000; else printf "%gk", s/1000 }') ;;
  esac
  append_segment "${PUR}${model}${R}${effort:+ ${DIM}${effort}${R}}${context_window_label:+ ${DIM}[${context_window_label}]${R}}"
fi
[ -n "$ctx" ] && append_segment "${DIM}ctx${R} $(gradient_color "$ctx" 15 25 50)${ctx}%${R}"

# Cache hit rate of the last API turn: cache_read / all input tokens.
# Low means the prefix was re-sent at full price (cache invalidated or TTL expired).
if [ -n "$transcript" ]; then
  cache_hit=$(cache_hit_rate "$transcript")
  if [ -n "$cache_hit" ]; then
    # inverse since high is good
    cache_color=$(gradient_color "$cache_hit" 25 50 80 inverse)
    append_segment "${DIM}cache${R} ${cache_color}${cache_hit}%${R}"
  fi
fi

append_limit_segment "$h5" "$h5r" "$FIVE_HOUR_WINDOW_SECONDS" "$([ -n "$h5r" ] && fmt_time "$h5r" '%H:%M')"
append_limit_segment "$d7" "$d7r" "$SEVEN_DAY_WINDOW_SECONDS" "$([ -n "$d7r" ] && fmt_time "$d7r" '%a')"

if [ "${added:-0}" -gt 0 ] || [ "${removed:-0}" -gt 0 ]; then
  append_segment "${GRN}+${added:-0}${R}/${RED}-${removed:-0}${R}"
fi

cost_fmt=$(awk -v c="${cost:-0}" 'BEGIN{printf "%.2f", c}')
[ "$cost_fmt" != "0.00" ] && append_segment "${GRN}\$${cost_fmt}${R}"

printf '%s' "$out"
git=$(git_row)
[ -n "$git" ] && printf '\n%s' "$git"
exit 0
