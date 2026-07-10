---
name: loop-worktree
description: Spawn an isolated git-worktree worker for a rubric subset; integrate finished workers back
disable-model-invocation: true
argument-hint: "<task> [R# ...] | --integrate <task> [<task> ...]"
---

# loop-worktree — isolated parallel workers (spawn / integrate)

Implements the loop-engineering skill's `references/worktree-guide.md`: one work unit = one worktree = one branch. Parallelize ONLY file-disjoint rubric subsets — tasks touching the same files are NOT independent; run those serially in this tree. N worktrees ≈ N× token spend: justify with wall-clock need, not tidiness.

Arguments (`$ARGUMENTS`): `<task> [R# ...]` = spawn a worker. `--integrate <task> [<task> ...]` = fold finished workers back.

## Spawn

Requires `.claude/loop/` (else: run `/loopy:loop-init` first, stop).

1. Verify every requested `R#` exists in `rubric.md`, and that this subset's implementation files are disjoint from every other planned/live task. Overlap → do not spawn; say why.
2. `git worktree add ../<repo>-<task> -b <type>/<task>` — cut from the current work branch, never a protected one.
3. Scaffold the worker's `.claude/loop/` in the new worktree:
   - `rubric.md`: ONLY the requested `R#` lines, `verify:` commands byte-identical.
   - `goal.md`: one line describing the subset.
   - `loop.config.md`: copy of this tree's, then set `worker: <task>`, `branch: <type>/<task>`, `auto_push: false`, `auto_pr: false` — workers never push or open PRs; the orchestrator integrates locally.
   - `state.md`, `memory.md`, `review.md`: fresh from loop-init templates.
4. Report the worktree path, branch, and next step: open a NEW session in that directory and run `/loopy:loop-run`. Each worktree has its own index/HEAD, so `loop_lock` and `branch_guard` are satisfied independently.

**Worker contract** (auto_commit's worker mode enforces the commit side): a worker commits its source changes plus `.claude/loop/results/<task>.md` ONLY — nothing else under `.claude/loop/` (its local state.md, subset rubric/goal, and worker config stay uncommitted, so integrating the branch cannot overwrite the orchestrator's loop files). `results/<task>.md` records: subset criteria pass/fail, files touched, unresolved items.

## Integrate (orchestrator only, in the main tree)

Run only when the named workers report done (their `results/<task>.md` exists on the branch). Per task:

1. `git merge --no-ff <type>/<task>` into the work branch (T0 — local, not a protected branch). A conflict on SOURCE files means the split was wrong: `git merge --abort`, redo the split — never resolve blind.
2. Fold `.claude/loop/results/<task>.md` into the main `state.md` (passed → Passed, unresolved → Unresolved, files touched → Attempted), then delete the results file.
3. `git worktree remove ../<repo>-<task>` and `git branch -d <type>/<task>`.

After all tasks: spawn the `verifier` once against the full `rubric.md` — integration is a claim until graded. Then normal loop-run flow (green gate, PR, human merge) applies to the combined work branch.
