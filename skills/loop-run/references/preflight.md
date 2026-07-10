# loop-run preflight

Run once before the first cycle. Skip entirely for `--verify-only`.

## Implementer

Read `implementer:` from loop.config.md (a missing key means `claude`). If it is `codex`, run `codex --version` once via Bash. On failure, use claude for the entire run and record "codex unavailable, fell back to claude" in state.md and memory.md. Check once per run, never per cycle — `codex --version` succeeds on an installed-but-unauthenticated CLI, and the per-cycle fallback in `codex-exec.md` covers that.

## Run marker + worktree lock

Write the marker (so the Stop gate can tell an interrupted run from a finished one) and acquire the per-worktree loop lock (so a second concurrent loop in the same working tree can't entangle this one). One Bash block:

```bash
sid="${CLAUDE_CODE_SESSION_ID:-unknown}"; [ -n "$sid" ] || sid=unknown
printf 'session_id=%s\ntimestamp=%s\n' "$sid" "$(date +%s)" > .claude/loop/.run-marker
bash "${CLAUDE_PLUGIN_ROOT:-}/scripts/loop_lock.sh" acquire "$sid" "$$"; lock_rc=$?
```

`CLAUDE_CODE_SESSION_ID` is version-dependent; `unknown` is the accepted fallback (the Stop gate then fails open).

**If `lock_rc` is 1** another live session already owns this working tree — do NOT run cycles. Tell the user to run in a separate `git worktree`, stop that other session, or wait for the lock TTL (`LOOP_LOCK_TTL`, default 3600s) to expire; then end the turn. Any other outcome (0, or a non-1 error if the plugin path can't resolve) → proceed. The same-session marker + this lock are what let the `auto_commit`/`auto_push`/`auto_pr` Stop hooks fire ONLY for this session's loop and stand down for everyone else (`scripts/loop_lock.sh gate`).

## Release the lock

When the loop ends this turn with `loop_active: false` (green gate done → `ready_for_merge`, or `stalled`/`needs_branch`, or an aborted run), release the lock so the tree is free for the next session:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-}/scripts/loop_lock.sh" release "${CLAUDE_CODE_SESSION_ID:-unknown}"
```

If the turn ends with `loop_active: true` (more cycles next turn), keep the lock — the next preflight refreshes it. A crashed run that never releases is covered by the TTL.

## Branch (never work on a protected branch)

Before reconciling remote state, land on the work branch: `bash scripts/branch_guard.sh` (or the project equivalent). GitHub Flow — one small work unit = one `<type>/<slug>` branch off the default branch; the merge stays the one human gate. The guard is fail-open (`SKIP:`/`OK:`/`BRANCHED:`, exit 0) except one hard stop: `NEED:` (exit 1) when HEAD is a protected branch (`main`/`master`) with no usable `branch:` key in `loop.config.md`. On `NEED`, do not start the cycle — interactive: ask for the `<type>/<slug>` name and write it to `loop.config.md`, then rerun; headless: record the reason in state.md, set `human_gate: needs_branch`, and end the turn.

## Reconcile the open PR (CI is the loop's, not the human's)

Before new work, reconcile the branch's remote state — a red PR is T0/T1 to fix, so the loop owns it and never leaves it for the human (only the merge is T2):

- If the branch has an **open PR whose latest CI is red**, make fixing it the first goal this run: reopen the failing check as a rubric criterion and close it before starting new work.
- If the branch is **ahead of base with no open PR** (e.g. a prior PR merged, then new commits landed), it is unreviewed — a new PR must be opened for it (the `auto_pr` Stop hook does this automatically; open one by hand if the hooks are inactive).

Run `bash scripts/ci_watch.sh` (or the project equivalent) to read the current verdict. This is the same watch the green gate uses — see `green-gate.md`.
