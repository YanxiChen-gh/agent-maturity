#!/usr/bin/env bash
# Commit & push the PRIVATE maturity-data repo. No-op when nothing changed.
# Called at the END of the maturity skills (and safe to run by hand) so updates to
# interventions.jsonl / tracker.md persist off the ephemeral env.
set -uo pipefail

DATA="${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}"
[ -d "$DATA/.git" ] || { echo "sync-maturity-data: $DATA not provisioned — run ensure-maturity-data.sh first" >&2; exit 1; }

git -C "$DATA" add -A
if git -C "$DATA" diff --cached --quiet; then
  echo "maturity data: nothing to sync"; exit 0
fi
msg="${1:-sync maturity data $(date -u +%FT%TZ)}"
# Identity: prefer explicit env override, else the data repo's own git config (set by
# install.sh), else fall back to global git config. No hardcoded personal identity.
id_args=()
if [ -n "${AGENT_MATURITY_GIT_NAME:-}" ]; then id_args+=(-c "user.name=$AGENT_MATURITY_GIT_NAME"); fi
if [ -n "${AGENT_MATURITY_GIT_EMAIL:-}" ]; then id_args+=(-c "user.email=$AGENT_MATURITY_GIT_EMAIL"); fi
git -C "$DATA" "${id_args[@]}" commit -q -m "$msg"
git -C "$DATA" push -q && echo "maturity data synced (pushed to private repo)."
