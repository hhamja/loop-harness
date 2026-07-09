---
name: loop-review
description: Comprehensively review a project's loop/harness engineering against the control plane — ETCLOVG coverage, maturity, and an adversarial red-team pass — writing a scored harness-review.md
argument-hint: [target-path]
disable-model-invocation: true
---

# loop-review — comprehensive harness review

Review a target project's agent/loop harness against the control plane (`${CLAUDE_PLUGIN_ROOT}/docs/loop-control-plane.md`) — not just whether the architecture exists, but whether its gates actually hold. Orchestrator-worker + maker≠checker: you (the main agent) are the orchestrator only — you spawn read-only reviewers, adversarially reproduce their findings, synthesize, and write the report. You never grade your own reading.

Complementary to `/loopy:loop-audit` (grades an initialized loop's *process*) and `loop-run --verify-only` (grades the *product*). This one grades the *architecture and its enforcement*, and works on any project — including one with no `.claude/loop/`.

Target path (`$ARGUMENTS`): default `.`.

## Procedure

1. **Fan out (parallel, read-only).** Spawn together, each returning one report and modifying nothing:
   - `loop-architect` — "diagnose the harness at `<path>` — ETCLOVG coverage + L0–L5 maturity". The structured spine.
   - `design-critic` — "adversarially red-team the harness at `<path>`: refute its compliance claims — gate bypasses, forgeable approvals, rubber-stamps, script bugs".
   - If `<path>/.claude/loop/` exists, also `auditor` (process adherence).
   For a large harness, add a few `explorer` scouts split by cutting plane (hooks/CI, gate scripts, agents, state templates) so coverage does not rest on one context.
2. **Reproduce, don't trust (§3).** A single checker rubber-stamps. For each `design-critic` hole a command can settle (e.g. a gate that should deny), reproduce it YOURSELF in a fresh temp dir (`mktemp -d` — never against the target's own files) by feeding the input to the actual script. Promote only reproduced holes to CONFIRMED; leave the rest PLAUSIBLE. Drop any that fail to reproduce.
3. **Synthesize (you write everything — maker≠checker for the review itself).** Merge into ONE report: an ETCLOVG table (PASS/PARTIAL/MISSING + cited evidence), `maturity: L<n>/5` with the single capping requirement, holes ranked by exploitability (CONFIRMED/PLAUSIBLE, each with repro or reason), and priority fixes in build order (§9 — enforcement holes and verifier/holdout before observability before governance polish). OVERWRITE `<path>/harness-review.md` with a one-line timestamp header. It is human-facing — commit it like `review.md`, never gitignore.
4. **Next step.** Point at the top fix. If the target has no loop, suggest `/loopy:loop-init`.

Writing one report is reversible/local (T0) — never merge, push, or publish from this skill, and change nothing under the target beyond `harness-review.md`. Safe to run anytime, including first thing in a fresh project.
