---
name: loop-engineering
description: Loop engineering method — machine-verifiable stop conditions, maker/checker separation (Codex CLI or Claude as maker, a verifier subagent as checker), disk-based memory in .claude/loop/. Consult when designing or running agent loops.
---

# Loop Engineering

Design the system that prompts the agent instead of prompting the agent each turn. A loop = run → collect feedback → self-correct, repeated until a verifiable stop condition holds.

## Three principles (non-negotiable)

1. **The maker must not grade its own work.** Implementation belongs to the configured implementer (`implementer:` in loop.config.md — the Codex CLI when available, else the main agent); grading belongs to the `verifier` subagent: fresh context, read-only, `rubric.md` as its only standard. It returns a report; the main agent applies it to the loop files.
2. **"Done" is a claim, not a proof.** Every stop condition must be machine-checkable: a command that exits 0, a file that exists, an output that matches. Subjective criteria are banned from rubric.md.
3. **Memory lives on disk, not in context.** Everything the next session needs is in `.claude/loop/` — `state.md` is the entry point; a fresh session reads that directory and resumes where the loop stopped.

## Structure

Plugin = immutable logic (installed once per machine). `.claude/loop/` = mutable state (once per project, created by `/loop-harness:loop-init`): `goal.md`, `rubric.md`, `state.md` (summary rewritten each cycle, max 100 lines), `memory.md`, `review.md` (human review summary, every cycle), `loop.config.md` (the only stack-dependent file).

## Cycle shape

Implement (by the configured implementer — a fresh `codex exec` per cycle when `implementer: codex`, prompt rebuilt from disk state; never a resumed session) → verifier grades ONCE at cycle end (phase gate — never per file edit) → main agent updates rubric checkboxes, rewrites state.md, records memory per protocol, overwrites review.md. Safety rails are always on: `max_iterations` cap and 3-consecutive-failure escalation. An unbounded "repeat until pass" loop is forbidden.

## Decision gates

Before a side-effecting action, classify by reversibility × impact. Reversible/local (edits, tests, local commits, work-branch push) → act or delegate, never re-ask. Irreversible or high-impact (merge to a protected branch, release, publish, external send, cost, destructive delete) → stop at a human gate. `decision_gate.sh` enforces this class mechanically. The test is "can this be undone?", not "may I ask?".

## Cheap reconnaissance

Use the `explorer` agent (haiku, read-only) when a cycle needs codebase scouting before implementing — file maps, symbol locations, conventions. Don't spend main-context tokens on broad reading.

## When to read references/

- Zooming out to the whole method's macro architecture / leverage rationale (6 principles, 7 layers, why loops beat per-turn prompting) → `references/elite-loop-engineering.md`
- Writing or fixing rubric criteria, or a criterion feels subjective → `references/rubric-guide.md`
- Recording a failure, deciding what to distill, `[plugin]` vs `[project]` tagging → `references/memory-protocol.md`
- Running parallel loop tasks in git worktrees, merging results → `references/worktree-guide.md`
- Classifying an action, or wiring the gate hook/config → `references/decision-gates.md`
- A criterion keeps failing, or replanning vs escalating → `references/replan.md`

## Cost discipline

Loops, verifiers and subagents burn tokens. Prefer `--verify-only` (grade once) or `--once` (single cycle) before committing to a full run. Deterministic work (budget counting, hook verdicts, state parsing, token estimation) belongs in scripts, not prompts. Codex output never enters main context: its stdout goes to `.claude/loop/.codex-log`; the main agent reads only `.codex-last`. Codex-side usage is billed by OpenAI and absent from the token estimate.
