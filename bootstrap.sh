#!/usr/bin/env bash
# One-shot bootstrap: clone (or update) the agent-maturity engine, then run its installer.
# Lets a new user set up without a manual `git clone` — pipe it from curl, or run it locally.
#
#   # public repo / marketplace:
#   curl -fsSL https://raw.githubusercontent.com/YanxiChen-gh/agent-maturity/main/bootstrap.sh \
#     | bash -s -- --data-repo <you>/agent-maturity-data
#
#   # private repo (needs gh authenticated): clone once, then bootstrap re-runs are pull+install
#   gh repo clone YanxiChen-gh/agent-maturity ~/agent-maturity
#   ~/agent-maturity/bootstrap.sh --data-repo <you>/agent-maturity-data
#
# All args are forwarded verbatim to install.sh. Target dir = $AGENT_MATURITY_HOME (default ~/agent-maturity).
set -euo pipefail

REPO="${AGENT_MATURITY_REPO:-YanxiChen-gh/agent-maturity}"
HOME_DIR="${AGENT_MATURITY_HOME:-$HOME/agent-maturity}"

if [ -d "$HOME_DIR/.git" ]; then
  echo "bootstrap: updating engine at $HOME_DIR"
  git -C "$HOME_DIR" pull --ff-only -q || echo "bootstrap: pull skipped (local changes/offline)"
else
  echo "bootstrap: cloning $REPO → $HOME_DIR"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh repo clone "$REPO" "$HOME_DIR" || git clone -q "https://github.com/$REPO.git" "$HOME_DIR"
  else
    git clone -q "https://github.com/$REPO.git" "$HOME_DIR" \
      || { echo "bootstrap: clone failed — for a private repo, authenticate gh first (gh auth login)" >&2; exit 1; }
  fi
fi

exec "$HOME_DIR/install.sh" "$@"
