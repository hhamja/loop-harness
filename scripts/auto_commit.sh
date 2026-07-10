#!/usr/bin/env bash
# loopy auto-commit (Stop hook).
#
# The mechanical complement of auto_push.sh for the OTHER half of the T0 rule
# (references/decision-gates.md): "local commits ... act autonomously, never
# re-ask". auto_push pushes an existing commit; this hook MAKES the commit, so a
# turn never ends with verified work left uncommitted and the human is never
# asked "shall I commit this?". auto_commit runs BEFORE auto_push in the Stop
# chain — commit, then push.
#
# Primary path is still the agent committing inline with a written message; this
# hook is the backstop that fires only when it didn't, giving a generic message.
#
# Commit ONLY if every guard holds — fail-open (exit 0, no commit) on any doubt:
#   1. .claude/loop/ exists          (else: non-loop session, do nothing)
#   2. stop_hook_active != true      (else: already re-prompting, don't commit)
#   3. auto_commit != false          (default true; opt out per project)
#   4. inside a git work tree, HEAD is a branch (not detached)
#   5. there is something to commit  (git status --porcelain non-empty)
#
# NOT gated on protected_branches or gate_push: a LOCAL commit is unconditionally
# T0 (undo with `git reset`), including on main in a direct-to-main repo where the
# workflow is exactly "commit locally, human gates the push". Only the push is
# gated (auto_push.sh / decision_gate.sh).
#
# ponytail: `git add -A` stages everything untracked too; on a work branch that is
# reversible T0 and gitignore covers secrets. Upgrade path if that ceiling bites:
# a pathspec / diff-scoped stage. Commit failure (e.g. a pre-commit hook) NEVER
# blocks the turn: logged to .claude/loop/.last-commit, hook still exits 0.
#
# Test seam: LOOP_AUTOCOMMIT_DRYRUN=1 prints "WOULD: git commit (<n> files)"
# instead of committing. Silent in normal operation.

set -u

INPUT="$(cat 2>/dev/null || true)"

# Hooks run in the project cwd; prefer the cwd field when present (mirrors auto_push).
HOOK_CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" 2>/dev/null || true
fi

LOOP_DIR=".claude/loop"

if [ "${LOOP_GUARD_DEBUG:-}" = "1" ] && [ -d "$LOOP_DIR" ]; then
  printf '%s auto_commit input=%s\n' "$(date +%s)" "$INPUT" >> "$LOOP_DIR/.hook-debug.log" 2>/dev/null || true
fi

# --- guard 1: not a loop project ---
[ -d "$LOOP_DIR" ] || exit 0

# --- guard 2: already re-prompted once (avoid committing mid-block) ---
if printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# --- session/loop gate (P1+P2): act only when THIS session actually ran a loop
# here (same-session .run-marker) AND no different fresh session holds the worktree
# lock. This is what stops a shared-working-tree session from auto-committing
# another session's changes. Logic + tests: scripts/loop_lock.sh. ---
CUR_SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
bash "$(cd "$(dirname "$0")" && pwd)/loop_lock.sh" gate "$CUR_SID" || exit 0

# --- guard 3: disabled per project ---
CONFIG="$LOOP_DIR/loop.config.md"
AUTO_COMMIT="true"
if [ -f "$CONFIG" ]; then
  a="$(sed -n 's/^auto_commit:[[:space:]]*//p' "$CONFIG" | head -n1)"
  case "$a" in false) AUTO_COMMIT="false" ;; esac
fi
[ "$AUTO_COMMIT" = "true" ] || exit 0

# --- guard 4: a git work tree with a checked-out branch (not detached) ---
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || exit 0   # detached HEAD -> never auto-commit

# --- guard 5: something to commit ---
STATUS="$(git status --porcelain 2>/dev/null)"
[ -n "$STATUS" ] || exit 0
N="$(printf '%s\n' "$STATUS" | grep -c .)"

# --- generic backstop message (subject + short file list) ---
FILES="$(printf '%s\n' "$STATUS" | sed 's/^...//' | head -n 10)"
MSG="$(printf 'chore(loop): auto-commit %s file(s) [Stop hook]\n\nBackstop for the T0 rule (local commit = autonomous). Amend with a\nwritten message if this belongs to a specific change.\n\n%s\n' "$N" "$FILES")"

# --- test seam: report instead of committing ---
if [ "${LOOP_AUTOCOMMIT_DRYRUN:-}" = "1" ]; then
  printf 'WOULD: git commit (%s files) on %s\n' "$N" "$BRANCH"
  exit 0
fi

# --- commit (best-effort; failure is logged, never blocks the turn) ---
git add -A >/dev/null 2>&1
ERR="$(git commit -m "$MSG" 2>&1)"; RC=$?
{
  printf 'branch=%s\n' "$BRANCH"
  printf 'files=%s\n' "$N"
  printf 'exit=%s\n' "$RC"
  printf 'committed_epoch=%s\n' "$(date +%s 2>/dev/null || echo 0)"
  [ "$RC" -eq 0 ] || printf 'error=%s\n' "$(printf '%s' "$ERR" | tr '\n' ' ' | cut -c1-300)"
} > "$LOOP_DIR/.last-commit" 2>/dev/null || true

exit 0
