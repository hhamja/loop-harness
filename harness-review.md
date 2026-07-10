# Harness review — loopy (self-review)

> 2026-07-10 (comprehensive pass) · target: `.` (loopy grading its own harness) · reviewers: loop-architect + design-critic + auditor + 2 explorers (hooks/CI, gate scripts); 6 command-settleable holes reproduced by the orchestrator in a fresh `mktemp -d` against the real scripts. Threat model per commit `0faabb4`: the gate hooks are a **forgetfulness backstop, not a sandbox** — a determined-adversary bypass is out of scope *by design*; a bug an *honest but forgetful* agent trips is in scope. This pass adds two previously-undocumented honest-agent bugs (`rm -rf /*` under-match, clock fail-open) and questions one adversarial→honest classification (`HEAD:refs/heads/main`). Standing adversarial escalations and the L3 holdout cap are unchanged.

## ETCLOVG coverage

| | Responsibility | Verdict | Evidence |
|---|---|---|---|
| E | Execution | PARTIAL | maker runs fresh `codex exec --full-auto` isolated; only per-worker cap is a 10-min wall-clock, no token/tool-call cap (`skills/loop-run/references/codex-exec.md:6`) |
| T | Tooling | PASS | read-only checkers `disallowedTools: Write,Edit` (`agents/verifier.md:5`) + `verifier_guard.sh` PreToolUse deny; maker sandbox egress-off default. Thickest responsibility here. Leak: denylist-based (see H4). |
| C | Context | PASS | durable `.claude/loop/*.md`; state.md rewritten ≤100 lines; codex fresh each cycle, main reads `.codex-last` summary only; checkers return per-criterion reports not logs |
| L | Lifecycle | PASS | `max_iterations:10`, `replan_max:2`, 3-fail→replan→escalate, "no infinite repeat-until-pass" (`skills/loop-run/SKILL.md:35-36`); rubric.md as decomposition artifact |
| V | Verification | PARTIAL | maker≠checker with permission+incentive asymmetry; **no information asymmetry (holdout ✕)** — checker grades the same fully-visible rubric the maker authored (`skills/loop-run/SKILL.md:28`) |
| O | Observability | FAIL | only `.last-usage` (transcript-bytes/4, `stop_gate.sh:61-74`); no reject-rate / repeated-tool-call / visible-vs-holdout counters; caps enforced by prompt, not a process-external counter |
| G | Governance | PARTIAL | T2 class hard-blocked by `decision_gate.sh` (hook, not prompt); but side-effect logs overwrite-not-append (`.last-*`), kill-switch + policy (`loop.config.md`) live in agent-writable, gitignored scope |

**maturity: L3/5** — capped by the L4 requirement (**holdout suite outside the loop, returning only a pass/fail bit**). Independent reviewers (loop-architect, this pass) and the repo's own control-plane doc (`docs/loop-control-plane.md` §10, holdout ✕) converge on the same cap.

## Holes (ranked by exploitability, CONFIRMED = reproduced in temp dir)

### NEW this pass — honest-agent bugs in scope for the backstop

- **CONFIRMED · `rm -rf /*` slips the catastrophic-delete gate** (`decision_gate.sh:167`, top priority). `CATA_TGT` requires `/` followed by space/`/`/end, so `/` (root) denies but `/*` — the classic empty-variable expansion (`rm -rf "$DIR"/*` when `$DIR` is unset → `rm -rf /*`) — is **ALLOWED**. This is the exact honest-catastrophe §5 exists to stop, and the same category as the already-fixed `~/<subdir>` over-match, just the opposite direction. Repro (fresh temp dir): `rm -rf /*` → ALLOWED while `rm -rf /` → DENIED. **Not previously documented anywhere in this review.** Fix: extend `CATA_TGT` to treat `/` + glob/end as root (one alternation).
- **CONFIRMED · clock fail-open re-approves an expired marker** (`decision_gate.sh:99`). `[ "$now" -gt 0 ] || return 0` — if `date +%s` yields 0/empty, an expired (or ancient) `.gate-approved` marker is treated as fresh → **approved**. Repro: `date` shim returning 0 + marker `ts=1000000000` (year 2001) → `git push origin main` ALLOWED. Low-likelihood trigger (broken clock) but it fails *open* on the one axis (freshness) meant to bound the marker's blast radius. Fix: fail *closed* when the clock is unreadable (`return 1`), not open.

### RECLASSIFY — currently escalated as adversarial, but honest-plausible

- **CONFIRMED · `git push origin HEAD:refs/heads/main` reaches protected `main` ungated** (`decision_gate.sh:157`). The branch matcher anchors on `[[:space:]:](main|master)`, so the fully-qualified `refs/heads/main` (a `/` precedes `main`) is missed. Repro: `HEAD:refs/heads/main` → ALLOWED while `HEAD:main` → DENIED. The prior pass bucketed this with adversarial wrappers, but a fully-qualified refspec is a plain, non-evasive git idiom — the *same reasoning* that reclassified `+refspec` from adversarial→honest last pass applies here. Recommend treating as an honest-agent fix, not an accepted bypass: add `refs/heads/` before the branch token to the §4 protected-branch grep.

### Standing adversarial escalations — reproduced, accepted by design (`0faabb4`)

All reproduced this pass; all require a *determined* agent evading its own gate, which the forgetfulness-backstop model explicitly does not defend. Listed for governance awareness, unchanged:

- **CONFIRMED · forgeable `.gate-approved` marker** (`decision_gate.sh:85-102`): the marker is written via the **unhooked Write tool** (PreToolUse matcher is `Bash`-only, `hooks/hooks.json:5`), and `approved()` accepts `action=any` with the session check *skipped when the marker's `session_id` is empty* (`[ -n "$s" ]` false). Repro: write `action=any\nts=<now>` (no session_id) → every T2 (`git push origin main`, `gh pr merge`, `npm publish`) flips ALLOWED. Sharper than the doc's concession (`docs/loop-control-plane.md:273`): no session_id is needed at all.
- **CONFIRMED · command-form bypasses** (`decision_gate.sh:114,130,135`): `FOO=1 git push origin main` (env-prefix), `git -C /tmp push origin main` (`-C` breaks push-adjacency), `gh api -X PUT repos/o/r/pulls/N/merge` (no `gh pr merge` form) — all ALLOWED. Env-prefix and `gh api` are not in the conceded list; `git -C` is.
- **CONFIRMED · `verifier_guard.sh` is a denylist → interpreter escape** (`verifier_guard.sh:66-90`): a read-only checker (verifier/auditor/architect/critic) can still mutate via `python3 -c`, `node -e`, `perl -i`, `patch -p1`, `install`, `ex` — all ALLOWED (baseline `rm -rf x` correctly DENIED). `disallowedTools` blocks the *tools*, not Bash-invoked writers, so a verifier could rewrite source/tests then report PASS.
- PreToolUse matcher is `Bash`-only: Write/Edit and MCP T2-equivalents (external send, remote delete/merge) reach no gate at all.

### PLAUSIBLE — design-level, not command-settleable

- **maker≠checker tautology** (`skills/loop-run/SKILL.md:28`): the verifier grades a `rubric.md` whose criteria + `verify:` commands the maker authors, with no holdout. The incentive leg (falsification prompt) holds; the information leg is absent and the permission leg leaks (H4). Not a reproduced exploit — the skill wording *implies* the maker can author the exact check the verifier re-runs, but no run was observed doing so.
- **state-forgery**: `state.md` `human_gate`/`loop_active` are plain files the main agent writes and `drive_next.sh:26-31` trusts; a maker can self-assert `human_gate: ready_for_merge`. Bounded because the merge itself is separately (if leakily) gated.

### REFUTED (dropped)

- **local == CI**: `.github/workflows/ci.yml:21` runs exactly `bash scripts/ci_local.sh` — genuine single source, no drift.
- **loop_lock ownership gate**: auto_commit/push/pr Stop hooks stand down for a foreign session / when another fresh session holds the lock (`loop_lock.sh cmd_gate`, asserted by `tests/run.sh:796-845`). Concurrency backstop, holds for its stated purpose.

## Process notes (auditor + explorers)

- **This repo is a plugin-source workspace, not a compliant loop** (its own now-deleted `loop.config.md:2` said so). No `rubric.md` / `state.md` / `memory.md`, so process criteria A1–A3/A6 are N/A-by-intent, not failures. The human merge gate itself held: PRs #7/#8/#9 all `mergedBy: hhamja`, no tags pushed past `v0.5.0`, the one destructive `rm` had recorded explicit approval (`review.md:9`).
- **Concurrent-session deletion of `loop.config.md`** (observed mid-audit ~15:26): the file that *disables* the auto-commit/push/pr hooks is itself agent-deletable in a shared tree — deleting it silently re-enables auto behavior via fail-open defaults. Governance-relevant instance of the "policy lives in agent-writable scope" hole above.
- **`check_memory.sh` is wired to the Stop hook only, not `ci_local.sh`** (`hooks/hooks.json:27` vs `ci_local.sh:32-36`): memory-hygiene violations surface at turn-end re-prompt, never in pre-push CI.

## Next step

Review-only pass (no `--fix`). Build order:

1. **`rm -rf /*` under-match** (`decision_gate.sh:167`) — top honest-agent fix, one-line regex + regression test (whole-root-glob deny), mirrors the existing §5 test shape.
2. **`HEAD:refs/heads/main` protected-push** (`decision_gate.sh:157`) — reclassify honest, add `refs/heads/` to the branch grep + regression test.
3. **clock fail-open** (`decision_gate.sh:99`) — fail closed on unreadable clock.
4. **holdout suite** (V, the L3→L4 cap) — the only structural item; everything above is a localized gate bug, everything below (O counters, append-only ledger, external kill-switch) is documented roadmap.

Items 1–3 are machine-checkable honest-agent bugs suitable for `/loopy:loop-review --fix`. The adversarial escalations remain accepted-by-design under `0faabb4`.
