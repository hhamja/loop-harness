# loop-harness

**English** | [한국어](README.ko.md)

[![License: MIT](https://img.shields.io/github/license/hhamja/loop-harness)](LICENSE)
[![Release](https://img.shields.io/github/v/release/hhamja/loop-harness)](https://github.com/hhamja/loop-harness/releases)

**Your agent says "done." This plugin makes it prove it.**

loop-harness is a Claude Code plugin for loop engineering: it runs implement→verify cycles and refuses to accept "done" until a machine-verifiable rubric passes — graded by an independent read-only verifier, with disk-based state that survives session death.

Design invariant: **the plugin is immutable logic** (install once per machine); **all mutable state lives in `.claude/loop/`** (created once per project by `loop-init`).

## Install

**Path 1 — marketplace:**

```
/plugin marketplace add <this-repo-URL-or-local-path>
/plugin install loop-harness@loop-harness-marketplace
```

This repo ships `.claude-plugin/marketplace.json`, so the repo itself can be added as a marketplace directly — no separate marketplace repo needed.

**Path 2 — local development:**

```
claude --plugin-dir /absolute/path/to/loop-harness
```

(Absolute path recommended.)

## Quickstart (3 minutes)

1. `cd` into your project and start Claude Code.
2. Run `/loop-harness:loop-init` — scaffolds `.claude/loop/` (goal, rubric, state, memory, review, config) and auto-detects your test/lint/build commands.
3. Edit `.claude/loop/goal.md` and `rubric.md` — every criterion needs a verification command (see the loop-engineering skill's rubric guide).
4. Run `/loop-harness:loop-run` — cycles implement → verify until the rubric passes or a safety rail triggers.
5. Run `/loop-harness:loop-status` any time to see progress; it is always read-only.

## Progressive adoption

You don't have to run the full loop on day one:

1. `/loop-harness:loop-run --verify-only` — grade existing code against a rubric; prints a report and writes nothing (read-only guarantee holds for a fresh session; see known limitations).
2. `/loop-harness:loop-run --once` — exactly one implement+verify cycle, then stop.
3. `/loop-harness:loop-run` — the full loop, with safety rails: `max_iterations` cap (default 10) and escalation after 3 consecutive failures of the same criterion.

## Token cost

Loops, verifiers and subagents consume tokens — always weigh cost against the task:

- The verifier runs once per cycle (phase gate), never per file edit.
- The `explorer` scout runs on haiku (cheap); use it instead of broad reading.
- Each run's token figure is estimated by the stop gate into `.claude/loop/.last-usage` (transcript-size heuristic — an estimate, never billing data) and surfaced in `state.md` / `loop-status`.
- Start with `--verify-only` or `--once` when unsure a full loop is worth it.

## Boundary principles

1. **"Done" is a claim, not a proof** — the final verification belongs to a human.
2. **Comprehension debt is real** — every cycle overwrites `.claude/loop/review.md` with a human-readable summary (files changed, key changes, risks). Read it.
3. **Loops, verifiers and subagents burn tokens** — always a cost/benefit call, never a default.

## `.claude/loop/` commit policy

Commit everything except hidden temp files. `loop-init` adds `.claude/loop/.*` to your `.gitignore` (covers `.run-marker`, `.last-usage`, `.hook-debug.log`); the visible files — goal, rubric, state, memory, review, config — are meant to be committed for team sharing and session recovery.

## Known limitations

- Claude Code versions that ship no dedicated Grep/Glob tools (observed in v2.1.201): the verifier and explorer fall back to read-only Bash equivalents (`grep`/`find`). The verifier remains hook-guarded against writes; the explorer's read-only property is prompt-enforced only.
- In `claude --resume` sessions the session id changes, so the Stop gate can be inactive for that session (fails open — it never blocks by mistake in this case).
- If a loop-run dies before updating `state.md`, the next turn-end in that same session is blocked once; appending the single line the gate asks for resolves it permanently. If that turn happens to be `--verify-only`, this one line is the only exception to its read-only guarantee (the guarantee covers persistent, committable files; the hidden temp `.last-usage` is out of scope and updates whenever a same-session marker exists).
