# Worktree Guide — parallel loop execution

Implemented by `/loopy:loop-worktree` (spawn a worker / integrate finished workers); this file is the doctrine it follows. Parallelism must be worth its token cost: several INDEPENDENT tasks, each with its own rubric subset.

## Procedure

1. Split the rubric into independent subsets. Tasks touching the same files are NOT independent — don't parallelize them.
2. Per task: `git worktree add ../<repo>-<task> -b loop/<task>`
3. Run one agent per worktree, scoped to its rubric subset. Each worktree is a separate checkout with its own index/HEAD, so the per-worktree loop lock (`loop_lock.sh`, acquired at preflight) is satisfied independently — this is exactly why parallel loops need separate worktrees rather than one shared tree (a shared tree serializes: the second `loop-run` is refused by the lock).
4. After merging (below): `git worktree remove ../<repo>-<task>` and delete the branch.

## Merge policy (mandatory)

- Parallel agents NEVER write the main `.claude/loop/state.md`.
- Each agent records its outcome in `.claude/loop/results/<task>.md` inside its own worktree: subset criteria pass/fail, files touched, unresolved items.
- Only the orchestrator (main session) merges: git-merge the branches, fold every `results/<task>.md` into the main `state.md`, then delete `results/`.
- A merge conflict on source files means the task split was wrong — redo the split; do not resolve blind.

## Cost warning

N worktrees ≈ N× token spend. Justify parallelism with wall-clock need, not tidiness (boundary principle 3).
