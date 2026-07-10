# Green gate — verify "done" before declaring it

When every rubric criterion passes, do NOT stop yet. Run this ONCE, on full runs only (never for `--once` or `--verify-only`):

1. Run the project's **full CI-equivalent locally** — everything the remote CI runs (lint, typecheck, tests, build), not just the rubric's per-criterion checks. Local verification must match CI or the branch goes red after push. Keep the two from drifting by giving CI a single entry point the loop also runs (loopy's own repo: `scripts/ci_local.sh`, which `ci.yml` calls verbatim; `auto_push.sh` runs it pre-push and stands down when red). A green rubric with a red CI is not done.
2. Spawn the `auditor` subagent ("audit this loop's process and decision-gate adherence").
3. Run the `/code-review` skill on the run's accumulated diff.

If either surfaces a real defect, fold it into `rubric.md` as a new/reopened criterion and into `state.md` unresolved, then keep looping under the same rails — a rubric that is green but fails audit or review is not done.

When the rubric passes AND the green gate is clean: overwrite `review.md` with the human-review summary, set `loop_active: false` and `human_gate: ready_for_merge`, and report done. Say explicitly: "done" is a claim — list what the human should verify by hand before merging.
