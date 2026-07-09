# loopy

**English** | [한국어](README.ko.md)

[![License: MIT](https://img.shields.io/github/license/hhamja/loopy)](LICENSE)
[![Release](https://img.shields.io/github/v/release/hhamja/loopy)](https://github.com/hhamja/loopy/releases)

**Your agent says "done." This plugin makes it prove it.**

loopy is a Claude Code plugin for loop engineering: it runs maker/checker cycles and refuses to accept "done" until a machine-verifiable rubric passes. Implementation is delegated to OpenAI's Codex CLI when available; grading is done by an independent read-only Claude verifier — a cross-model split where the model that writes the code never grades it — with disk-based state that survives session death.

Design invariant: **the plugin is immutable logic** (install once per machine); **all mutable state lives in `.claude/loop/`** (created once per project by `loop-init`).

## Install

**Path 1 — marketplace:**

```
/plugin marketplace add <this-repo-URL-or-local-path>
/plugin install loopy@loopy-marketplace
```

This repo ships `.claude-plugin/marketplace.json`, so the repo itself can be added as a marketplace directly — no separate marketplace repo needed.

**Path 2 — local development:**

```
claude --plugin-dir /absolute/path/to/loopy
```

(Absolute path recommended.)

## Quickstart (3 minutes)

1. `cd` into your project and start Claude Code.
2. Run `/loopy:loop-init` — scaffolds `.claude/loop/` (goal, rubric, state, memory, review, config), auto-detects your test/lint/build commands, and detects whether the Codex CLI is available (sets `implementer:` accordingly).
3. Edit `.claude/loop/goal.md` and `rubric.md` — every criterion needs a verification command (see the loop-engineering skill's rubric guide).
4. Run `/loopy:loop-run` — cycles implement (Codex or Claude) → verify until the rubric passes or a safety rail triggers.
5. Run `/loopy:loop-status` any time to see progress; it is always read-only.

## Progressive adoption

You don't have to run the full loop on day one:

1. `/loopy:loop-run --verify-only` — grade existing code against a rubric; prints a report and writes nothing (read-only guarantee holds for a fresh session; see known limitations).
2. `/loopy:loop-run --once` — exactly one implement+verify cycle, then stop.
3. `/loopy:loop-run` — the full loop, with safety rails: `max_iterations` cap (default 10) and escalation after 3 consecutive failures of the same criterion.

## Review an existing harness

`/loopy:loop-review [path]` reviews any project's agent/loop harness against the control plane (`docs/loop-control-plane.md`) — no `.claude/loop/` required. As orchestrator, the main agent fans out read-only reviewers — a `loop-architect` that scores the seven ETCLOVG responsibilities (Execution, Tooling, Context, Lifecycle, Observability, Verification, Governance) with cited evidence and a maturity level (L0–L5), and a `design-critic` that adversarially red-teams the harness (gate bypasses, forgeable approvals, rubber-stamps) — then independently reproduces the critic's exploitable findings before writing `harness-review.md` with build-order-ranked priority fixes. Unlike `loop-audit` (which grades an initialized loop's *process*), this reviews whether the harness *architecture* exists and whether its gates actually hold.

## Cross-model maker/checker (Codex)

The implement step can be delegated to OpenAI's Codex CLI, so the model that writes the code is never the model that grades it.

- **Prerequisite:** the `codex` CLI installed and authenticated (`codex login`). `loop-init` runs `codex --version` and sets `implementer: codex` when it succeeds, else `implementer: claude`.
- **How it works:** each cycle, the main agent rebuilds a prompt from `.claude/loop/` disk state (goal, unresolved criteria with their verification commands, the last verifier failure reasons, distilled rules) and runs one fresh `codex exec --full-auto` — never a resumed session. Codex's full stdout goes to `.claude/loop/.codex-log`; the main agent reads back only `.codex-last` (`--output-last-message`), so Codex output never floods Claude's context. The prompt forbids Codex from touching `.claude/loop/` or running git commit/push.
- **Config:** `implementer: codex | claude` and an optional `codex_args:` passthrough in `loop.config.md` (e.g. `-m <model>`, or `-c sandbox_workspace_write.network_access=true` to allow network — the workspace-write sandbox disables it by default).
- **Fallback:** if `codex --version` fails at run start, the whole run proceeds as Claude with a note in `state.md`/`memory.md`. If a `codex exec` call exits non-zero, it retries once, then falls back to Claude for that cycle. Set `implementer: claude` for the pre-0.2.0 behavior — no Codex dependency at all.

## Token cost

Loops, verifiers and subagents consume tokens — always weigh cost against the task:

- The verifier runs once per cycle (phase gate), never per file edit.
- The `explorer` scout runs on haiku (cheap); use it instead of broad reading.
- Each run's token figure is estimated by the stop gate into `.claude/loop/.last-usage` (transcript-size heuristic — an estimate, never billing data) and surfaced in `state.md` / `loop-status`.
- With `implementer: codex`, Codex output is kept out of Claude's context, and Codex-side usage is billed by OpenAI — it is **not** included in the `.last-usage` estimate.
- Start with `--verify-only` or `--once` when unsure a full loop is worth it.

## Boundary principles

1. **"Done" is a claim, not a proof** — the final verification belongs to a human.
2. **Comprehension debt is real** — every cycle overwrites `.claude/loop/review.md` with a human-readable summary (files changed, key changes, risks). Read it.
3. **Loops, verifiers and subagents burn tokens** — always a cost/benefit call, never a default.

## `.claude/loop/` commit policy

Commit everything except hidden temp files. `loop-init` adds `.claude/loop/.*` to your `.gitignore` (covers `.run-marker`, `.last-usage`, `.last-push`, `.hook-debug.log`, and the Codex I/O files `.codex-prompt`, `.codex-last`, `.codex-log`); the visible files — goal, rubric, state, memory, review, config — are meant to be committed for team sharing and session recovery.

## Known limitations

- Claude Code versions that ship no dedicated Grep/Glob tools (observed in v2.1.201): the verifier and explorer fall back to read-only Bash equivalents (`grep`/`find`). The verifier remains hook-guarded against writes; the explorer's read-only property is prompt-enforced only.
- In `claude --resume` sessions the session id changes, so the Stop gate can be inactive for that session (fails open — it never blocks by mistake in this case).
- If a loop-run dies before updating `state.md`, the next turn-end in that same session is blocked once; appending the single line the gate asks for resolves it permanently. If that turn happens to be `--verify-only`, this one line is the only exception to its read-only guarantee (the guarantee covers persistent, committable files; the hidden temp `.last-usage` is out of scope and updates whenever a same-session marker exists).
- With `implementer: codex`, Codex runs in a workspace-write sandbox with network **disabled** by default; goals that need to install dependencies fail unless you allow network via `codex_args` (`-c sandbox_workspace_write.network_access=true`).
- In an interactive session, the first `codex exec` Bash call triggers a normal permission prompt; headless runs need a permission mode that allows it (an installed-but-unauthenticated Codex passes the version check but fails at `codex exec`, which then falls back to Claude).
