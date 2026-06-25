#!/usr/bin/env bash
# Plain-bash tests for the capture mechanic. Run: bash tests/capture.test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAP="$ROOT/scripts/capture.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok  %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
assert_eq(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want [$2], got [$3])"; fi; }

# Each test runs in an isolated data dir so captures.jsonl never touches real data, and points
# AGENT_MATURITY_CAPTURES straight at the temp file (ensure-maturity-data is a best-effort no-op).
new_env(){ TMP="$(mktemp -d)"; export AGENT_MATURITY_DATA_DIR="$TMP/data"; mkdir -p "$AGENT_MATURITY_DATA_DIR"; export AGENT_MATURITY_CAPTURES="$AGENT_MATURITY_DATA_DIR/captures.jsonl"; }
field(){ python3 -c 'import json,sys; print(json.loads(sys.stdin.readline()).get(sys.argv[1],""))' "$1"; }

# --- valence is required and validated ---
test_valence(){
  new_env
  "$CAP" bogus "x" >/dev/null 2>&1 && no "rejects bad valence" || ok "rejects bad valence"
  "$CAP" heavy "" >/dev/null 2>&1 && no "requires a note" || ok "requires a note"
  "$CAP" heavy "felt heavy" >/dev/null 2>&1 && ok "accepts heavy" || no "accepts heavy"
  "$CAP" light "smooth" >/dev/null 2>&1 && ok "accepts light" || no "accepts light"
  rm -rf "$TMP"
}

# --- a well-formed record lands, with the right fields ---
test_record(){
  new_env
  "$CAP" heavy "held the whole design in my head" 4 scope-redirect,verify-fail --session abc123 >/dev/null 2>&1
  local line; line="$(cat "$AGENT_MATURITY_CAPTURES")"
  python3 -c 'import json,sys; json.loads(sys.stdin.readline())' <<<"$line" && ok "emits valid JSON" || no "emits valid JSON"
  assert_eq "valence recorded"   "heavy"  "$(field valence    <<<"$line")"
  assert_eq "weight recorded"    "4"      "$(field weight     <<<"$line")"
  assert_eq "session recorded"   "abc123" "$(field session_id <<<"$line")"
  assert_eq "watch armed"        "True"   "$(field watch      <<<"$line")"
  assert_eq "tags parsed"        "['scope-redirect', 'verify-fail']" "$(python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["tags"])' <<<"$line")"
  rm -rf "$TMP"
}

# --- weight/tags are order-independent; weight omitted when unstated ---
test_arg_order(){
  new_env
  "$CAP" light "win" mytag 3 --session s1 >/dev/null 2>&1   # tags before weight
  local line; line="$(cat "$AGENT_MATURITY_CAPTURES")"
  assert_eq "weight from either position" "3" "$(field weight <<<"$line")"
  assert_eq "tag from either position" "['mytag']" "$(python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["tags"])' <<<"$line")"
  new_env
  "$CAP" heavy "no weight given" --session s2 >/dev/null 2>&1
  assert_eq "weight omitted when unstated" "" "$(field weight < "$AGENT_MATURITY_CAPTURES")"
  rm -rf "$TMP"
}

# --- re-capturing the same session UPDATES in place (no duplicate) ---
test_update_in_place(){
  new_env
  "$CAP" heavy "first read"  --session dup1 >/dev/null 2>&1
  "$CAP" light "on reflection, a win" 2 --session dup1 >/dev/null 2>&1
  local n; n="$(wc -l < "$AGENT_MATURITY_CAPTURES" | tr -d ' ')"
  assert_eq "one line after re-capture" "1" "$n"
  assert_eq "latest valence kept" "light" "$(field valence < "$AGENT_MATURITY_CAPTURES")"
  # a DIFFERENT session appends rather than replaces
  "$CAP" heavy "other session" --session dup2 >/dev/null 2>&1
  assert_eq "different session appends" "2" "$(wc -l < "$AGENT_MATURITY_CAPTURES" | tr -d ' ')"
  rm -rf "$TMP"
}

# --- session-less capture is allowed ---
test_sessionless(){
  new_env
  "$CAP" light "quick win, no session" >/dev/null 2>&1 && ok "session-less capture works" || no "session-less capture works"
  python3 -c 'import json,sys; o=json.loads(sys.stdin.readline()); sys.exit(0 if "session_id" not in o else 1)' < "$AGENT_MATURITY_CAPTURES" && ok "omits session_id when absent" || no "omits session_id when absent"
  rm -rf "$TMP"
}

# --- the separation guarantee: capture NEVER writes interventions.jsonl ---
test_separation(){
  new_env
  "$CAP" heavy "must not touch interventions" --session iso1 >/dev/null 2>&1
  if [ -e "$AGENT_MATURITY_DATA_DIR/interventions.jsonl" ]; then no "captures never write interventions.jsonl"; else ok "captures never write interventions.jsonl"; fi
  rm -rf "$TMP"
}

test_valence
test_record
test_arg_order
test_update_in_place
test_sessionless
test_separation

echo
echo "capture tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
