# loop-run preflight

Run once before the first cycle. Skip entirely for `--verify-only`.

## Implementer

Read `implementer:` from loop.config.md (a missing key means `claude`). If it is `codex`, run `codex --version` once via Bash. On failure, use claude for the entire run and record "codex unavailable, fell back to claude" in state.md and memory.md. Check once per run, never per cycle — `codex --version` succeeds on an installed-but-unauthenticated CLI, and the per-cycle fallback in `codex-exec.md` covers that.

## Run marker

Write the marker so the Stop gate can tell an interrupted run from a finished one (one Bash command):

```bash
sid="${CLAUDE_CODE_SESSION_ID:-unknown}"; [ -n "$sid" ] || sid=unknown; printf 'session_id=%s\ntimestamp=%s\n' "$sid" "$(date +%s)" > .claude/loop/.run-marker
```

`CLAUDE_CODE_SESSION_ID` is version-dependent; `unknown` is the accepted fallback (the Stop gate then fails open).

## Reconcile the open PR (CI is the loop's, not the human's)

Before new work, reconcile the branch's remote state — a red PR is T0/T1 to fix, so the loop owns it and never leaves it for the human (only the merge is T2):

- If the branch has an **open PR whose latest CI is red**, make fixing it the first goal this run: reopen the failing check as a rubric criterion and close it before starting new work.
- If the branch is **ahead of base with no open PR** (e.g. a prior PR merged, then new commits landed), it is unreviewed — a new PR must be opened for it (the `auto_pr` Stop hook does this automatically; open one by hand if the hooks are inactive).

Run `bash scripts/ci_watch.sh` (or the project equivalent) to read the current verdict. This is the same watch the green gate uses — see `green-gate.md`.
