---
name: harvest-interventions
description: Reconstruct the agent-maturity intervention log from coding-agent transcripts, git history, and PR review cycles instead of logging by hand. Supports Claude Code, Codex, and OpenCode. Use only when explicitly invoked (e.g. "/harvest-interventions", "backfill my intervention log", "harvest interventions for the last 2 weeks", "populate the maturity log automatically"). Pairs with /maturity-review — run this first to give it data.
disable-model-invocation: true
---

# Harvest Interventions

Make Phase 1 of the maturity system zero-effort: instead of running `li` in the moment every
time you step in, a subagent mines the artifacts you already produce and proposes intervention
log entries. You glance, confirm, and it writes them. Backfills the past immediately — no
two-week wait.

**This is approximate, and that's fine.** It reconstructs from evidence, so it will miss
interventions that left no trace (a hand-edit in your editor with no agent session) and may
mis-bucket a few. The human-confirm step is the accuracy gate; the goal is a good-enough
baseline at ~10× less effort than moment-logging, not a perfect ledger. `li` stays the
escape hatch for things artifacts can't see.

## Inputs

- **Repo** — default: the current repo (`git rev-parse --show-toplevel | xargs basename`).
  Ask if the user named several; harvest one at a time so the confirm step stays legible.
- **Window** — default: last 14 days. Honor an explicit range if given.
- **`--session <id>` / `--session current`** — optional. Switches to **session-scoped mode**
  (see below): mine exactly one conversation instead of a repo+window. This is what
  `capture-conversation` calls for an opt-in "harvest this convo while it's fresh", and what
  reconciles a flagged session against the count later.
- Target log: `$AGENT_MATURITY_DATA_DIR/interventions.jsonl`.

## Session-scoped mode (`--session`)

When invoked with `--session <id>` (or `--session current`):

- **`current`** resolves to the session id on the `[scope-gate] (session: <id>)` line the
  UserPromptSubmit hook injects into context.
- Locate the session through each supported client's public artifact:
  - Claude Code: the matching `~/.claude/projects/*/<id>.jsonl` or
    `$AGENT_MATURITY_DATA_DIR/evidence/*/projects/*/<id>.jsonl` file.
  - Codex: the rollout JSONL whose filename contains the id under `~/.codex/sessions/`.
  - OpenCode: `opencode export <id> --sanitize`, written to a temporary JSON file for mining.
  Reading/exporting at harvest time includes turns added after an earlier capture.
- **Skip** the repo+window default and steps 0b/0c (no cross-env sweep, no brief aggregation —
  this is one conversation, fresh). Still run 0a (provision the data store).
- Dispatch the step-1 mining subagent against **only that one transcript file**, with the same
  classification rules (source A). Sources B/C (git, PRs) don't apply to a single session.
- Run the same human-confirm gate (step 2+) and write to the same `interventions.jsonl`.
- The client and session id are stamped in each entry's `evidence`
  (`<client> transcript <id>#turnN`);
  this lets a later batch run skip sessions already harvested this way and avoid double-proposing.

## Procedure

### 0a. Provision the private data store (always first)

The log + tracker live in a PRIVATE repo, symlinked in lazily at skill time (gh is authed now,
unlike at env-provisioning time). Run this first — it's a fast no-op once set up:

    bash $AGENT_MATURITY_HOME/scripts/ensure-maturity-data.sh

If it reports gh isn't authenticated or the repo is inaccessible, stop and tell the user
(can't read/write the log without it).

### 0b. Refresh cross-env Claude evidence if stale

Work happens across many ephemeral Ona envs, so the local Claude transcript directory is only
a slice. Before mining, check the evidence freshness. Codex and OpenCode local artifacts are
read directly in step 1; the current Ona collector only sweeps Claude's remote artifacts.

- Read `$AGENT_MATURITY_DATA_DIR/evidence/_manifest.txt` → `collected_at`.
- **Run `scripts/collect-ona-evidence.sh` (running-only) if** the manifest is missing, older
  than ~6 hours, or the user passed `--refresh`. Otherwise skip it and say "evidence is fresh
  (collected <when>), skipping collection."
- **Never** run it with `--include-stopped` automatically — that starts stopped envs and costs
  compute. Only do that if the user explicitly asks.
- If collection partially fails (some envs unreachable), proceed with whatever evidence exists;
  note which envs were skipped. Collection is best-effort, not a hard gate.

### 0c. Read scope-gate briefs (the gate's measurement substrate)

If `$AGENT_MATURITY_DATA_DIR/briefs/` has entries in the window, summarize them for
`/maturity-review`. Briefs are markdown (frontmatter + body); older ones may be `.json` —
read both. Frontmatter carries `triage`/`covers`; the body carries the Approach, acceptance
checks, and questions in prose.

- **scoped-before-code rate** = non-trivial briefs ÷ (non-trivial briefs + non-trivial
  tasks that reached code with no brief, inferred from transcripts). Report the count
  of briefs by `triage`.
- **Ask-F1 inputs** — count batched up-front questions in briefs vs. clarifications
  that still landed *later* in the same session's transcript. Falling later-clarifications
  with steady up-front question precision = the gate working.
- **approach-divergence rate** = clarifications tagged `wrong-approach` / `scope-redirect`
  whose correction *contradicts an Approach line the brief already declared* ÷ non-trivial
  briefs in the window. This is the number the approach-declaration lever targets: redirects
  the pre-code declaration should have surfaced but didn't. Drive it toward zero. Judge it
  semantically (does the redirect reverse a declared choice?), same as any intervention
  classification. **Distinguish** from *novel* approach forks not in any declaration — those
  are the gate working (the human confirming a fork the agent surfaced early), not a miss.

Report these as a short block; `/maturity-review` consumes them in its Spec scoring and
ablation check. If `briefs/` is empty (gate not yet exercised), say so.

### 1. Dispatch a mining subagent

Spawn a `general-purpose` subagent (keeps the noisy parsing out of the main context). Give it
the repo, the window, and these instructions verbatim:

> Mine three sources for human interventions on AI-agent coding work in **<repo>** over **<window>**.
> Return ONLY a JSON object — no prose. Be conservative; when unsure, omit.
>
> **A. Coding-agent transcripts** (richest source). Mine all available supported clients:
>   - **Claude Code:** `~/.claude/projects/` plus
>     `$AGENT_MATURITY_DATA_DIR/evidence/*/projects/`. Include the repo's main directory and
>     worktrees. Parse `*.jsonl` files modified within the window. A human turn has
>     `type=="user"` and textual `message.content`.
>   - **Codex:** rollout `*.jsonl` files under `~/.codex/sessions/` modified within the window.
>     Use the rollout's role/type fields to identify genuine user and assistant messages; the
>     format is not a stable API, so inspect fields rather than assuming Claude's schema.
>   - **OpenCode:** run `opencode session list --format json`, select sessions for this repo and
>     window, then run `opencode export <session-id> --sanitize` for each selected session into
>     a temporary directory. Mine the exported message roles and text. Never query OpenCode's
>     private SQLite schema. Remove the temporary exports after mining.
> De-duplicate by `<client>:<session-id>`. Exclude tool results and harness-injected context
> (command wrappers, system reminders, scope-gate text, and skill boot text). Walk turns in
> order and classify each genuine human turn *relative to the preceding assistant turn*:
>   - **task** — a fresh task statement / new feature ask → NOT an intervention; count it
>     toward the task denominator only.
>   - **correction** (Trust) — points out a bug, says it's wrong, asks to redo/fix/revert
>     something the agent produced.
>   - **clarification** (Spec) — redirects the approach, adds/restates requirements, answers
>     an agent question with new constraints, "no, I meant X", "use the GraphQL resolver not REST".
>   - **unblock** (Babysit) — restarts a stalled/looping agent, resolves an error or merge
>     conflict for it, "you're stuck, try Y", "continue".
> Also COUNT explicit agent-initiated questions (including Claude `AskUserQuestion` calls and
> equivalent Codex/OpenCode question tools or clear assistant questions) — report the count
> separately; these are a positive Spec signal, not interventions.
>
> **Tag each proposal** with 0+ slugs from the canonical vocabulary in
> `$AGENT_MATURITY_HOME/tags.md` (READ THAT FILE FIRST — it is the single source of
> truth). Tags are an orthogonal "what-kind" facet, independent of `type`: e.g. a `correction`
> that was a hand-off-without-running gets `["verify-fail"]`; a `clarification` that split a PR
> gets `["scope-redirect"]`. Assign only tags you're confident in (omit rather than guess); use
> the empty array when no sub-kind clearly fits. If a clear pattern recurs that no existing tag
> names, you MAY mint a new kebab-case slug AND list it under a `"new_tags"` field (slug → one-line
> definition) so it can be added to `tags.md` — but prefer reusing an existing tag.
>
> **B. Git history.** On branches with commits in the window: agent commits carry a
> `Co-Authored-By: Claude` trailer. Human commits **without** it that directly follow agent
> commits, or are "fix"/"revert"/"oops" fixups, corroborate **corrections**. Report shas.
> **Caveat (2026-06-15):** the `Co-Authored-By: Claude` trailer is no longer a reliable
> agent-vs-human signal — treat all PRs as AI-generated. Use this source only as weak
> corroboration for corrections; prefer transcript turns (source A) and scope-gate
> briefs (step 0c) as the authoritative per-task signal. The north-star denominator is
> "merged PRs", not "merged agent-PRs".
>
> **C. PRs** (`gh pr list`/`gh pr view`, author=@me, merged or open in window). Count review
> round-trips / "changes requested" cycles → corroborating **correction** signal. Report PR #s.
>
> **D. Recurring human imperatives (cross-session).** Beyond classifying each turn in isolation,
> look ACROSS the sessions you read for **instructions the human issues repeatedly that the agent
> could have done unprompted** — e.g. "did you test it / show evidence", "run typecheck", "tighten
> the comments", "handle the error case", "check the logs". Cluster them by *meaning*, not wording
> (there is NO fixed phrase list — infer the clusters from what actually recurs; new frictions
> should surface on their own). For each cluster recurring across **≥3 distinct sessions**, report a
> one-line gloss, the distinct-session count, total occurrences, one short example quote, the
> underlying `type` (so it reconciles with the counts above), and a `candidate_default` flag — would
> a standing default (context-prime or a gate) plausibly remove this instruction? This is the generic
> signal behind "if you keep typing X, automate it": each frequent cluster is simultaneously an
> **undercounted intervention** and a **candidate lever** for `/maturity-review`. Do not enumerate
> clusters below the 3-session floor; note if you truncated a long tail.
>
> Output schema:
> ```json
> {
>   "repo": "<repo>", "window": "<from>..<to>",
>   "task_count": <int>,
>   "agent_initiated_questions": <int>,
>   "proposals": [
>     {"date":"YYYY-MM-DD","type":"correction|clarification|unblock",
>      "note":"<short, what happened>","source":"auto","client":"claude|codex|opencode|git|github",
>      "model":"<model slug when present in the artifact>","tags":["<slug>", ...],
>      "evidence":"<client> transcript <id>#turn<N> | commit <sha> | PR #<n>","confidence":"high|med|low"}
>   ],
>   "recurring_imperatives": [
>     {"gloss":"<the instruction the human keeps issuing>","type":"correction|clarification|unblock",
>      "sessions":<int>,"occurrences":<int>,"example":"<short quote>","candidate_default":true|false}
>   ],
>   "new_tags": {"<new-slug>": "<one-line definition>"}
> }
> ```
> Cap at the clearest ~40 proposals; if you truncated, say so in a `"truncated":true` field.
> Omit `new_tags` (or use `{}`) if you minted none.

### 2. Present for confirmation (compact)

From the subagent's JSON, show the user a tight summary — **don't** dump all rows:
- counts by type (correction / clarification / unblock), task_count, agent_initiated_questions
- **tag breakdown** — counts by tag (highlight any the user is tracking a hypothesis on, e.g.
  `verify-fail`), so the sub-metric is visible at confirmation time
- 2–3 example notes per type
- flag any `low` confidence rows separately
- if the subagent returned `new_tags`, surface them and ask whether to adopt them into `tags.md`
- **recurring imperatives** — list the top clusters (gloss, distinct-session count,
  `candidate_default`), highest-frequency first. These are *automation candidates*, not log rows
  to confirm — they feed `/maturity-review`'s next-lever step, so don't ask to write them; just
  show them and carry them forward.

Then ask one question: **write all, prune some, or discard?** Offer "write all" as the default
for the lazy path. If they prune, take the list of indices to drop.

### 3. Write

Append the confirmed proposals to `interventions.jsonl` (a symlink into the private repo), one
compact JSON line each, preserving `source:"auto"`, `client`, `model` when known, `evidence`,
`confidence`, and `tags` (write `tags` as a JSON array; omit the key or use `[]` when none).
Don't rewrite or dedup existing lines.
If the user adopted any `new_tags`, add them to `$AGENT_MATURITY_HOME/tags.md` under the
right group before writing. Report how many were written and the resulting per-type **and per-tag**
totals.

### 4. Sync the private data store

Persist the writes off this ephemeral env:

    bash $AGENT_MATURITY_HOME/scripts/sync-maturity-data.sh "harvest: +N interventions"

### 5. Hand off

Tell the user the log is populated and to run **`/maturity-review`** next for the evidence-based
baseline. Mention the `agent_initiated_questions` count — it feeds the Spec supporting signal
(agent-initiated question rate) that `/maturity-review` reports. Also carry forward the
`recurring_imperatives` clusters: `/maturity-review` weighs them as candidate levers — a frequent
`candidate_default:true` cluster is a ready-made "wire up a standing default" recommendation, and
the count is the honest read on Trust/Babysit friction the per-turn classification undercounts.

## Notes

- Re-running over an overlapping window will double-log. Either harvest forward-only (window
  starts after the last harvested date) or tell the user to dedup. Prefer non-overlapping windows.
- Sessions about non-coding work (e.g. building this maturity system itself) aren't product
  interventions — the subagent should skip or down-weight them; the user prunes the rest.
