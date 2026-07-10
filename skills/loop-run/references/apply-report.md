# Applying the verifier report

After each cycle's phase gate, the main agent does ALL state updates (the verifier only reports; it never writes):

- `rubric.md`: set `[x]` on criteria the report passed, `[ ]` otherwise.
- `state.md`: REWRITE as a summary — `loop_active`, `human_gate` (`none` | `ready_for_merge` | `pending_t2` | `stalled` — a deterministic marker the driver/notifier reads), iteration count, attempted / passed / unresolved (with consecutive-failure and `replan` count per criterion), and the token figure from `.claude/loop/.last-usage` if present, explicitly labeled "estimate". Max 100 lines. Never append (exception: the single 'loop interrupted' line the stop gate may demand).
  - Under `## Approaches tried (rejected)`, for each criterion the verifier still fails, add `- Rn: <approach just tried> → rejected: <why it failed>` — this is the episodic memory a fresh cycle relies on to not repeat a dead end (it is run-scoped state, NOT a distilled rule). Drop a criterion's entries once it passes; keep the last ~3-5 per criterion.
- `memory.md`: for each failure, follow the 5-step protocol (fail → investigate → verify → distill) per the loop-engineering skill's `references/memory-protocol.md`; tag `[plugin]` or `[project]`.
- `review.md`: OVERWRITE with the human review summary — files changed, key changes, risks. With codex, take the changed-file list from `.codex-last`, cross-checked with `git status --short` when the project is a git repo.
