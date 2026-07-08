#!/usr/bin/env bash
# Flag the current conversation as a SUBJECTIVE signal in the agent-maturity captures log.
#
# This is a separate track from interventions.jsonl. /maturity-review REPORTS captures
# (split by valence) but NEVER counts them toward the interventions/PR north star — physical
# separation is what guarantees the subjective flag can't silently bias the objective trend.
# Its value is calibration: where "felt heavy" diverges from a low intervention count, the
# count is under-measuring attention; "felt light" on hard work is a win worth recording.
#
# Usage:
#   capture.sh <valence> "<note>" [weight] [tags] [--session <id>]
#     valence   heavy | light
#                 heavy = cost MORE attention than the intervention count reflects
#                 light = a win — surprisingly LITTLE attention for the work
#     note      short free-text: why it felt that way
#     weight    optional integer 1-5, the HUMAN's subjective intensity. The agent may
#               propose a value but must never author one the human didn't state — an
#               agent-written weight just re-derives the objective count and destroys the
#               flag's independence. Omit when unstated.
#     tags      optional comma-separated "what-kind" slugs from $AGENT_MATURITY_HOME/tags.md
#     --session <id>  coding-agent session id this flag attaches to, so a later
#                     `/harvest-interventions --session <id>` can mine the full transcript
#                     (including turns added AFTER the flag). Omit for a session-less flag.
#   weight and tags are order-independent: a purely-numeric positional arg is weight,
#   anything else is the tag list.
#
# Re-running with the same --session id UPDATES that session's flag in place (no duplicate).
#
# Suggested alias (install.sh sets this up):  alias capture="$AGENT_MATURITY_HOME/scripts/capture.sh"
#   capture heavy "4 rounds redirecting the approach; held the whole design in my head" 4 scope-redirect --session abc123
#   capture light "agent one-shot the migration, zero corrections"

set -euo pipefail

# Lazily provision the private data store so the log resolves into it (best-effort).
bash "$(dirname "$0")/ensure-maturity-data.sh" 2>/dev/null || true

LOG="${AGENT_MATURITY_CAPTURES:-${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}/captures.jsonl}"

# Pull --session <id> out of the args wherever it appears; collect the rest as positionals.
session=""
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --session) session="${2:-}"; shift 2 ;;
    --session=*) session="${1#--session=}"; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

valence="${1:-}"
note="${2:-}"

case "$valence" in
  heavy|light) ;;
  *)
    echo "error: valence must be heavy | light (got '${valence:-<empty>}')" >&2
    echo "usage: capture.sh <heavy|light> \"<note>\" [weight] [tags] [--session <id>]" >&2
    exit 2
    ;;
esac

if [ -z "$note" ]; then
  echo "error: note is required" >&2
  exit 2
fi

# Positionals 3 and 4 are weight and tags in either order: a purely-numeric arg is weight,
# anything else is a comma-separated tag list.
weight=""
tags_csv=""
for arg in "${3:-}" "${4:-}"; do
  [ -z "$arg" ] && continue
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    weight="$arg"
  else
    tags_csv="$arg"
  fi
done

command -v python3 >/dev/null || { echo "error: python3 required" >&2; exit 1; }

repo="$(git rev-parse --show-toplevel 2>/dev/null | xargs -r basename || echo unknown)"

# Build the record and merge it in. python3 (already a project dependency for the collector)
# handles JSON escaping and the update-in-place dedupe by session_id correctly.
LOG="$LOG" SID="$session" VALENCE="$valence" NOTE="$note" WEIGHT="$weight" \
TAGS_CSV="$tags_csv" REPO="$repo" python3 - <<'PY'
import json, os, datetime

log = os.environ["LOG"]
sid = os.environ.get("SID", "")
rec = {
    "date": datetime.date.today().isoformat(),
    "captured_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "repo": os.environ.get("REPO", "unknown") or "unknown",
    "valence": os.environ["VALENCE"],
    "source": "manual",
    "watch": True,
    "tags": [t.strip() for t in os.environ.get("TAGS_CSV", "").split(",") if t.strip()],
    "note": os.environ["NOTE"],
}
if sid:
    rec["session_id"] = sid
w = os.environ.get("WEIGHT", "")
if w:
    rec["weight"] = int(w)

# Update-in-place: drop any existing flag for the same session before appending the new one.
kept = []
replaced = False
if os.path.exists(log):
    with open(log) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            if sid:
                try:
                    if json.loads(line).get("session_id") == sid:
                        replaced = True
                        continue
                except json.JSONDecodeError:
                    pass
            kept.append(line)
kept.append(json.dumps(rec))

os.makedirs(os.path.dirname(log) or ".", exist_ok=True)
with open(log, "w") as f:
    f.write("\n".join(kept) + "\n")

print("updated" if replaced else "logged")
PY

echo "captured $valence (${repo})${session:+ session=$session}${tags_csv:+ [$tags_csv]}: $note"
