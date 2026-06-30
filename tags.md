# Intervention Tags (the "what-kind" facet)

Canonical tag vocabulary for `interventions.jsonl`. **Single source of truth** — `harvest-interventions`,
`li` (`log-intervention.sh`), and `/maturity-review` all read this list. Edit here, not in those.

## Why tags exist

The primary axis is `type` — `correction`→Trust, `clarification`→Spec, `unblock`→Babysit. That tells
you *which layer* costs attention. Tags are an **orthogonal facet** that tells you *what kind* of
intervention within that layer, so a hypothesis about one specific failure mode can be isolated and
trended instead of being averaged into the generic bucket.

Example: "a verification gate reduces hand-offs that weren't run" is only provable if those
interventions are tagged `verify-fail` — otherwise the effect hides inside the broader `correction` rate.

Rules:
- **0..n tags per entry.** Tags are optional; a clean entry with no clear sub-kind gets none.
- **Tags are orthogonal to type.** Any tag may appear on any type, though most lean toward one
  (noted below). Don't force a tag just because the type matches.
- **Greppable by design.** `grep '"verify-fail"' interventions.jsonl` is the measurement primitive.

## Vocabulary

Grouped by the dimension they usually attach to. The grouping is a hint, not a constraint.

### Trust-leaning (usually on `correction`)
- `verify-fail` — handed off without running/exercising the change; the "did you actually test this" prod.
- `ci-red` — handed off with failing CI / lint / typecheck the agent should have caught first.
- `logic-bug` — a real correctness/logic bug the human caught (in review or mid-task).
- `revert` — asked to undo/revert prior agent work.
- `quality-noise` — verbosity, over-engineering, unnecessary comments/tests; "cut this", "too prescriptive".
- `verbose-output` — model wrote verbose/redundant **code comments** or coverage-only/over-mocked tests; "cut the comments", "too verbose", "simplify this". A narrower, trendable subset of `quality-noise` isolating output *verbosity* (vs over-engineering / over-prescription) — often co-tagged with it. This is the ablation signal for any conciseness lever (model-specific: Opus 4.8 over-comments by default).

### Spec-leaning (usually on `clarification`)
- `scope-redirect` — approach or PR-decomposition redirect ("split this", "too much", "do X first").
- `spec-gap` — a missing/under-specified requirement surfaced after work started.
- `wrong-approach` — design/tool correction ("use the resolver not REST", "override the client instead").
- `env-flag-scoping` — feature-flag / environment / region scoping correction.

### Babysit-leaning (usually on `unblock`)
- `stuck-restart` — restarted a stalled or looping agent; "continue", "you're stuck, try Y".
- `env-broken` — fixed a broken dev env / server / dependency so the agent could proceed.

## Growing the vocabulary

When an intervention fits none of the above **and** you've seen the same shape recur (~3+ times),
mint a new kebab-case slug and add it here with a one-line definition. Don't proliferate
one-off tags — a tag earns its place by being trendable across reviews. If unsure, leave it
untagged; harvest can backfill once the pattern is named.
