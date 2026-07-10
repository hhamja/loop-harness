#!/usr/bin/env bash
# loopy touch-track (PostToolUse hook: Bash|Edit|Write|NotebookEdit).
#
# Two jobs, one file per session (.claude/loop/.touched-<sid>):
#   1. MANIFEST — every file this session changes through the file tools is
#      appended, and auto_commit.sh stages ONLY these paths while another live
#      session shares the working tree (instead of `git add -A`), so two
#      sessions in one tree both auto-commit without sweeping each other's work.
#   2. PRESENCE — a Bash call carries no file_path, but it can still change
#      files (redirects, formatters, installs). It bumps the manifest's mtime,
#      so loop_lock.sh `others` sees this session as LIVE and peers stop
#      sweeping with add -A. The Bash-made paths themselves stay unstaged while
#      contended (the documented ceiling) — unknown paths are never guessed.
# (The 0.12.0 run-marker gate solved the entanglement by standing down entirely
# — interactive sessions got no auto commit/push at all; this scopes instead.)
#
# Fast path by design: one append or touch, no git calls — it fires per tool use.
# Silent, always exits 0.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/hook_lib.sh
. "$SCRIPT_DIR/hook_lib.sh"
hook_init
hook_debug touch_track

# not a loop project -> do nothing
[ -d "$LOOP_DIR" ] || exit 0

SID="$(sid_safe "$(json_str session_id)")"
FP="$(tool_str file_path)"
if [ -n "$FP" ]; then
  printf '%s\n' "$FP" >> "$LOOP_DIR/.touched-$SID" 2>/dev/null || true
else
  # no file_path (Bash et al.): presence only — freshen, never add paths
  touch "$LOOP_DIR/.touched-$SID" 2>/dev/null || true
fi
exit 0
