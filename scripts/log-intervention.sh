#!/usr/bin/env bash
# Append one intervention to the agent-maturity log. This is the raw signal the
# /maturity-review skill scores against — keep it cheap so you actually log.
#
# Usage:
#   log-intervention.sh <type> "<note>" [cost_min] [tags]
#     type      correction | clarification | unblock
#                 correction    = you fixed/redid agent output  -> Trust
#                 clarification = you re-scoped / answered mid-task -> Spec
#                 unblock       = you got a stuck agent moving    -> Babysit
#     note      short free-text description
#     cost_min  optional integer minutes the intervention cost (default 0)
#     tags      optional comma-separated "what-kind" slugs from
#                 $AGENT_MATURITY_HOME/tags.md (e.g. verify-fail,logic-bug)
#   cost_min and tags are order-independent: a numeric arg is cost, anything else is tags.
#
# Suggested shell alias (install.sh sets this up):
#   alias li="$AGENT_MATURITY_HOME/scripts/log-intervention.sh"
# Then: li correction "handed off without running the app" verify-fail
#       li correction "rewrote the auth guard the agent got backwards" 15 logic-bug

set -euo pipefail

# Lazily provision the private data store so the log resolves into it (best-effort — if the
# repo's unreachable, fall back to a local file rather than failing the log call).
bash "$(dirname "$0")/ensure-maturity-data.sh" 2>/dev/null || true

LOG="${AGENT_MATURITY_LOG:-${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}/interventions.jsonl}"

type="${1:-}"
note="${2:-}"

case "$type" in
  correction|clarification|unblock) ;;
  *)
    echo "error: type must be correction | clarification | unblock (got '${type:-<empty>}')" >&2
    echo "usage: log-intervention.sh <type> \"<note>\" [cost_min] [tags]" >&2
    exit 2
    ;;
esac

if [ -z "$note" ]; then
  echo "error: note is required" >&2
  exit 2
fi

# Args 3 and 4 are cost_min and tags in either order: a purely-numeric arg is cost,
# anything else is a comma-separated tag list.
cost=0
tags_csv=""
for arg in "${3:-}" "${4:-}"; do
  [ -z "$arg" ] && continue
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    cost="$arg"
  else
    tags_csv="$arg"
  fi
done

date_iso="$(date +%F)"
repo="$(git rev-parse --show-toplevel 2>/dev/null | xargs -r basename || echo unknown)"

# Escape a string for embedding in JSON (backslashes + double quotes).
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

esc_note="$(json_escape "$note")"

# Build a JSON array of trimmed, non-empty tags. Empty -> "[]".
tags_json="[]"
if [ -n "$tags_csv" ]; then
  tags_json="["
  first=1
  IFS=',' read -ra _tags <<< "$tags_csv"
  for t in "${_tags[@]}"; do
    t="$(printf '%s' "$t" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$t" ] && continue
    [ "$first" -eq 0 ] && tags_json+=","
    tags_json+="\"$(json_escape "$t")\""
    first=0
  done
  tags_json+="]"
fi

printf '{"date":"%s","repo":"%s","type":"%s","cost_min":%s,"source":"manual","tags":%s,"note":"%s"}\n' \
  "$date_iso" "$repo" "$type" "$cost" "$tags_json" "$esc_note" >> "$LOG"

echo "logged $type ($repo)${tags_csv:+ [$tags_csv]}: $note"
