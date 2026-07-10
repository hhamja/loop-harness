#!/usr/bin/env bash
# loopy touch-track (PostToolUse hook: Edit|Write|NotebookEdit).
#
# Records every file THIS session changes through the file tools into a
# per-session manifest (.claude/loop/.touched-<sid>). auto_commit.sh reads it
# when another live session shares this working tree: it stages ONLY the
# manifest paths instead of `git add -A`, so two sessions in one tree can both
# auto-commit without sweeping each other's work. (The 0.12.0 run-marker gate
# solved that entanglement by standing down entirely — interactive sessions got
# no auto commit/push at all; this solves it by scoping WHAT is staged instead.)
#
# Fast path by design: one append, no git calls — it fires on every file edit.
# ponytail: Bash side effects (a lockfile from `pnpm install`, codegen) are not
# tracked; while another session is live they stay uncommitted until the tree
# is uncontended again. Upgrade path: snapshot `git status` around Bash calls.
#
# Silent, always exits 0.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/hook_lib.sh
. "$SCRIPT_DIR/hook_lib.sh"
hook_init
hook_debug touch_track

# not a loop project -> do nothing
[ -d "$LOOP_DIR" ] || exit 0

FP="$(tool_str file_path)"
[ -n "$FP" ] || exit 0

SID="$(sid_safe "$(json_str session_id)")"
printf '%s\n' "$FP" >> "$LOOP_DIR/.touched-$SID" 2>/dev/null || true
exit 0
