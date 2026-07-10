---
name: loop-run
description: Run maker/checker cycles — implement via Codex CLI or Claude per loop.config.md, verifier grades — until the rubric passes; supports --once and --verify-only
argument-hint: "[--once | --verify-only]"
disable-model-invocation: true
---

# loop-run — verified maker/checker cycles

Arguments (`$ARGUMENTS`): `--once` = exactly one cycle. `--verify-only` = grade once, report, write NOTHING (no marker, no state updates — strictly read-only).

## Before anything

1. No `.claude/loop/`: tell the user to run `/loopy:loop-init` and stop.
2. Read, in order: `state.md` (entry point — resume from its unresolved list), `goal.md`, `rubric.md`, `loop.config.md`, and `memory.md`'s `## Distilled rules`.
3. **Preflight** (skip for `--verify-only`): choose the implementer (codex vs claude) and write the run marker — procedure in `references/preflight.md`.

## --verify-only path

Spawn the `verifier` agent with "grade `.claude/loop/rubric.md`". Print its report verbatim plus a one-paragraph summary. Update no file, then stop.

## Cycle (repeat until a stop condition)

1. **Implement** by the implementer chosen at preflight:
   - **claude** (or any fallback): pick the unresolved rubric criteria (from state.md), make the smallest change that could pass them — skip any approach under `## Approaches tried`. Prefer the cheap `explorer` agent for reconnaissance over broad main-context reading.
   - **codex**: ONE fresh `codex exec` per cycle, never `resume`, prompt rebuilt from disk each cycle. Full procedure (prompt construction, the exact command, retry/fallback) in `references/codex-exec.md`.
2. **Phase gate — end of cycle only:** spawn the `verifier` once with "grade `.claude/loop/rubric.md`". Never invoke it per file edit; it only reports.
3. **Apply the report** — the main agent does ALL updates to `rubric.md`, `state.md`, `memory.md`, and `review.md`. Exact fields and rules: `references/apply-report.md`.

## Stop conditions

- **Success:** every rubric criterion passes → do NOT stop yet. Run the green gate ONCE (full runs only) before declaring done — procedure in `references/green-gate.md`.
- **Safety rails (mandatory, never skip):**
  - iteration count would exceed `max_iterations` (loop.config.md) → stop, record the reason in state.md.
  - the same criterion failed 3 consecutive cycles → do NOT escalate yet. Replan first per the loop-engineering skill's `references/replan.md`: up to `replan_max` (default 2) genuinely different strategies (change approach / decompose / spike), **never weakening the criterion**. Only once replan is exhausted, escalate with 2-3 options (interactive: ask; headless: record them + the stall reason in state.md, set `human_gate: stalled`, end the turn).
  - An unbounded "repeat until pass" loop is forbidden.
- `--once`: stop after one full cycle regardless of outcome (state/memory/review still updated).

## Decision gates

Reversible/local actions (edits, tests, local commits, work-branch push, draft PR) act immediately — re-confirming one is over-confirmation. Irreversible/high-impact T2 (merge to a protected branch, release/publish, force-push, tag push, external send, cost, catastrophic delete) is a human gate `decision_gate.sh` enforces: write context to `review.md`, then interactive → ask; headless → set `human_gate: pending_t2` and end the turn. Full doctrine, the headless flow, and the `.gate-approved` marker protocol (never forge it): the loop-engineering skill's `references/decision-gates.md`.

Token note: you cannot measure your own usage; `.last-usage` (written by the stop gate at turn end) is the PREVIOUS run — report it as an estimate, never a precise figure.
