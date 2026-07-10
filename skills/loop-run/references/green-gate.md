# Green gate — verify "done" before declaring it

When every rubric criterion passes, do NOT stop yet. Run this ONCE, on full runs only (never for `--once` or `--verify-only`):

1. Run the project's **full CI-equivalent locally** — everything the remote CI runs (lint, typecheck, tests, build), not just the rubric's per-criterion checks. Local verification must match CI or the branch goes red after push. Keep the two from drifting by giving CI a single entry point the loop also runs (loopy's own repo: `scripts/ci_local.sh`, which `ci.yml` calls verbatim; `auto_push.sh` runs it pre-push and stands down when red). A green rubric with a red CI is not done.
2. Spawn the `auditor` subagent ("audit this loop's process and decision-gate adherence").
3. Run the `/code-review` skill on the run's accumulated diff.
4. **Watch remote CI to green.** After the branch is pushed and its PR is open, run `bash scripts/ci_watch.sh` (or the project's `gh run watch` equivalent) to block on the real CI verdict. Remote CI passing is a T0/T1 verification the loop owns — never leave a red PR for the human. On red, reopen the failing check as a rubric criterion (its reproduction is the failing job) and keep looping to fix it, then re-push and re-watch.

If any of these surfaces a real defect, fold it into `rubric.md` as a new/reopened criterion and into `state.md` unresolved, then keep looping under the same rails — a rubric that is green but fails audit, review, or remote CI is not done.

**Cap and escalate.** This green→red→fix loop is bounded by `max_iterations`/`escalation` (loop.config.md). If CI can't be driven green within the cap, escalate to the human — not because fixing is risky (it is T0/T1), but because *stuck* is where real human judgment (replan / change approach) belongs. Never bypass or disable the check to force green; that is test/CI tampering.

When the rubric passes AND the green gate is clean (incl. remote CI green): overwrite `review.md` with the human-review summary, set `loop_active: false` and `human_gate: ready_for_merge`, and report done. Say explicitly: "done" is a claim — the merge stays the human's one T2 gate; list what to verify by hand before it.
