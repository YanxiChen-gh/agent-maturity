---
name: capture-conversation
description: Flag the CURRENT conversation as a subjective signal in agent-maturity data. Use when the user says "capture this convo", "capture this conversation in maturity data", "log this conversation to maturity", "flag this convo as heavy/light", "this convo was heavy/painful/grindy", or "this one went surprisingly smoothly" and wants it marked for maturity review. Writes one heavy/light valence flag to captures.jsonl (a SEPARATE track from counted interventions) and then offers an opt-in deep harvest while context is still fresh.
---

# Capture Conversation

Record a **subjective** read of the current conversation — how much attention it actually
cost you — as a flag in agent-maturity data. This is the human's signal, deliberately kept
on its own track (`captures.jsonl`) so it can never be silently folded into the objective
interventions/PR north star. Its payoff is **calibration**: when "felt heavy" diverges from a
low intervention count, the count is under-measuring attention; "felt light" on hard work is a
win worth recording. Both directions matter — don't only capture the painful ones.

## What this is NOT

- It does **not** add a counted intervention. For that, the human runs `li` or confirms a
  `/harvest-interventions` proposal. A capture is a separate, non-counted flag.
- It does **not** invent a `weight`. See step 3 — weight is the human's to author.

## Procedure

### 1. Resolve the session id

The flag attaches to an agent session so a later harvest can mine its transcript. Get the id
from the `[scope-gate] (session: <id>)` line the UserPromptSubmit hook injects into context
(it appears on every turn). If it isn't present, derive it from the Claude or Codex transcript
path, use the OpenCode session id, or ask the user. A session-less flag is
allowed but loses the later deep-harvest option, so prefer to resolve it.

### 2. Determine valence from the user's phrasing

- **heavy** — "this was painful / grindy / lots of back-and-forth / I had to hold everything
  in my head / more work than it looks." Cost MORE attention than the count will reflect.
- **light** — "the agent nailed it / surprisingly smooth / barely touched it." A win: LESS
  attention than the task's difficulty would predict.

If the phrasing is genuinely ambiguous, ask one short question. Don't guess.

### 3. Weight — human-authored only

If the user stated an intensity ("call it a 4", "very heavy"), record it as an integer 1-5.
You MAY propose one to help them ("felt like a 3 — three redirects and a revert?"), but record
ONLY a value they confirm. If they don't give one, **omit weight**. Never author a weight
yourself: an agent-derived weight just re-computes the objective count and destroys the very
independence that makes this flag useful.

### 4. Write the flag

Provision the data store, write the capture, then sync so it survives env teardown:

    bash "$AGENT_MATURITY_HOME/scripts/ensure-maturity-data.sh"
    "$AGENT_MATURITY_HOME/scripts/capture.sh" <heavy|light> "<one-line why>" [weight] [tags] --session <id>
    bash "$AGENT_MATURITY_HOME/scripts/sync-maturity-data.sh" "capture: <valence> <session>"

`note` should be one line in the user's framing. `tags` (optional) reuse the canonical
vocabulary in `$AGENT_MATURITY_HOME/tags.md` — read it before tagging; omit rather than guess.
Re-running for the same session updates the flag in place, so it's safe to refine.

### 5. Offer an opt-in deep harvest (while context is warm)

The flag is instant and done. Now offer — don't force — the expensive step:

> Want me to mine this session for interventions now while it's fresh? The confirm step is far
> more accurate right after the conversation than in the month-end batch.

- **Yes** → invoke `/harvest-interventions --session <id>` (session-scoped mode) and walk the
  proposals through the normal human-confirm gate.
- **No** → done. The flag is recorded; the regular batch harvest will pick up the session
  later (the transcript keeps growing, so later turns are included whenever it runs).

## Notes

- The capture and any later-confirmed interventions are independent records. A heavy flag with
  zero confirmed interventions is a legitimate, informative state — it's exactly the
  divergence `/maturity-review` surfaces.
- One flag per session (update-in-place). If a single session genuinely splits into two very
  different stretches, capture the dominant one and note the nuance in the `note`.
