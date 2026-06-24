# agent-maturity

> **Alpha / WIP.** Interfaces and the rubric will change. Used daily by the author; sharing early to gather interest and feedback.

A personal, evidence-based system for answering one question: **am I spending less human attention per change my coding agents ship — and what's the cheapest next move that would help?**

It treats *your agent harness as a product* and runs a recurring meta-eval on it. Instead of vibes ("agents feel better lately"), you get a tracked number trended over time and a single recommended lever each review.

## The idea in one minute

Attention spent on agent work goes to three places. Each is scored L1→L5 and maps to a logged intervention type:

| Dimension | The question | Intervention |
|---|---|---|
| **Trust** | How much do I review/correct output before merge? | `correction` |
| **Spec** | How much do I decompose/clarify before an agent can start? | `clarification` |
| **Babysit** | How much do I unblock/coordinate while agents run? | `unblock` |

**North star:** *interventions per merged PR*, trended down. Overall level = your weakest dimension. The full model is in [`rubric.md`](rubric.md); the orthogonal "what-kind" tags are in [`tags.md`](tags.md).

## The loop

1. **`scope-gate`** (a skill + two hooks) forces a short scoping brief before code on non-trivial tasks — restate the task, acceptance checks, batch questions up front. Each brief is also a measurement artifact.
2. **`li`** logs an intervention in the moment: `li correction "handed off without running it" verify-fail`.
3. **`/harvest-interventions`** mines transcripts + git + PRs to reconstruct interventions you didn't log by hand, and proposes entries to confirm.
4. **`/maturity-review`** scores the three dimensions from the log, computes the north star + trend, runs an ablation check on the last change, and recommends exactly one next move.

## Architecture: engine vs. data

This repo is the **engine** — generic, shareable, carries no personal data:

```
skills/   harvest-interventions, maturity-review, scope-gate
scripts/  li (log), ensure/sync data, scope-gate hooks, ona evidence collector
rubric.md tags.md   defaults (fork/customize per person)
install.sh
```

Your **data** lives in a separate PRIVATE repo you own (interventions log, tracker, scope-gate briefs, evidence), cloned lazily to `$AGENT_MATURITY_DATA_DIR` (default `~/.agent-maturity-data`). The engine never contains it. This split is what lets the tool be per-person/per-repo while the wiring stays common.

Two env vars are the whole config surface: **`AGENT_MATURITY_HOME`** (this repo, self-resolving) and **`AGENT_MATURITY_DATA_DIR`** (your data).

## Quickstart

First, create your own PRIVATE data repo (once) — the engine never stores data:

```bash
gh repo create <you>/agent-maturity-data --private
```

Then bootstrap the engine. `bootstrap.sh` clones-or-updates and installs in one shot:

```bash
# Public repo / marketplace — true one-liner:
curl -fsSL https://raw.githubusercontent.com/YanxiChen-gh/agent-maturity/main/bootstrap.sh \
  | bash -s -- --data-repo <you>/agent-maturity-data

# Private repo (needs `gh` authenticated) — clone once, then bootstrap installs:
gh repo clone YanxiChen-gh/agent-maturity ~/agent-maturity
~/agent-maturity/bootstrap.sh --data-repo <you>/agent-maturity-data
```

> While this repo is private, the `curl | bash` form needs a token — use the `gh repo clone` path. Once it's public (or shipped as a Claude Code marketplace plugin), the one-liner works as-is.

Then open a new shell (or `source ~/.agent-maturity.env`) and:

```bash
/maturity-review            # scores your current state, sets a baseline
li clarification "use the resolver, not REST" wrong-approach
```

`install.sh` (run by `bootstrap.sh`, or directly) symlinks the skills into `~/.claude/skills`, writes `~/.agent-maturity.env`, and registers the scope-gate hooks. It's idempotent; `--dry-run` shows what it would do; `--no-hooks` skips hook registration.

## Notes & limitations

- **Claude Code first.** Skills + hooks target Claude Code. The scripts are portable bash; the model is tool-agnostic.
- **The Ona evidence collector is platform-specific** (sweeps Ona dev environments). It's optional — the rest works without it.
- **Harvest is approximate.** It reconstructs from artifacts and mis-buckets some; the confirm step is the accuracy gate. `li` is the escape hatch for things artifacts can't see.
- **No autonomy *scoring* tool exists off the shelf** — backends like Langfuse only move where the raw log lives. The rubric + meta-eval are the point, and they're here.
