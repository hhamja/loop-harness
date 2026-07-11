# Harness review — loopy (self-review)

> 2026-07-11 09:49 KST (comprehensive pass) · target: `.` (loopy grading its own harness) · branch `feat/universal-gates` @ `9282328` · reviewers: loop-architect + design-critic + auditor + 2 explorers (hooks/CI, skills/agents/state); 3 command-settleable holes reproduced by the orchestrator in a fresh `mktemp -d` against the real scripts. Threat model per commit `0faabb4`: the gate hooks are a **forgetfulness backstop, not a sandbox** — a determined-adversary bypass is out of scope *by design*; a bug an *honest but forgetful* agent trips is in scope.
>
> This pass runs against a **live shared worktree** — a concurrent session committed `9282328` ("refactor: dedup shared parses … ponytail review") mid-review, which restored the fail-closed clock guard that had transiently regressed. The auditor and loop-architect both observed `187 passed, 1 failed`; at committed HEAD the orchestrator's full-permission run is **`188 passed, 0 failed`** (that failure was a transient WIP + a subagent-sandbox `date`-shim limitation, now moot). The three prior-pass honest-agent bugs (`rm -rf /*` under-match, `HEAD:refs/heads/main` protected push, clock fail-open) are all **FIXED and pinned** by golden tests. This pass surfaces **three NEW honest-agent holes** in the same gate scripts.

## ETCLOVG coverage

| | Responsibility | Verdict | Evidence |
|---|---|---|---|
| E | Execution | PARTIAL | codex maker runs fresh, sandboxed, egress-off per cycle (`skills/loop-run/references/codex-exec.md:3,9`); parallel workers get real worktree isolation (`skills/loop-worktree/SKILL.md:19-27`, `loop_lock.sh` cmd_acquire). Gaps: only per-worker cap is a 10-min wall-clock — no token/tool-call cap (`codex-exec.md:6`); documented claude-fallback maker runs unisolated in the orchestrator context (`skills/loop-run/SKILL.md:25`). |
| T | Tooling | PARTIAL | read-only checkers carry `disallowedTools: Write,Edit` (`agents/verifier.md:5` et al.) backed by `verifier_guard.sh` PreToolUse deny — **live-verified** (it blocked the loop-architect's and design-critic's own repro Bash). But it is denylist + Bash-matcher-only, `explorer` is excluded from the agent_type match (`verifier_guard.sh:30`), and it now carries a **normal-use false-positive** (H3) that blocks a checker's own source greps. Interpreter escapes remain (accepted, see below). |
| C | Context | PASS | durable `.claude/loop/*.md`; state.md rewritten ≤100 lines (hygiene machine-checked at Stop, `check_memory.sh:42-64`); codex rebuilds its prompt from disk each cycle and returns a summary only ("NEVER read `.codex-log`", `codex-exec.md:12`); checkers return per-criterion reports, not logs. |
| L | Lifecycle | PASS | `max_iterations:10`, `replan_max:2`, 3-fail→replan→escalate, "unbounded repeat-until-pass forbidden" (`skills/loop-run/SKILL.md:33-36`, `references/replan.md:11-27`); rubric/goal as decomposition artifacts. Caveats: caps are agent-counted, not process-external (L4 circuit-breaker gap); this repo's own `loop.config.md` carries no `max_iterations`/`escalation` keys (auditor A6). |
| V | Verification | PARTIAL | maker≠checker holds on permission (disallowedTools + guard) and incentive (falsification prompt, `agents/verifier.md:12`, `design-critic.md:8`) asymmetry; every rubric criterion carries a machine `verify:` command; gate order deterministic→nondeterministic and **local == CI** genuinely single-sourced (`.github/workflows/ci.yml:21` runs `bash scripts/ci_local.sh` verbatim). Two structural misses: **no information asymmetry — no holdout suite anywhere**; **no policy gate on the test/CI-tamper diff path** (PreToolUse matcher is Bash-only, so Edit/Write of `tests/`, `.github/workflows/`, gate scripts, or rubric `verify:` lines hits no gate). |
| O | Observability | FAIL | only `.last-usage` (transcript-bytes/4, `stop_gate.sh:48-63`), side-effect outcome logs (`.last-commit`/`.last-push`/`.last-pr`), and the `fleet.sh` live dashboard. Absent: checker reject-rate, repeated-identical-tool-call counter, visible-vs-holdout gap (structurally impossible without a holdout). 1 of 4 required counters, and it's an estimate. |
| G | Governance | PARTIAL | T2 class hard-blocked by hook, not prompt — publish/release/merge/force-push(+refspec)/tag-push/protected-branch-push/catastrophic-rm (`decision_gate.sh:88-141`); human approval via a one-shot, TTL'd, session-bound marker that **fails closed on clock doubt** (`decision_gate.sh:56-73`, pinned by `tests/run.sh:266-273`). But two existing gates leak on honest input (**H1** catastrophic-rm, **H2** protected-push); the marker/kill-switch/`state.md:human_gate` all live in agent-writable, gitignored scope (marker forgeable via the unhooked Write tool — accepted); side-effect logs overwrite-not-append (`.last-*` via `>`). |

**maturity: L3/5** — capped by the L4 requirement (**a holdout suite kept outside the loop, returning only a pass/fail bit**). The verifier grades the same fully-visible `rubric.md` the orchestrator authors; no maker-invisible check exists. Independently re-derived by loop-architect and converging with the repo's own control-plane doc (`docs/loop-control-plane.md` §10, holdout ✕). L4 additionally fails on the O counters and the agent-counted circuit breaker, but holdout is the earliest build-order gap.

## Holes (ranked by exploitability, CONFIRMED = reproduced in temp dir)

### NEW this pass — honest-agent bugs, in scope for the backstop

- **CONFIRMED · multi-operand `rm -rf … /` slips the catastrophic-delete gate** (`decision_gate.sh:139-140`, **top priority**). `CATA_TGT` is anchored immediately after the `-rf` flag whitespace (`…-rf[[:space:]]+${CATA_TGT}`), so **only the first operand** is inspected. A root/home target in any *later* position is ALLOWED. This is the exact irreversible honest catastrophe §5 advertises stopping (header line 22: "rm -rf of / ~ $HOME"), reachable by a stray-space/typo footgun (`rm -rf ./dist /`) or a later `$VAR` expanding to `/`. Repro (fresh temp dir, fed as Bash-tool JSON to the real script):

  ```sh
  G=/Users/kim/develop/loop-harness/scripts/decision_gate.sh; T=$(mktemp -d)
  dg(){ printf '{"cwd":"%s","session_id":"r","tool_input":{"command":%s}}' "$T" \
        "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
      | bash "$G" | grep -q '"deny"' && echo "DENY  | $1" || echo "ALLOW | $1"; }
  dg 'rm -rf /'            # DENY  (baseline)
  dg 'rm -rf ./build /'    # ALLOW <-- HOLE
  dg 'rm -rf /tmp/x /'     # ALLOW <-- HOLE
  dg 'rm -rf ./dist ~'     # ALLOW <-- HOLE
  ```

  Fix: match `/`/`~`/`$HOME` as an rm operand in **any** position, not just immediately after the flags (one added alternation over the operand list), plus a regression test mirroring the existing §5 shape.

- **CONFIRMED · bare `git push` on a protected branch slips the protected-push gate** (`decision_gate.sh:129`). The matcher is purely lexical — it needs a literal `main|master` (or `refs/heads/…`) token *in the command string* — but a PreToolUse hook cannot resolve HEAD. So the single most common push idiom carries no branch token and is ALLOWED under the default `gate_push:false`, even while the honest agent is sitting *on* a protected branch with `upstream=main`. Repro (same harness):

  ```sh
  dg 'git push'              # ALLOW <-- HOLE (when HEAD is a protected branch)
  dg 'git push origin'       # ALLOW <-- HOLE
  dg 'git push -u origin'    # ALLOW <-- HOLE
  dg 'git push origin main'  # DENY  (explicit token only)
  ```

  Architecturally bounded (the hook can't see HEAD) and partly mitigated elsewhere — `auto_push.sh` refuses to auto-push protected branches, and `gate_push:true` gates *every* push (`decision_gate.sh:108`) — but a manual `git push` typed by the agent reaches the decision_gate backstop and misses. Same non-evasive class as the reclassified `HEAD:refs/heads/main`, now machine-wide since 0.14.0. Fix (design decision): recommend `gate_push:true` as the machine-wide default, or resolve the current branch inside the hook.

- **CONFIRMED · `verifier_guard.sh` false-positive blocks a checker's own source greps** (`verifier_guard.sh:47,51,55,59`). The command-name checks do **not** strip quoted spans before matching, unlike the redirect check in the same file that explicitly does (`:63-70`, "a real redirect operator is never inside quotes"). So a read-only checker grepping source for a dangerous pattern is falsely DENIED — the auditor/critic's core job. Self-demonstrating: this very design-critic had two of its own greps live-blocked. Repro:

  ```sh
  V=/Users/kim/develop/loop-harness/scripts/verifier_guard.sh; T=$(mktemp -d)
  vg(){ printf '{"cwd":"%s","session_id":"r","agent_type":"loopy:design-critic","tool_input":{"command":%s}}' "$T" \
        "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
      | bash "$V" | grep -q '"deny"' && echo "DENY  | $1" || echo "ALLOW | $1"; }
  vg "grep -rn 'a|rm -rf|b' src"   # DENY  <-- FALSE POSITIVE
  vg "grep -E 'x|cp f|y' log"      # DENY  <-- FALSE POSITIVE
  vg "grep -rn 'TODO' src"         # ALLOW (correct)
  vg 'rm -rf x'                    # DENY  (correct baseline)
  ```

  Fix: strip quoted spans before the command-name matches, mirroring the `STRIPPED=` step at `verifier_guard.sh:68`; add a regression test asserting a quoted-pattern grep is ALLOWED while a bare mutation is still DENIED.

### Standing adversarial escalations — accepted by design (`0faabb4`), unchanged

All require a *determined* agent evading its own gate, which the forgetfulness-backstop model explicitly does not defend. Verified still ALLOW, none worse:

- forgeable `.gate-approved` marker written via the **unhooked Write tool** (PreToolUse matcher is `Bash`-only), session check skipped when the marker's `session_id` is empty (`decision_gate.sh:64`).
- command-form bypasses: `FOO=1 git push origin main` (env-prefix), `git -C /tmp push origin main` (`-C` breaks push-adjacency), `gh api -X PUT …/merge` (no `gh pr merge` form).
- `verifier_guard.sh` denylist → interpreter escape: `python3 -c`, `node -e`, `perl -i`, `patch -p1` all ALLOWED (`verifier_guard.sh` is a denylist; `disallowedTools` blocks the *tools*, not Bash-invoked writers).
- PreToolUse matcher is `Bash`-only: Write/Edit and MCP T2-equivalents reach no gate.

### PLAUSIBLE — design-level, not command-settleable

- **maker≠checker tautology / no holdout** (`skills/loop-run/SKILL.md:28`): the verifier grades a `rubric.md` whose criteria + `verify:` commands the maker authors, with no maker-invisible check. Incentive leg holds; information leg absent; permission leg leaks (Bash-only matcher on the diff path). This is the L3→L4 cap, not a reproduced exploit.
- **loop-independent over-blocking** (design intent, `decision_gate.sh:8-13`): since 0.14.0 the gate runs in *every* repo, so `git push origin main`/`npm publish` are DENY-by-default machine-wide — friction for a solo direct-to-main workflow. A documented tradeoff, not a bug.

### REFUTED (dropped)

- **clock fail-open**: a mid-edit WIP snapshot had transiently reverted the guard; committed HEAD `9282328` restores `now>0 → return 1`, pinned by `tests/run.sh:266-273`. Suite `188/0`. Does not exist in the committed state.
- **3 prior-pass honest bugs**: `rm -rf /*` → DENY (`decision_gate.sh:139`), `git push origin HEAD:refs/heads/main` → DENY (`:129`), clock fail-closed — all reproduced DENY, no regression.
- **local == CI**: `.github/workflows/ci.yml:21` runs exactly `bash scripts/ci_local.sh` — genuine single source, no drift.

## Process notes (auditor + explorers)

- **This repo is a plugin-source workspace, not a compliant loop.** Its `.claude/loop/` exists but is gate-fixes scaffolding: `memory.md` absent (A3), `loop.config.md` has no `max_iterations`/`escalation` keys (A6), and `.claude/loop/` is gitignored so `rubric.md` weakening can't be audited from history (A7). The **human merge gate held**: PRs #13/#16/#18 all merged by `hhamja`; the one destructive `rm` had a recorded one-shot approval (`review.md:9-10`); a push was skipped when CI was red (`.last-push`). These process items are N/A-by-intent for a plugin workspace, not loop-run violations — but if this dir is ever run as a real loop, A3/A6/A7 need closing.
- **Live shared-worktree hazard**: the transient `187/1` both independent reviewers saw was a peer session's uncommitted WIP. Any point-in-time claim against a shared tree is fragile; grade against a committed SHA (done here: `9282328`).

## Next step

Review-only pass (no `--fix`). Build order (§9 — enforcement holes and verifier/holdout before observability before governance polish):

1. **Multi-operand catastrophic `rm`** (`decision_gate.sh:139-140`) — top honest-agent fix; match root/home in any operand position + regression test. One-line-ish regex, machine-checkable.
2. **verifier_guard quote-stripping** (`verifier_guard.sh:47-59`) — strip quoted spans before command-name matches (mirror `:68`) + regression test. Restores the checker's audit function. Machine-checkable.
3. **Bare `git push` protected-branch** (`decision_gate.sh:129`) — design decision: `gate_push:true` machine-wide default, or in-hook branch resolution. Escalate into a PR discussion, not a pure auto-fix.
4. **Holdout suite** (V, the L3→L4 cap) — the only structural item; a maker-invisible check run at the green gate, returning a pass/fail bit. Also the sole path to the visible-vs-holdout counter.
5. **Test/CI-tamper diff-path gate** (V/G) — Edit/Write PreToolUse hook (or a diff-path check in `ci_local.sh`) treating `tests/`, `.github/workflows/`, `hooks/`, gate scripts, and rubric `verify:` lines as T2.
6. **Observability counters + process-external circuit breaker** (O/L4); then **governance polish** (append-only `.last-*` ledger, external kill-switch, per-T2 rollback plan) and this repo's own `loop.config.md` A6 keys.

Items 1–2 are machine-checkable honest-agent bugs suitable for `/loopy:loop-review --fix`. Item 3 is a design decision; 4–6 are documented roadmap. The adversarial escalations remain accepted-by-design under `0faabb4`.
