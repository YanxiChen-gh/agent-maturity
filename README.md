# agent-maturity

> **Alpha / WIP — personal experiment.** A personal side project shared early to gather interest and feedback. Interfaces and the rubric will change without notice. Provided **as-is, with no warranty and no support or maintenance commitment** (see [LICENSE](LICENSE), MIT). Not an official tool of any employer; use at your own discretion.

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
3. **`capture`** flags a whole conversation as a *subjective* signal — `capture heavy "lots of back-and-forth"` or `capture light "agent one-shot it"`. Kept on a separate track (`captures.jsonl`), reported by review but never counted; the gap between "felt heavy" and the objective count is the calibration signal. Just say "capture this convo" to trigger the skill.
4. **`/harvest-interventions`** mines transcripts + git + PRs to reconstruct interventions you didn't log by hand, and proposes entries to confirm. `--session <id>` scopes it to one conversation.
5. **`/maturity-review`** scores the three dimensions from the log, computes the north star + trend, runs an ablation check on the last change, and recommends exactly one next move.

## Architecture: engine vs. data

This repo is the **engine** — generic, shareable, carries no personal data:

```
skills/   harvest-interventions, maturity-review, scope-gate, capture-conversation
scripts/  li (log), capture (subjective convo flag), ensure/sync data, scope-gate hooks, ona evidence collector
rubric.md tags.md   defaults (fork/customize per person)
install.sh
```

Your **data** lives in a separate PRIVATE repo you own (interventions log, tracker, scope-gate briefs, evidence), cloned lazily to `$AGENT_MATURITY_DATA_DIR` (default `~/.agent-maturity-data`). The engine never contains it. This split is what lets the tool be per-person/per-repo while the wiring stays common.

Two env vars are the whole config surface: **`AGENT_MATURITY_HOME`** (this repo, self-resolving) and **`AGENT_MATURITY_DATA_DIR`** (your data).

## Quickstart

One line (`gh` authenticated). `bootstrap.sh` clones-or-updates the engine, installs it, and
auto-creates your PRIVATE data repo if it doesn't exist yet:

```bash
curl -fsSL https://raw.githubusercontent.com/YanxiChen-gh/agent-maturity/main/bootstrap.sh \
  | bash -s -- --data-repo <you>/agent-maturity-data
```

Then open a new shell (or `source ~/.agent-maturity.env`) and:

```bash
/maturity-review            # scores your current state, sets a baseline
li clarification "use the resolver, not REST" wrong-approach
```

`install.sh` (run by `bootstrap.sh`, or directly) symlinks the skills into Claude Code's
`~/.claude/skills` and the shared `~/.agents/skills` path used by Codex and OpenCode. It writes
`~/.agent-maturity.env`, registers the scope-gate hooks for Claude Code and Codex, and ensures
your data repo exists. Codex asks you to trust changed user hooks once through `/hooks`.
It's idempotent; `--dry-run` shows what it would do; `--no-hooks` skips hooks.

OpenCode discovers the same skills from `~/.agents/skills`. Its hook API differs, so the
[Dotfiles](https://github.com/YanxiChen-gh/Dotfiles) integration installs an OpenCode plugin
that adapts `tool.execute.before` and prompt context to the engine's scope-gate scripts.

### Put it in your dotfiles

Drop this one line into your dotfiles' install/setup script — same line for everyone, the repo
does all the heavy lifting (re-runs just pull + reinstall):

```bash
curl -fsSL https://raw.githubusercontent.com/YanxiChen-gh/agent-maturity/main/bootstrap.sh \
  | bash -s -- --data-repo "<you>/agent-maturity-data" \
      --name "$(git config --global user.name)" --email "$(git config --global user.email)"
```

## Notes & limitations

- **Three supported clients.** Skills work in Claude Code, Codex, and OpenCode. Claude Code and
  Codex use their native lifecycle hooks; OpenCode needs the Dotfiles plugin adapter described
  above. The scripts and scoring model remain model-agnostic.
- **The Ona evidence collector is platform-specific** and currently sweeps only Claude transcripts from remote environments. Codex and OpenCode sessions are harvested locally. The collector is optional; the rest works without it.
- **Harvest is approximate.** It reconstructs from artifacts and mis-buckets some; the confirm step is the accuracy gate. `li` is the escape hatch for things artifacts can't see.
- **No autonomy *scoring* tool exists off the shelf** — backends like Langfuse only move where the raw log lives. The rubric + meta-eval are the point, and they're here.
