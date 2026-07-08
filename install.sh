#!/usr/bin/env bash
# Install the agent-maturity engine for the current user.
#
# What it does (all idempotent, non-clobbering):
#   1. Symlinks the skills into ~/.claude/skills/ and ~/.agents/skills/
#   2. Writes ~/.agent-maturity.env (config: HOME, DATA_DIR, DATA_REPO, PATH, li + capture aliases)
#      and makes your shell profile source it.
#   3. Registers the scope-gate hooks for Claude Code and Codex (unless --no-hooks).
#
# It creates the local briefs directory so the scope gate is active immediately. The private
# data repo is still cloned lazily on first skill use by ensure-maturity-data.sh.
#
# Usage:
#   ./install.sh [--data-repo <owner/name>] [--data-dir <path>] [--skills-dir <path>]
#                [--name "<git name>"] [--email "<git email>"] [--no-hooks] [--dry-run]
#
#   --data-repo   your PRIVATE data repo for interventions/tracker/briefs (e.g. you/agent-maturity-data).
#                 Recommended; without it the scope-gate still works offline but harvest/review
#                 can't sync. You can also create it later and set AGENT_MATURITY_DATA_REPO yourself.
#   --data-dir    where the data repo is cloned (default ~/.agent-maturity-data).
#   --skills-dir  additional skills dir (Claude + agent-standard dirs are always installed).
#   --name/--email  git identity for data-repo commits (default: your global git config).
#   --no-hooks    skip scope-gate hook registration.
#   --dry-run     print what would happen; change nothing.

set -uo pipefail

HOME_DIR="$(cd "$(dirname "$0")" && pwd)"   # the engine repo root = where this script lives
ENV_FILE="$HOME/.agent-maturity.env"

# Preserve previously installed values when a later bootstrap omits optional flags.
if [ -f "$ENV_FILE" ]; then
  set +u
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set -u
fi

DATA_REPO="${AGENT_MATURITY_DATA_REPO:-}"
DATA_DIR="${AGENT_MATURITY_DATA_DIR:-$HOME/.agent-maturity-data}"
SKILLS_DIR=""
GIT_NAME="${AGENT_MATURITY_GIT_NAME:-}"
GIT_EMAIL="${AGENT_MATURITY_GIT_EMAIL:-}"
NO_HOOKS=0; DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --data-repo)  DATA_REPO="${2:-}"; shift ;;
    --data-dir)   DATA_DIR="${2:-}"; shift ;;
    --skills-dir) SKILLS_DIR="${2:-}"; shift ;;
    --name)       GIT_NAME="${2:-}"; shift ;;
    --email)      GIT_EMAIL="${2:-}"; shift ;;
    --no-hooks)   NO_HOOKS=1 ;;
    --dry-run)    DRY=1 ;;
    -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "install: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift
done

run() { if [ "$DRY" = 1 ]; then echo "  [dry-run] $*"; else eval "$*"; fi; }

echo "agent-maturity install"
echo "  engine home : $HOME_DIR"
echo "  data dir    : $DATA_DIR"
echo "  data repo   : ${DATA_REPO:-<unset — set later via AGENT_MATURITY_DATA_REPO>}"
echo "  skills dirs : $HOME/.claude/skills, $HOME/.agents/skills${SKILLS_DIR:+, $SKILLS_DIR}"
[ "$DRY" = 1 ] && echo "  (dry-run: no changes)"
echo

# 1. Make scripts executable + symlink skills. Claude Code uses its compatibility path;
# Codex and OpenCode both discover the open Agent Skills path.
run "chmod +x '$HOME_DIR'/scripts/*.sh" || {
  echo "install: failed to make scripts executable" >&2
  exit 1
}
SKILLS_DIRS=("$HOME/.claude/skills" "$HOME/.agents/skills")
[ -n "$SKILLS_DIR" ] && SKILLS_DIRS+=("$SKILLS_DIR")
for skills_dir in "${SKILLS_DIRS[@]}"; do
  run "mkdir -p '$skills_dir'" || {
    echo "install: failed to create skills directory $skills_dir" >&2
    exit 1
  }
  for s in harvest-interventions maturity-review scope-gate capture-conversation; do
    target="$skills_dir/$s"
    source="$HOME_DIR/skills/$s"
    if { [ -e "$target" ] || [ -L "$target" ]; } \
      && { [ ! -L "$target" ] || [ "$(readlink "$target")" != "$source" ]; }; then
      echo "install: refusing to replace unmanaged skill path $target" >&2
      exit 1
    fi
    run "ln -sfn '$source' '$target'" || {
      echo "install: failed to link skill $target" >&2
      exit 1
    }
  done
done
echo "✓ skills symlinked for Claude Code, Codex, and OpenCode"

# Activate the hard gate before the private data repo is needed. Lazy provisioning supports
# cloning into this pre-existing directory without replacing local briefs.
run "mkdir -p '$DATA_DIR/briefs'" || {
  echo "install: failed to create brief store $DATA_DIR/briefs" >&2
  exit 1
}

# 2. Write the config env file and source it from the shell profile(s).
if [ "$DRY" = 1 ]; then
  echo "  [dry-run] write $ENV_FILE (HOME, DATA_DIR, DATA_REPO, PATH, li + capture aliases)"
else
  {
    echo "# agent-maturity config — written by install.sh; edit values as needed."
    echo "export AGENT_MATURITY_HOME=\"$HOME_DIR\""
    echo "export AGENT_MATURITY_DATA_DIR=\"$DATA_DIR\""
    [ -n "$DATA_REPO" ] && echo "export AGENT_MATURITY_DATA_REPO=\"$DATA_REPO\""
    [ -n "$GIT_NAME" ]  && echo "export AGENT_MATURITY_GIT_NAME=\"$GIT_NAME\""
    [ -n "$GIT_EMAIL" ] && echo "export AGENT_MATURITY_GIT_EMAIL=\"$GIT_EMAIL\""
    echo "export PATH=\"\$AGENT_MATURITY_HOME/scripts:\$PATH\""
    echo "alias li=\"\$AGENT_MATURITY_HOME/scripts/log-intervention.sh\""
    echo "alias capture=\"\$AGENT_MATURITY_HOME/scripts/capture.sh\""
  } > "$ENV_FILE"
fi
echo "✓ config written → $ENV_FILE"

# 2b. Ensure the per-user PRIVATE data repo exists, so the lazy clone on first skill use just
# works (one fewer manual step). Best-effort: needs gh authed; never fails the install.
if [ -n "$DATA_REPO" ] && [ "$DRY" != 1 ]; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh repo view "$DATA_REPO" >/dev/null 2>&1; then
      echo "  (data repo $DATA_REPO already exists)"
    elif gh repo create "$DATA_REPO" --private >/dev/null 2>&1; then
      echo "✓ created private data repo $DATA_REPO"
    else
      echo "  (couldn't auto-create $DATA_REPO — create it yourself: gh repo create $DATA_REPO --private)"
    fi
  else
    echo "  (gh not authed — create your data repo later: gh repo create $DATA_REPO --private)"
  fi
fi

src_line='[ -f "$HOME/.agent-maturity.env" ] && . "$HOME/.agent-maturity.env"'
sourced_any=0
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -e "$rc" ] || continue
  sourced_any=1
  if grep -qF '.agent-maturity.env' "$rc" 2>/dev/null; then
    echo "  (already sourced in $(basename "$rc"))"
  else
    run "printf '\n%s\n' '$src_line' >> '$rc'"
    echo "✓ profile $(basename "$rc") now sources config"
  fi
done
# Fresh machine with no profile yet → create one matching the login shell so the env loads.
if [ "$sourced_any" = 0 ]; then
  case "${SHELL:-}" in *zsh) rc="$HOME/.zshrc" ;; *) rc="$HOME/.bashrc" ;; esac
  run "printf '%s\n' '$src_line' >> '$rc'"
  echo "✓ created $(basename "$rc") sourcing config"
fi

# 3. Register scope-gate hooks. OpenCode uses its plugin API rather than this hook format;
# the Dotfiles integration provides that adapter and points it at these same scripts.
if [ "$NO_HOOKS" = 1 ]; then
  echo "• skipping scope-gate hooks (--no-hooks)"
else
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] AGENT_MATURITY_HOME='$HOME_DIR' '$HOME_DIR'/scripts/scope-gate-register.sh"
    echo "  [dry-run] AGENT_MATURITY_HOME='$HOME_DIR' '$HOME_DIR'/scripts/scope-gate-register.sh '$HOME/.codex/hooks.json'"
  else
    if AGENT_MATURITY_HOME="$HOME_DIR" "$HOME_DIR"/scripts/scope-gate-register.sh; then
      echo "✓ scope-gate hooks registered in ~/.claude/settings.json"
    else
      echo "install: failed to register Claude Code scope-gate hooks" >&2
      exit 1
    fi
    if AGENT_MATURITY_HOME="$HOME_DIR" "$HOME_DIR"/scripts/scope-gate-register.sh "$HOME/.codex/hooks.json"; then
      echo "✓ scope-gate hooks registered in ~/.codex/hooks.json"
    else
      echo "install: failed to register Codex scope-gate hooks" >&2
      exit 1
    fi
    echo "  Codex requires one-time review of changed user hooks: open /hooks and trust them."
  fi
fi

echo
echo "Done. Open a new shell (or: source $ENV_FILE) to pick up the env."
if [ -z "$DATA_REPO" ]; then
  echo "Next: create a PRIVATE data repo and set AGENT_MATURITY_DATA_REPO=you/agent-maturity-data,"
  echo "      then run any maturity skill — the data repo is cloned on first use."
fi
echo "Try: /maturity-review  ·  /harvest-interventions  ·  li correction \"...\" verify-fail"
