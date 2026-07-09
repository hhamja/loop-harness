# Changelog

## 0.8.0 — 2026-07-10

- `auto_commit.sh` (new Stop hook): the mechanical complement of `auto_push.sh` for the other half of the T0 rule "local commits → act autonomously, never re-ask". `auto_push` pushes an existing commit; if the agent left verified work uncommitted, there was nothing to push and a human still got asked "shall I commit?" — a doctrine violation. The new hook runs first in the Stop chain and, on a work tree with changes, commits them (`git add -A`) with a generic backstop message, then `auto_push` pushes. The agent committing inline with a written message stays the primary path; the hook only fires when it didn't. Unlike push, it is NOT gated on `protected_branches`/`gate_push` — a local commit is unconditionally T0 (undo with `git reset`), which is exactly the direct-to-main workflow "commit locally, human gates the push". Opt out with `auto_commit: false` in `loop.config.md`; commit failure logs to `.claude/loop/.last-commit` and never blocks the turn. Covered by new `tests/run.sh` cases (guards + a real-commit assertion); documented in `decision-gates.md` and the loop-init config template.

## 0.7.0 — 2026-07-10

- `loop-diagnose` renamed to `loop-review` and upgraded from a single-agent diagnosis into an orchestrated review: the main agent fans out read-only reviewers — `loop-architect` (ETCLOVG coverage + L0–L5 maturity) and the new `design-critic` (adversarial red-team) — then independently reproduces the critic's exploitable findings before synthesizing one report. Invocation is now `/loopy:loop-review [path]` (was `/loopy:loop-diagnose`); the report file is `harness-review.md` (was `harness-diagnosis.md`).
- `loop-review --fix`: after the review, autonomously remediate the high-severity, machine-checkable findings on a fresh `review/…` branch and stop at a draft PR (the merge stays the human gate). It does not fix or grade itself — each finding becomes a rubric criterion whose `verify:` command is the finding's own reproduction (the exploit must now be blocked), and the existing `loop-run` maker/checker/verify/green-gate loop closes them; design-level findings (no holdout, forgeable-marker redesign, …) are escalated into the PR, never auto-built. Reuses `loop-run`/`auto_push`/`decision_gate` — no new enforcement code. Procedure in `skills/loop-review/references/fix-mode.md`.
- New `design-critic` read-only subagent (`agents/design-critic.md`): framed to REFUTE compliance claims — gate bypasses, forgeable approvals, rubber-stamps, script bugs — reporting CONFIRMED/PLAUSIBLE/REFUTED holes. This supplies the doctrine's §3.3 incentive asymmetry (adversarial framing) that a single rubric-grader lacks.
- `verifier_guard.sh` now also guards any `*critic*` agent — the read-only checkers are verifier, auditor, architect, critic, all blocked from write-capable Bash; covered by a new `tests/run.sh` case.

## 0.6.1 — 2026-07-09

- Command→skill migration completed: `loop-init`, `loop-run`, `loop-status`, `loop-audit`, `loop-ci` moved from `commands/*.md` to `skills/<name>/SKILL.md`. They already resolved as `/loopy:<name>`, so invocation is unchanged; this aligns the repo with the project convention that `commands/` is legacy and every feature is a Skill.
- Each migrated skill gains a `name:` field. The four side-effecting ones (`loop-init`, `loop-run`, `loop-audit`, `loop-ci`) get `disable-model-invocation: true`; the read-only `loop-status` stays model-invocable.
- `loop-init` and `loop-run` bodies exceeded the ≤500-word SKILL.md limit, so their bulk moved into per-skill `references/` (uncounted, per the existing pattern): loop-init's state-file templates → `references/templates.md`; loop-run's codex procedure, preflight, report-application, and green-gate detail → `references/{codex-exec,preflight,apply-report,green-gate}.md`. Behavior unchanged — only prose location.
- Docs pruned: removed unreferenced/stale files — `docs/loop-engineering-playbook.md` (a lower-resolution restatement of `docs/loop-control-plane.md`, linked by nothing), the `docs/mission-v3.5.0*.md` build-spec snapshots (KO/EN; described the pre-migration `commands/` structure at v0.2.0), and the `elite-loop-engineering.md` loop-engineering reference (its operating content already lives in the SKILL body + control-plane). The skill route to elite was removed. `loop-control-plane.md` stays — it's a `${CLAUDE_PLUGIN_ROOT}` runtime dependency of `loop-diagnose`/`loop-architect`.

## 0.6.0 — 2026-07-09

- Harness diagnosis: `loop-diagnose` (new skill) + `loop-architect` (new read-only subagent) diagnose *any* project's agent/loop harness against the control plane (`docs/loop-control-plane.md`) — no `.claude/loop/` required. The architect scores the seven ETCLOVG responsibilities (Execution, Tooling, Context, Lifecycle, Observability, Verification, Governance) with cited evidence and a maturity level (L0–L5), and returns build-order-ranked priority fixes; the main agent writes the report to `harness-diagnosis.md`. Complements `loop-audit`, which grades an *initialized* loop's process rather than whether the architecture exists at all.
- Packaged as a Skill (per current Claude Code guidance that custom commands are skills) with `disable-model-invocation: true` so this side-effecting workflow only runs when the user invokes `/loopy:loop-diagnose [path]`; the target path arrives via `$ARGUMENTS`.
- `verifier_guard.sh` now also guards the `loop-architect` agent (all three read-only checkers — verifier, auditor, architect — are blocked from write-capable Bash).
- `check_budget.sh` now enforces the ≤500-word body limit on every `skills/*/SKILL.md`, not just the loop-engineering skill.

## 0.5.0 — 2026-07-09

- Auto-push (new Stop hook `auto_push.sh`): realizes the decision doctrine's T0 rule "pushing a work branch is reversible → act autonomously, never re-ask". At turn end inside a loop project the current work branch is pushed automatically — plain `git push` when it is ahead of its upstream, or `git push -u origin <branch>` on the first push. It is the active complement to `decision_gate.sh`, which *blocks* pushing a protected branch.
- Safe by construction: never pushes a `protected_branches` branch (a human gate stays a human gate), stands down when `gate_push: true` (direct-to-main repos where every push is already T2), never force-pushes or pushes tags, and a push failure is logged to `.claude/loop/.last-push` without ever blocking the turn.
- `loop.config.md` gains `auto_push` (default `true`); set `auto_push: false` to opt out. Absent key falls back to the default, so existing loops need no change.

## 0.4.0 — 2026-07-09

- Autonomous replan: a criterion failing 3 consecutive cycles no longer escalates straight to a human. `loop-run` first tries up to `replan_max` genuinely different strategies — change approach, decompose the work, or spike the root cause — and escalates only when they are exhausted. Doctrine in `references/replan.md`.
- Criterion-weakening is forbidden as an autonomous move: replan may change the *approach*, never relax, loosen, or delete a rubric `verify:` command (that stays a human-only escalation option). New auditor check **A7** grades this against `rubric.md`'s git history.
- `loop.config.md` gains `replan_max` (default `2`); absent key falls back to the default, so existing loops need no change.
- Green gate before "done": on a full run reaching all-green, `loop-run` now runs the `auditor` (process) and the `/code-review` skill (correctness) once before declaring done. A rubric that is green but fails audit or review reopens as new/unresolved criteria instead of stopping — 'green' is no longer trusted blind.
- `state.md` gains a deterministic `human_gate` marker (`none` | `ready_for_merge` | `pending_t2` | `stalled`) that a driver or notifier can read to decide whether to advance, wait, or surface to the human.

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
