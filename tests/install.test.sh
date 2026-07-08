#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

HOME="$TMP/home"
SHELL=/bin/bash
PATH="$TMP/bin:$PATH"
export HOME SHELL PATH
mkdir -p "$HOME" "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$TMP/bin/gh"

"$ROOT/install.sh" --data-repo example/agent-maturity-data --data-dir "$HOME/data" \
  --name "Test User" --email "test@example.com" >/dev/null
"$ROOT/install.sh" >/dev/null

for base in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  for skill in harvest-interventions maturity-review scope-gate capture-conversation; do
    target="$base/$skill"
    if [ ! -L "$target" ] || [ "$(readlink "$target")" != "$ROOT/skills/$skill" ]; then
      printf 'FAIL: missing skill link %s\n' "$target" >&2
      exit 1
    fi
  done
done

grep -qF "AGENT_MATURITY_HOME=\"$ROOT\"" "$HOME/.agent-maturity.env" || {
  printf 'FAIL: engine home missing from env file\n' >&2
  exit 1
}
grep -qF 'AGENT_MATURITY_DATA_REPO="example/agent-maturity-data"' "$HOME/.agent-maturity.env" || {
  printf 'FAIL: reinstall discarded data repo config\n' >&2
  exit 1
}
[ -d "$HOME/data/briefs" ] || {
  printf 'FAIL: install did not activate the brief store\n' >&2
  exit 1
}

for hooks in "$HOME/.claude/settings.json" "$HOME/.codex/hooks.json"; do
  grep -qF 'scope-gate-pretooluse.sh' "$hooks" || {
    printf 'FAIL: scope hook missing from %s\n' "$hooks" >&2
    exit 1
  }
  grep -qF 'scope-gate-userpromptsubmit.sh' "$hooks" || {
    printf 'FAIL: prompt hook missing from %s\n' "$hooks" >&2
    exit 1
  }
done

UNMANAGED_HOME="$TMP/unmanaged-home"
mkdir -p "$UNMANAGED_HOME/.agents/skills/scope-gate"
: >"$UNMANAGED_HOME/.agents/skills/scope-gate/keep"
if HOME="$UNMANAGED_HOME" AGENT_MATURITY_DATA_REPO="" \
  AGENT_MATURITY_DATA_DIR="$UNMANAGED_HOME/data" "$ROOT/install.sh" --no-hooks >/dev/null 2>&1; then
  printf 'FAIL: install replaced an unmanaged skill directory\n' >&2
  exit 1
fi
[ -f "$UNMANAGED_HOME/.agents/skills/scope-gate/keep" ] || {
  printf 'FAIL: unmanaged skill content was removed\n' >&2
  exit 1
}

SYMLINK_HOME="$TMP/symlink-home"
mkdir -p "$SYMLINK_HOME/.agents/skills" "$TMP/other-skill"
ln -s "$TMP/other-skill" "$SYMLINK_HOME/.agents/skills/scope-gate"
if HOME="$SYMLINK_HOME" AGENT_MATURITY_DATA_REPO="" \
  AGENT_MATURITY_DATA_DIR="$SYMLINK_HOME/data" "$ROOT/install.sh" --no-hooks >/dev/null 2>&1; then
  printf 'FAIL: install replaced an unmanaged skill symlink\n' >&2
  exit 1
fi
[ "$(readlink "$SYMLINK_HOME/.agents/skills/scope-gate")" = "$TMP/other-skill" ] || {
  printf 'FAIL: unmanaged skill symlink was repointed\n' >&2
  exit 1
}

BLOCKED_DATA="$TMP/not-a-directory"
: >"$BLOCKED_DATA"
if HOME="$TMP/blocked-home" AGENT_MATURITY_DATA_REPO="" \
  AGENT_MATURITY_DATA_DIR="$BLOCKED_DATA/data" "$ROOT/install.sh" --no-hooks >/dev/null 2>&1; then
  printf 'FAIL: install ignored brief-store creation failure\n' >&2
  exit 1
fi

BROKEN_HOME="$TMP/broken-home"
mkdir -p "$BROKEN_HOME/.claude"
printf '%s\n' 'not-json' >"$BROKEN_HOME/.claude/settings.json"
if HOME="$BROKEN_HOME" AGENT_MATURITY_DATA_REPO="" \
  AGENT_MATURITY_DATA_DIR="$BROKEN_HOME/data" "$ROOT/install.sh" >/dev/null 2>&1; then
  printf 'FAIL: hook registration failure did not fail install\n' >&2
  exit 1
fi
grep -qF 'not-json' "$BROKEN_HOME/.claude/settings.json" || {
  printf 'FAIL: malformed hook config was overwritten\n' >&2
  exit 1
}

printf 'agent-maturity install exposes skills to Claude Code, Codex, and OpenCode\n'
