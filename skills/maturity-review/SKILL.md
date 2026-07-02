---
name: maturity-review
description: Assess your agent-autonomy maturity and recommend the single highest-leverage next move. Use only when explicitly invoked (e.g. "/maturity-review", "where am I on the autonomy journey", "score my agent setup", "what should I uplevel next"). A periodic meta-eval of the agent harness itself, not a code task.
disable-model-invocation: true
---

# Maturity Review

A recurring meta-eval of your multi-agent setup: score where the harness sits on the
autonomy maturity model, ground it in evidence, recommend the one next move, and update the
tracker. This is the "treat the harness as a product / eval your own setup" discipline made
into a checkpoint — run it roughly monthly or after a meaningful harness change.

The goal being measured is **less human attention per shipped change**. Score outcomes, not
inventory: a capability counts only when it's *load-bearing in the real loop*, not when it
merely exists somewhere.

## Inputs (read these first — don't work from memory)

- `$AGENT_MATURITY_HOME/rubric.md` — the model, dimensions, and scoring procedure.
- `$AGENT_MATURITY_DATA_DIR/tracker.md` — current scorecard, last recommendation, changelog.
- `$AGENT_MATURITY_DATA_DIR/interventions.jsonl` — raw intervention signal (may be sparse/empty early on; say so rather than inventing a baseline).

## Procedure

0. **Provision the private data store** (always first — the tracker + log live in a private repo,
   symlinked in lazily at skill time since gh is authed now):

       bash $AGENT_MATURITY_HOME/scripts/ensure-maturity-data.sh

   If it reports gh isn't authenticated / repo inaccessible, stop and tell the user.

1. **Read** the three inputs above.

2. **Gather evidence** (pragmatic — this is signal, not an audit). Prefer cheap reads:
   - Intervention log: counts by `type` over the window since the last review, total cost_min.
     Also break down by **`tags`** (the orthogonal what-kind facet, vocabulary in
     `$AGENT_MATURITY_HOME/tags.md`): report counts per tag and, for any tag tied to
     a live hypothesis or the previous review's recommended move (e.g. `verify-fail` for a
     verification gate), state its trend vs last window — that tag IS the ablation signal for
     whether the lever worked. `grep '"<tag>"' interventions.jsonl` is the primitive.
   - GitHub, for recent agent-authored PRs (ask which repos if unclear; default to the active one):
     `gh pr list --author "@me" --state merged --limit 30 --json number,title,reviewDecision,createdAt,mergedAt`
     and for a sample, review round-trips / post-handoff force-pushes / time-to-merge as Trust signal.
   - The skills/plugins actually wired into the loop (what gates completion vs what's opt-in).
   - **Recurring-imperative clusters** from the latest `/harvest-interventions` run (its
     `recurring_imperatives`): a frequent `candidate_default:true` cluster is both a correction to
     the per-turn undercount (Trust/Babysit friction hides in instructions the human keeps
     re-issuing, which single-turn classification misses) and a ready-made lever candidate for
     step 6 ("wire up a standing default for X"). If there's no recent harvest, note it.
   If evidence is thin, score provisionally and **say what data would firm it up** — never
   inflate a level on hope.

3. **Score** each dimension L1–L5 per the rubric's procedure. Overall = the weakest dimension.
   For each, cite the specific evidence that pins the level (and the missing criterion that
   blocks the next level).

4. **Compute the north star** — interventions per merged agent-PR (total + per type) — and
   state the trend vs the previous tracker entry. If no baseline, set one.

5. **Ablation + harness re-read** (before recommending, so retirement candidates compete as the
   one move):
   - *Ablation* — look at the previous changelog entry: did that harness change move the metric?
     If not — or if it was **recommended but never built** and the metric moved anyway — name it
     as candidate scaffolding to retire. A recommended-but-unbuilt lever whose bottleneck then
     receded is a **do-not-build** flag, not a backlog item (don't accrete against a problem that
     moved).
   - *Model-upgrade trigger* — if the agent's model tier changed since the last review, re-read
     the **whole** harness (every gate/hook/skill) and flag anything the model now does for free
     as a retirement candidate. (LOOPS.md rule VIII.)

6. **Recommend exactly one next move** — the highest-leverage lever on the weakest / most-painful
   dimension. The one move may be **additive** (wire up a capability) **or a retirement** (remove
   scaffolding the model has outgrown); retirement candidates from step 5 compete on equal footing,
   and a removal that buys the most clarity/speed *is* the recommendation. **Prefer wiring up an
   asset you already own** (e.g. `full-verification-workflow`, `review-pr`, `simplify-pr`, the
   ai-platform eval skills, worktree/background-job orchestration) over building new; prefer
   deleting dead scaffolding over either. Still exactly one move — named concretely, with how
   you'll know it worked.

7. **Update the tracker**: rewrite the scorecard table (point-in-time) + "Last reviewed" date,
   **append one row to the "North-star history" table** (append-only trend line — never
   overwrite prior rows; numbers only, caveats go in the changelog), replace the "Recommended
   next move" section, and append a changelog entry (`date — what changed — metric impact: TBD`).
   Leave `interventions.jsonl` alone (that's logged live, not here).

8. **Sync the private data store** so the updated tracker persists off this ephemeral env:

       bash $AGENT_MATURITY_HOME/scripts/sync-maturity-data.sh "review: <date> baseline/update"

## Output

Keep it tight — a checkpoint, not an essay:

- **Scorecard**: the table (Trust / Spec / Babysit / Overall) with one evidence line each.
- **North star**: the rate + trend (or "baseline set").
- **Ablation**: did the last change pay off — and is anything now a retirement/do-not-build candidate? (one line)
- **Next move**: the single recommendation (additive **or** a retirement) — what, why this one, expected metric effect, how to verify.

Then state plainly that the tracker has been updated.

## Populating the log (remind the user if it's stale)

The scoring is only as good as the raw log. Two ways to fill it — prefer the first:

- **`/harvest-interventions`** (low effort) — a subagent reconstructs interventions from
  session transcripts + git + PR history over a window and proposes entries to confirm. Run
  this if the log looks stale relative to recent agent activity, then re-score.
- **`li` / `log-intervention.sh`** (manual escape hatch) — `li <correction|clarification|unblock>
  "note" [cost_min]`, run from inside the repo. For interventions artifacts can't see (a
  hand-edit with no agent session). `correction→Trust, clarification→Spec, unblock→Babysit`.

If the log is stale, suggest `/harvest-interventions` before scoring rather than scoring thin data.
