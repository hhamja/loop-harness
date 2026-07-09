# Changelog

## 0.3.0 — 2026-07-09

- Decision gates: classify every side-effecting action by reversibility × impact. Reversible/local work (edits, tests, local commits, work-branch push) runs autonomously — never re-confirmed; only irreversible or high-impact actions stop on a human gate. Doctrine in the loop-engineering skill + `references/decision-gates.md`.
- `decision_gate.sh` (new PreToolUse Bash hook) mechanically blocks the T2 class inside a loop project: package publish, release/submit (`gh release`, `eas submit`), `gh pr merge`, push to a protected branch, force-push, tag push, catastrophic `rm -rf`. Scoped to loop projects only (fail-open everywhere else).
- `loop.config.md` gains `protected_branches` (default `main master`), `gate_push` (default `false` — set `true` for direct-to-main repos), and `extra_gates` (optional project regex). Absent keys fall back to defaults, so existing loops need no change.
- One-shot approval marker `.claude/loop/.gate-approved` (action class + session + 15-min TTL, gitignored): the main agent writes it only after explicit human approval, retries the gated command, then removes it.
- `loop-audit` (new command) + `auditor` (new read-only subagent): audit the loop *process* — maker/checker separation, machine-verifiable stops, disk-memory discipline, and gate adherence (over-/under-confirmation) — and write a scored report to `audit.md`. Complements the product-grading verifier.
- `verifier_guard.sh` now also guards the `auditor` agent (both are read-only checkers).
- `loop-ci` (new command) + `gen_ci.sh`: scaffold a GitHub Actions CI workflow from the loop's detected test/lint/build (a pure, golden-tested generator; node stacks for now).
- CI/CD for this repo: `ci.yml` (shellcheck + `bash -n` + jq manifest validation + `tests/run.sh`) on push/PR; `release.yml` cuts a GitHub Release from the matching CHANGELOG section when a `v*` tag is pushed.
- `.gitignore` for OS/editor files and loop runtime artifacts (`.run-marker`, `.gate-approved`, codex logs, …).

## 0.2.0 — 2026-07-07

- Cross-model maker/checker: `loop-run` delegates the Implement step to OpenAI's Codex CLI (`codex exec --full-auto`) when `implementer: codex`; Claude stays the orchestrator and the verifier.
- `loop.config.md` gains `implementer: codex|claude` (auto-detected by `loop-init` via `codex --version`) and an optional `codex_args` passthrough (e.g. model, network access).
- Fresh `codex exec` per cycle; the prompt is rebuilt from disk state (goal, unresolved criteria, last failure reasons, distilled rules) with fixed guardrails (no `.claude/loop/` writes, no git commit/push).
- Context hygiene: codex stdout → `.claude/loop/.codex-log`; the main agent reads only `.codex-last` (`--output-last-message`); prompt in `.codex-prompt` — all covered by the existing `.claude/loop/.*` gitignore rule.
- Fallback: codex unavailable at run start → the run proceeds as claude (recorded in state.md/memory.md); a non-zero `codex exec` → one retry, then claude for that cycle.
- Docs: mission spec v3.4.4 → v3.5.0 (ko/en); README cross-model section (en/ko).

## 0.1.0 — 2026-07-06

- Initial release.
- Commands: `loop-init`, `loop-run` (`--once`, `--verify-only`), `loop-status`.
- Agents: `verifier` (read-only grader), `explorer` (haiku scout).
- Skill: `loop-engineering` + 3 references (memory-protocol, rubric-guide, worktree-guide).
- Hooks: Stop gate (`stop_gate.sh`), verifier write guard (`verifier_guard.sh`, PreToolUse Bash).
- `check_budget.sh` token-budget proof script.
