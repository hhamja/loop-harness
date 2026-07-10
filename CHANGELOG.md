# Changelog

## 0.12.0 — 2026-07-10

- **Working-tree isolation: one tree = one writing loop, parallelism = worktrees.** Root fix for the concurrent-session entanglement where two sessions sharing one checkout got their unrelated changes bundled into one auto-commit (`git add -A` grabs everything; hooks fire on every Stop). Two complementary halves:
  - **`scripts/loop_lock.sh`** — per-worktree session lock. `gate`: the `auto_commit`/`auto_push`/`auto_pr` Stop hooks now act only for the session that actually ran a loop in this tree (same-session `.run-marker`) and stand down while a different fresh session holds the lock. `acquire` (loop-run preflight): a second `loop-run` in an already-held tree is refused and pointed to a separate git worktree; `release` at loop end, TTL 3600s crash backstop, `LOOP_LOCK_DISABLE=1` escape hatch. A shared tree now *serializes* instead of entangling.
  - **`/loopy:loop-worktree`** — the deliberate-parallelism primitive that makes `worktree-guide.md` executable (was reference-only). Spawn: one file-disjoint rubric subset = one worktree = one `<type>/<task>` branch, worker config gets `worker: <task>` + `auto_push`/`auto_pr` off. Worker contract, enforced by `auto_commit`'s new worker mode: commit sources plus `.claude/loop/results/<task>.md` ONLY — nothing else under `.claude/loop/` (local state/rubric/goal/config stay uncommitted, so integrating a task branch can never conflict with or overwrite the orchestrator's loop files). Integrate: local `git merge` per task branch (T0 — the human merge gate stays at the PR), fold `results/<task>.md` into the main `state.md`, remove worktrees; a source conflict means the split was wrong — redo it, never resolve blind. Orchestration beyond isolation (auto rubric split, parallel dispatch) is deliberately NOT shipped — fan-out last (control-plane §12).
  - Covered by 6 worker-mode tests (incl. a real-run commit-content assertion) + the lock suite; two-worker E2E merged conflict-free. 152 tests pass, `ci_local.sh` ALL GREEN, budget OK.

## 0.11.1 — 2026-07-10

- **`fleet.sh --swiftbar`: the fleet as a macOS menubar dashboard.** Same data pipeline (collect() extracted so the table and SwiftBar renderers share one source), emitted in SwiftBar/xbar plugin format: menubar title `⏳W ▶B` (waiting count always visible without opening anything), dropdown listing every live session with name · project · branch · idle, color-coded (waiting=orange, busy=green, idle=gray), stale count in the footer. A 3-line shim in the SwiftBar plugin folder (`~/.swiftbar/fleet.5s.sh`) execs the repo script, so logic stays versioned here. Covered by swiftbar-mode assertions in the existing `test_fleet` fixture.

## 0.11.0 — 2026-07-10

- **`scripts/fleet.sh`: an at-a-glance view of every live Claude Code session on the machine.** Running many parallel sessions across projects, you lose track of which are working, which are done, and — the one that actually costs you — which are *silently waiting for input*. fleet reads `~/.claude/sessions/<PID>.json` (Claude Code already writes each session's `name`/`status`/`cwd`/`updatedAt` there live and rewrites it on every transition), reconciles against `kill -0` to drop dead PIDs, and prints a table sorted **waiting → busy → idle** with whole-row color emphasis on waiting. No hooks, no transcript parsing, no new dependency (just `jq`); read-only and independent of `.claude/loop/`. `--watch [secs]` auto-refreshes in a spare terminal.
  - Deliberately **not** a loopy skill: it is a machine-wide, cross-project tool, orthogonal to a single project's maker/checker loop, and a folder-scoped slash command would both miss the "see everything" goal and spend the description-word budget. Symlink `scripts/fleet.sh` onto PATH for a one-word `fleet`.
  - Covered by a new `tests/run.sh` case that injects a fixture sessions dir via `FLEET_SESSIONS_DIR` (live PID = `$$`/`$PPID`, dead PID = 999999) and locks the empty-`status` regression: a session field left blank must not collapse and shift the columns (the reason the first draft crashed on a real VS Code bridge session). 121 tests pass, `ci_local.sh` green.

## 0.10.0 — 2026-07-10

- **Autonomous CI remediation: the loop keeps its own PR green; only the merge is human.** By the reversibility×impact doctrine, fixing a red CI on a work branch is T0/T1 (reversible, local) — so leaving a red PR for the human, or asking whether to fix it, is over-confirmation. The gap: the Stop hooks (commit→push→PR) open a PR but nothing then drives a red run back to green, so a remote-only failure could sit red.
  - New `scripts/ci_watch.sh`: blocks until **this commit's** CI run concludes (matches the run by HEAD sha; deadline-bounded so it can never hang), exit 0 = green / nothing to watch, exit 1 = red with the failing job log tail. It is a **tool the drive loop runs, deliberately NOT a hook** — CI is async and a Stop hook must never block; watching + fixing is multi-step loop work.
  - Wired into `loop-run`: the **green gate** now watches remote CI to green before declaring done (red → reopen the failing check as a rubric criterion → fix → re-push → re-watch, bounded by `max_iterations`; *stuck past the cap* is the only thing that escalates to the human). **Preflight reconcile**: on entry, a branch with a red open PR — or commits ahead of base with no open PR (a prior PR merged, then new commits landed) — is resolved before new work. Disabling/skipping a check to force green is called out as T2-class test/CI tampering.
  - Resolution timing is explicit: local-reproducible red is caught *pre-push* (`ci_local.sh` gate); remote-only red is fixed *in the active drive session* right after `gh` reports; a walked-away session's red is picked up at the *next drive turn* (reconcile). There is no daemon — loopy is not a long-lived process. Documented in `decision-gates.md`, `green-gate.md`, `preflight.md`; covered by new `tests/run.sh` cases (98 pass).

## 0.9.3 — 2026-07-10

- Follow-up self-review (`loop-architect` + `design-critic` re-run, holes reproduced by the orchestrator). Both converge with the standing `harness-review.md`: **L3/5**, capped by the documented holdout gap; the adversarial bypasses (marker/config forgery, `git -C`/`eval`/`sh -c` wrappers, `gh api …/merge`, interpreter writes past `verifier_guard`, unhooked Write/MCP) remain out of scope by the stated threat model (gates are a **forgetfulness backstop, not a sandbox**) and stay escalated, not auto-fixed. Two honest-agent findings were fixed:
  - **`+refspec` force-push slipped `decision_gate.sh`.** The force-push sub-gate matched `--force`/`-f`/`--force-with-lease` but not the `+`-prefixed refspec form, so `git push origin +main` (force-push a protected branch) and `git push origin +feature` passed. **Reclassified adversarial→honest:** the 0.9.1 note bucketed `+main` with evasion wrappers, but `+refspec` is a plain force-push *spelling* an honest agent uses — the same category as the `-f` fix that 0.9.1 *did* apply, not a wrapper like `git -C`. Gated a `+`-prefixed refspec token as a force-push for any branch (one grep line); regression tests added (`+main` deny, `+feature` deny, consistent with `--force <work-branch>` already denying). Wrapped forms (`git -C … +main`) still evade by design.
  - **False ✅ in the doctrine map.** `docs/loop-control-plane.md` §10 claimed `decision_gate.sh` hard-blocks "테스트/CI 변조" (§7's test/CI-tamper policy gate). It does not — no diff-path check exists and the PreToolUse matcher is `Bash`-only, so test/CI edits via Edit/Write are ungated. Split the row into an honest ✅ (T2 *command* block, Bash-only backstop) plus a new ✕ (test/CI-tamper block: unimplemented) and added it to the L4/L5 maturity-cap list, so the doc no longer asserts a guarantee the harness never provides. `harness-review.md` updated. 95 tests pass, `ci_local.sh` green.

## 0.9.2 — 2026-07-10

- **Root-cause fix for red PRs: local verification now equals CI, by construction.** PR #6 went red on a `shellcheck` SC2016 finding (`tests/run.sh` awk `$1`, a false positive — intentional literal) that the local loop never ran: `ci.yml` checked shellcheck + `bash -n` + manifest JSON + tests, but the loop only ran `tests/run.sh`, so a lint error sailed through auto_push into a red required check. Also `ci.yml` never ran `check_budget.sh` despite CLAUDE.md calling budget "CI-enforced" — a second local↔CI drift.
  - New `scripts/ci_local.sh` is the **single source** of every CI check (shellcheck, syntax, manifest, budget, tests); `ci.yml` now just calls it, so local and CI cannot drift. Run `bash scripts/ci_local.sh` before pushing and green here == green there.
  - `auto_push.sh` gained a **pre-push CI gate**: when `scripts/ci_local.sh` is present it runs it and stands down on red, so a red commit never reaches origin (the commit still lands locally — T0). Belt to CI's suspenders (the required check still blocks merge).
  - SC2016 silenced on the one intentional-literal line; branch merged up to date with `main`. `green-gate.md` now states the "local verify must equal CI" rule. 93 tests pass, `ci_local.sh` green.

## 0.9.1 — 2026-07-10

- Self-review (`loop-review` on loopy itself: loop-architect + design-critic + auditor, holes reproduced by the orchestrator) fixed two `decision_gate.sh` regex bugs that an honest-but-forgetful agent trips — the exact class the backstop exists to catch. (1) **Catastrophic-delete over-match:** `rm -rf ~/<subdir>` and `$HOME/<subdir>` were gated as catastrophic though they are reversible T1 — the false positive that already bit a user (`.claude/loop/review.md` 2026-07-09, "Follow-up (not done)"). The new `CATA_TGT` gates only the *whole* root/home (`rm -rf /`, `//`, `~`, `~/`, `$HOME`, `${HOME}`), letting home subdirs pass. (2) **`-f` short-form force-push slipped:** `git push --force …` denied but `git push -f origin <branch>` passed, because `git[[:space:]]+push[[:space:]]` consumed the only space so the leading-`[[:space:]]-f` alternative never matched; `-f`/`--force` are now matched as a whole arg token in any position. Both closed with new `tests/run.sh` regression cases (91 pass). The adversarial bypasses the red-team also found (marker/config forgery, `git -C`/`eval` wrappers, `+main` refspec, `gh api …/merge`, interpreter writes past `verifier_guard`, unhooked Write/MCP) are out of scope by the stated threat model (gates are a forgetfulness backstop, not a sandbox — `0faabb4`) and are escalated in `harness-review.md`, not auto-fixed. New `harness-review.md` records the full ETCLOVG/maturity read (L3/5, capped by the documented holdout gap).

## 0.9.0 — 2026-07-10

- `auto_pr.sh` (new Stop hook): the third active complement to the T0 doctrine — "opening a PR" is reversible/low-impact (the *merge* is the T2 gate), so it is automated too. The Stop chain now runs commit → push → **PR**: after the branch is pushed, this hook opens a pull request (`gh pr create --fill`, base = the repo's default branch) so a human returns to a reviewable PR instead of a bare branch, and their only remaining action is the merge. Guards: loop project, on a non-protected branch with an upstream, an authenticated `gh`, and — since a branch can carry a merged/closed PR plus new commits — no *open* PR already for the branch. `pr_draft: true` opens a draft; opt out with `auto_pr: false`. Failure logs to `.claude/loop/.last-pr` and never blocks the turn. Covered by new `tests/run.sh` cases (guards + dryrun create/draft); documented in `decision-gates.md` and the loop-init config template.

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
