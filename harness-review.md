# Harness review — loopy (self-review)

> 2026-07-10 (follow-up pass) · target: `.` (loopy grading its own harness) · reviewers: loop-architect + design-critic, holes reproduced by the orchestrator in a scratch dir. Threat model per commit `0faabb4`: the gate hooks are a **forgetfulness backstop, not a sandbox** — a determined-adversary bypass is out of scope by design; a bug an *honest but forgetful* agent trips is in scope. This pass closed the `+refspec` force-push spelling gap and corrected a false ✅ in the control-plane doc; the standing escalations below are unchanged from the prior pass.

## ETCLOVG coverage

| | Responsibility | Verdict | Evidence |
|---|---|---|---|
| E | Execution | PARTIAL | maker runs fresh `codex exec --full-auto` isolated; only per-worker cap is a 10-min wall-clock, no token/tool-call cap (`skills/loop-run/references/codex-exec.md`) |
| T | Tooling | PASS | read-only checkers `disallowedTools: Write,Edit` + `verifier_guard.sh` PreToolUse deny; maker sandbox egress-off default. Thickest responsibility here. |
| C | Context | PASS | durable `.claude/loop/*.md`; state.md rewritten ≤100 lines; checkers return per-criterion reports, not logs |
| L | Lifecycle | PASS | `max_iterations:10`, `replan_max:2`, 3-fail escalation, rubric.md as decomposition artifact |
| V | Verification | PARTIAL | maker≠checker with permission+incentive asymmetry; **no information asymmetry (holdout ✕)** — checker grades the same fully-visible rubric the maker saw |
| O | Observability | FAIL | only `.last-usage` (transcript-bytes/4); no reject-rate / repeated-tool-call / visible-vs-holdout counters |
| G | Governance | PARTIAL | T2 class hard-blocked by `decision_gate.sh` (hook, not prompt); but side-effect logs are overwrite-not-append (no ledger) and the kill-switch lives in the agent-writable repo |

**maturity: L3/5** — capped by the L4 requirement (holdout suite outside the loop). Already self-documented as future work in `docs/loop-control-plane.md` §10 (holdout ✕, observability ⚠).

## Holes (ranked by exploitability under the stated threat model)

### Fixed this pass (honest-agent bugs that defeated the backstop's own purpose)
- **CONFIRMED · FIXED — catastrophic-delete over-match** (`decision_gate.sh` §5): `rm -rf ~/<subdir>` / `$HOME/<subdir>` were gated as catastrophic though they are reversible T1. This *already bit a user* (`.claude/loop/review.md` 2026-07-09). Fix: `CATA_TGT` gates only the whole root/home; a home subdir passes. Repro closed; regression tests added (`tests/run.sh`: home-subdir allow, whole-home/root deny).
- **CONFIRMED · FIXED — `-f` short-form force-push slipped** (`decision_gate.sh` §4): `git push --force …` denied (asserted by the suite) but `git push -f origin <branch>` slipped — the mandatory `push[[:space:]]` consumed the only space, so the leading-`[[:space:]]-f` alternative never matched. Force-push is a routine honest operation the gate is meant to catch. Fix: match `-f`/`--force` as a whole arg token in any position. Repro closed; regression test added.
- **CONFIRMED · FIXED (this pass) — `+refspec` force-push slipped** (`decision_gate.sh` §4): the force-push sub-gate matched `--force`/`-f`/`--force-with-lease` but not the `+`-prefixed refspec form, so `git push origin +main` (force-push a protected branch) and `git push origin +feature` both passed. **Reclassified from adversarial→honest:** the prior pass bucketed `+main` with evasion wrappers, but `+refspec` is a plain force-push *spelling* an honest agent uses — the exact category as the `-f` fix above, not a wrapper like `git -C`/`eval`. Fix: gate a `+`-prefixed refspec token as a force-push for any branch (one grep line). Repro closed; regression tests added (`+main` deny, `+feature` deny — consistent with `--force <work-branch>` already denying).
- **CONFIRMED · FIXED (this pass) — false ✅ in the doctrine map** (`docs/loop-control-plane.md` §10): the mapping claimed `decision_gate.sh` hard-blocks "테스트/CI 변조" (§7's test/CI-tamper policy gate). It does not — the script has no diff-path check and the PreToolUse matcher is `Bash`-only, so test/CI edits via Edit/Write are ungated. A governance doc asserting a guarantee the harness never provides misleads the very `loop-architect`/`design-critic` reviewers it feeds. Fix: split the row into an honest ✅ (T2 *command* block, Bash-only, a forgetfulness backstop not a sandbox) + a new ✕ (test/CI-tamper block: unimplemented); added to the L4/L5 maturity-cap list.

### Escalated — out of scope for auto-fix (adversarial bypasses; de-scoped by the backstop threat model)
These require a *determined* agent deliberately evading its own gate — `0faabb4` explicitly does not defend this. Listed for governance awareness, not fixed:
- Forgeable/self-issued `.gate-approved` marker and agent-editable `loop.config.md` policy (gate reads policy from an agent-writable, gitignored file).
- Push/publish/merge evasion via `git -C … push`, env-prefix (`A=1 git push`), `eval`/`sh -c`, `HEAD:refs/heads/main` fully-qualified refspec, `gh api …/merge`, `yarn npm publish`, bare tag-name push. (The plain `+main` force-refspec is now gated — see Fixed above; wrapped forms like `git -C … +main` still evade, by design.)
- `verifier_guard.sh` is a denylist: a read-only checker can still mutate via `python3 -c` / `node -e` / `perl -i` / `patch` / `install` / `ex` / `sh -c`.
- PreToolUse matcher is `Bash`-only: Write/Edit and MCP T2-equivalents (external send, remote delete/merge) reach no gate.

*Note:* the most honest-plausible of these is `git -C <path> push origin main` (a legit everyday flag). Closing it properly means dropping the `git…push` adjacency assumption across all four sub-gates — a larger, fragile rewrite. Deferred, not dismissed.

### Escalated — design roadmap (features, not bugs; already documented as future maturity)
- **V/L4:** holdout suite returning only a pass/fail bit, kept outside the loop (the direct cap on L3→L4).
- **O:** process-external circuit breaker + counters (reject rate, repeated tool calls, cost) — caps aren't enforced outside the model today.
- **G:** append-only side-effect ledger (replace overwrite `.last-*`) + independent kill-switch outside agent write-scope.
- **A7 auditability:** `.claude/loop/` is gitignored, so rubric-weakening has no git trail — force-track `rubric.md` per run or append the rubric diff to `review.md`.

## Next step
Top remaining item in build order: **add a holdout suite** (V, the L3 cap). Everything above it is either fixed or an accepted-by-design limitation of the forgetfulness-backstop model.
