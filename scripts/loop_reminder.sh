#!/usr/bin/env bash
# loopy loop reminder (SessionStart hook).
#
# Carries the ENTRY of the loop workflow into every project. The doctrine
# ("substantial implementation goes through /loopy:loop-init then
# /loopy:loop-run") is machine-wide, but the loop runtime only exists where
# `.claude/loop/` does — so in a git project without one, this hook injects a
# one-line reminder at session start (SessionStart stdout is added to context).
#
# It never blocks: "is this substantial?" is a judgment call the model makes;
# the hook only supplies the fact it tends to forget. Fail-open on any doubt.
# Noise control: git worktrees only — a session in a non-project directory
# gets no coding-policy reminder.

set -u

# shellcheck source=scripts/hook_lib.sh
. "$(cd "$(dirname "$0")" && pwd)/hook_lib.sh"
hook_init

# already a loop project -> the loop runtime and its gates take it from here
[ -d "$LOOP_DIR" ] && exit 0

# not a git worktree -> not a code project, stay silent
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

printf '%s\n' "loopy: this project has no .claude/loop/. Per user policy, substantial code implementation (new features, multi-file changes) must go through /loopy:loop-init then /loopy:loop-run (Codex as maker when available). Trivial edits are exempt."
exit 0
