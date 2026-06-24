#!/usr/bin/env bash
# Lazily provision the PRIVATE maturity-data repo at $AGENT_MATURITY_DATA_DIR.
# Idempotent and a fast no-op once set up. Called by the maturity skills at invocation time
# — NOT from install.sh — because gh is reliably authenticated during a session but often
# not at env-provisioning time, and the data is only needed when a skill actually runs.
#
# Clones the per-user private data repo ($AGENT_MATURITY_DATA_REPO, set by install.sh) into
# $AGENT_MATURITY_DATA_DIR. Skills/scripts read interventions.jsonl, tracker.md, briefs/ and
# evidence/ directly from there — no symlinks. Never clobbers a pre-existing dir's locals.
set -uo pipefail

REPO="${AGENT_MATURITY_DATA_REPO:-}"
DATA="${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}"

# Provision $DATA as a clone of the private repo. Handles a PRE-EXISTING non-empty dir
# (the scope-gate hook's log, or an eagerly-created briefs/ dir) by cloning INTO it — so
# the gate can be active from task #1 without breaking provisioning. Remote URL comes from
# $AGENT_MATURITY_DATA_URL (testing) or gh. Returns non-zero on failure (never wedges:
# the caller still creates the local dirs so a brief can be written offline).
provision_data() {
  [ -d "$DATA/.git" ] && return 0   # already provisioned → no-op

  local url="${AGENT_MATURITY_DATA_URL:-}"
  if [ -z "$url" ]; then
    [ -n "$REPO" ] || { echo "ensure-maturity-data: set AGENT_MATURITY_DATA_REPO (e.g. you/agent-maturity-data) or AGENT_MATURITY_DATA_URL — run install.sh to configure it" >&2; return 1; }
    command -v gh >/dev/null || { echo "ensure-maturity-data: gh not on PATH; cannot provision private data repo" >&2; return 1; }
    gh auth status >/dev/null 2>&1 || { echo "ensure-maturity-data: gh not authenticated (run 'gh auth login')" >&2; return 1; }
    url="$(gh repo view "$REPO" --json url -q .url 2>/dev/null)" || true
    [ -n "$url" ] || { echo "ensure-maturity-data: cannot resolve URL for $REPO (no access?)" >&2; return 1; }
  fi

  if [ -e "$DATA" ] && [ -n "$(ls -A "$DATA" 2>/dev/null)" ]; then
    # Existing non-empty dir → clone INTO it, preserving untracked locals.
    echo "Provisioning private maturity data into existing dir: $DATA"
    git -C "$DATA" init -q || return 1
    git -C "$DATA" remote add origin "$url" 2>/dev/null || git -C "$DATA" remote set-url origin "$url"
    git -C "$DATA" fetch -q origin || { echo "ensure-maturity-data: fetch failed (auth/access?)" >&2; return 1; }
    local branch=main
    git -C "$DATA" show-ref -q "refs/remotes/origin/$branch" || \
      branch="$(git -C "$DATA" for-each-ref --format='%(refname:short)' refs/remotes/origin | head -1 | sed 's#^origin/##')"
    [ -n "$branch" ] || { echo "ensure-maturity-data: remote has no branches" >&2; return 1; }
    git -C "$DATA" checkout -q -B "$branch" "origin/$branch" || { echo "ensure-maturity-data: checkout failed (untracked collision?)" >&2; return 1; }
  else
    echo "Provisioning private maturity data: cloning → $DATA"
    git clone -q "$url" "$DATA" || { echo "ensure-maturity-data: clone failed (no access?)" >&2; return 1; }
  fi
}

provision_data
prov_status=$?

# Always create the local data dirs — a brief can then be written locally even if provisioning
# failed (e.g. gh unauthed); the scope-gate skill writes it regardless and it syncs later.
mkdir -p "$DATA/briefs"

if [ "$prov_status" -ne 0 ]; then
  echo "ensure-maturity-data: provisioning incomplete — briefs can be written locally but won't sync until resolved." >&2
  exit "$prov_status"
fi

# First run: ensure the core data files exist so reads/appends don't fail.
for f in interventions.jsonl tracker.md; do
  [ -e "$DATA/$f" ] || : > "$DATA/$f"
done
echo "maturity data ready ($DATA)"
