---
name: scope-gate
description: Produce and review a pre-execution scope before writing code on a non-trivial task. Declares the approach, runs one clean-context critic, and presents interactive scopes in a lightweight Lavish approval page. Invoked when the agent self-classifies work as non-trivial or the scope-gate hook blocks an edit.
---

# Scope Gate

Force scoping **before** code on non-trivial tasks, to cut the scope-redirection
clarifications that otherwise land after an approach is already chosen. Produces a
canonical Markdown **brief** that is both the gate marker (the PreToolUse hook checks
for it) and the measurement artifact (`/harvest-interventions` reads it). Interactive
tasks use a lightweight Lavish page to review that scope; the HTML is an ephemeral
presentation layer, not another source of truth.

**This is a Spec L2→L3/L4 lever. Retirement trigger:** when agent-initiated
scope-question precision is high AND clarifications/PR is flat, this gate is no longer
load-bearing — `/maturity-review`'s ablation check should flag it for removal.

## When this runs

- The agent self-classified the current task as **non-trivial** (see the injected
  triage rubric), or
- The `scope-gate-pretooluse.sh` hook **blocked** an Edit/Write with "no scoping
  decision recorded".

## Triage first

Apply the rubric. **Non-trivial** if any: an approach/design choice; a new/changed
public interface, type, endpoint, or schema; multi-file or multi-system work; a
"make it X" architectural ask; multi-part (PR-decomposition) work; or you are unsure.
**Default to non-trivial when unsure.** **Trivial** = one obvious, cheaply-reversible
change, no new interface, no approach fork.

If trivial, take the **`--trivial` path**: write a brief with `"triage":"trivial"` and
a one-line `trivial_reason`, then proceed to code. Do not over-scope trivial work.

## Procedure (non-trivial)

1. **Provision the data store** (fast no-op once set up):

       bash $AGENT_MATURITY_HOME/scripts/ensure-maturity-data.sh

   This creates `$AGENT_MATURITY_DATA_DIR/briefs` even if provisioning fails. If it
   reports gh isn't authenticated / repo inaccessible, **do not stop** — warn the user
   that the brief won't sync until that's resolved, then still write the brief locally
   (step 7) so the gate is satisfied and work isn't wedged. It will sync on a later run.

2. **Restate** the task in one line + **pass-to-pass acceptance checks** — concrete,
   checkable conditions that define done.

2b. **Declare the approach** — state the key implementation choices you intend *before*
   writing code, one line each. Cover whichever apply: which API/SDK/library, runtime
   resolution vs codegen, reusing an existing abstraction vs a new one, a real fix vs a
   workaround. Note a rejected alternative + one-line why-not where it's a genuine fork.
   These are the choices the human otherwise only sees in review — surfacing them here is
   the point of the gate. Declare what's true for *this* task; don't copy examples.

3. **Propose a PR-decomposition** if the work is multi-part: an ordered list of
   independently-shippable parts.

4. **Batch genuine scope questions** — only real blockers and approach forks
   (precision over volume). For each, either get an answer or record an explicit
   assumption.

5. **Run exactly one clean-context scope critic.** Dispatch a read-only general-purpose
   subagent with the task, acceptance checks, approach, decomposition, and questions. Let
   it inspect relevant repository context, but do not let it edit or implement. Its output
   is limited to three high-confidence findings in this shape:

   ```text
   Decision at risk: <the proposed choice>
   Evidence: <specific repository fact or external constraint>
   Alternative or question: <one actionable fork>
   ```

   The critic returns `No findings` when there is no concrete fork. It does not rewrite the
   scope, produce a full plan, add generic risks, or review wording. Do not run a second
   critic by default. If subagents are unavailable, state that the critic was skipped and
   continue; this quality check must not wedge the gate.

6. **Approval (mode-dependent):**
   - **Interactive** (default): use Lavish when available. Load the `lavish` skill and read
     its `input` playbook; read `comparison` only when there is a genuine choice between
     alternatives. Do not use the full `plan` playbook for an ordinary scope review.
     Generate `/tmp/agent-maturity-scope-<session_id>.html` as a compact decision
     surface containing:
     - the outcome in one sentence;
     - concrete acceptance checks;
     - each approach decision with its rationale and any rejected alternative;
     - the critic's findings, visually distinguished from accepted decisions;
     - PR decomposition only when the work is genuinely multi-part;
     - unresolved questions or assumptions; and
     - one explicit approval control that sends `Scope approved. Write the canonical brief
       and proceed.` back to the agent.

     Keep the page materially lighter than an implementation plan. Prefer a one-screen,
     scan-friendly layout; omit command lists, file-by-file steps, and resolved questions.
     Users can annotate any element or selected text for detail. Run
     `npx -y lavish-axi <html-file>`, resolve its local URL through the host's configured
     browser-exposure helper when one exists, give the user the resulting URL, then poll
     with `npx -y lavish-axi poll <html-file>` following the Lavish skill's long-poll guidance.
     If feedback requests changes, apply it to the scope and page, then poll again. If the
     poll returns explicit approval, stop polling and continue. **Wait for explicit
     approval** before writing code. If Lavish or `npx` is unavailable, fall back to
     presenting the same compact scope in chat and ask once for approval.
   - **Autonomous** (`$AGENT_MATURITY_AUTONOMOUS=1`, or a Claude background job with
     `$CLAUDE_JOB_DIR` set): do not create a Lavish page and do not wait. Resolve critic
     findings conservatively, record each open question as an `assumed` resolution, proceed
     to code, and surface the approach declaration and assumptions in the PR description
     for async review.

7. **Write the canonical brief** after interactive approval or immediately after the
   autonomous critique. Use the Write tool (this path is floored, so the hook allows it)
   to write:

       $AGENT_MATURITY_DATA_DIR/briefs/<YYYY-MM-DD>-<session_id>.md

   Use the `session_id` from the `[scope-gate] (session: …)` line the
   UserPromptSubmit hook injected. If you don't have it, check that line in context.

   The brief is **markdown**: a small YAML frontmatter *envelope* (the only fields
   anything indexes on — keep it stable) plus a **free-form body**. Nothing parses the
   body field-by-field — the existence hook checks the filename, and the harvester reads
   it with an LLM — so write the body as legible prose under headings, not a rigid schema.
   Include the sections that apply; omit what doesn't (e.g. skip PR-decomposition when the
   work is a single PR). For a trivial task, set `triage: trivial` in frontmatter and give
   a one-line reason in the body — nothing more.

   ```markdown
   ---
   session_id: ...
   created_at: <YYYY-MM-DD>
   mode: interactive | autonomous
   triage: non-trivial | trivial
   covers:
     - <path or glob this brief scopes>
   ---

   # Task
   <one line>

   ## Acceptance checks
   - <concrete pass-to-pass condition>

   ## Approach
   - <key implementation choice for THIS task; rejected alt + why-not where it's a fork>

   ## PR decomposition
   <ordered independently-shippable parts, or a one-line "single PR — <why>">

   ## Questions
   - <blocker> — answered: <answer> | assumed: <assumption>
   ```

8. **Sync** so the brief persists off the ephemeral env:

       bash $AGENT_MATURITY_HOME/scripts/sync-maturity-data.sh "scope-gate: brief <session_id>"

9. **Proceed to code.** Retry the edit that was blocked (the hook now finds the brief).

## Notes

- The scope and its Lavish page are intentionally lightweight. If review comments expose
  unresolved architecture, sequencing, or migration work, escalate to the client's full
  planning workflow instead of expanding the scope page into a plan.
- Accepted decisions belong in the Markdown brief. End the Lavish session and delete its
  temporary HTML file when approval is complete.
- One brief per session covers the session (v1). If a genuinely new non-trivial task
  begins mid-session, re-run this skill to write a fresh brief.
