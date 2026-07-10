#!/usr/bin/env bash
# loopy auto-commit (Stop hook).
#
# The mechanical complement of auto_push.sh for the OTHER half of the T0 rule
# (references/decision-gates.md): "local commits ... act autonomously, never
# re-ask". auto_push pushes an existing commit; this hook MAKES the commit, so a
# turn never ends with verified work left uncommitted and the human is never
# asked "shall I commit this?". auto_commit runs BEFORE auto_push in the Stop
# chain — commit, then push. Interactive and loop sessions alike: since 0.13.0
# this hook no longer requires a same-session .run-marker.
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
# Shared-tree safety — staging is SCOPED, not gated (replaces the 0.12.0 P1
# run-marker stand-down for this hook):
#   alone in the tree  -> `git add -A` (the never-lose-work backstop, as before)
#   a DIFFERENT live session present (loop_lock.sh others: fresh .session-lock
#   or fresh foreign .touched-* manifest) -> stage ONLY the paths THIS session
#   touched (its .touched-<sid> manifest, written by touch_track.sh), so two
#   sessions in one tree both commit without sweeping each other's work.
# ponytail: while contended, Bash side effects (lockfiles, codegen) are not in
# the manifest and stay uncommitted until the tree is uncontended again.
#
# Worker mode (loop.config.md has `worker: <task>`, set by /loopy:loop-worktree):
# never stage ANYTHING under .claude/loop/ except results/ — a worker's outcome
# goes in results/<task>.md (unique name, merges clean); its local state.md,
# subset rubric/goal, and worker config stay uncommitted so integrating the task
# branch can't conflict with — or overwrite — the orchestrator's loop files.
#
# Test seam: LOOP_AUTOCOMMIT_DRYRUN=1 prints "WOULD: git commit (<n> files)"
# instead of committing. Silent in normal operation.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/hook_lib.sh
. "$SCRIPT_DIR/hook_lib.sh"
hook_init
hook_debug auto_commit

# --- guard 1: not a loop project ---
[ -d "$LOOP_DIR" ] || exit 0

# --- guard 2: already re-prompted once (avoid committing mid-block) ---
stop_hook_active && exit 0

# --- guard 3: disabled per project ---
[ "$(cfg_flag auto_commit true)" = "true" ] || exit 0
WORKER="$(config_field worker)"

# --- guard 4: a git work tree with a checked-out branch (not detached) ---
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || exit 0   # detached HEAD -> never auto-commit

# --- session scope: my manifest + is a different live session sharing this tree? ---
SID="$(sid_safe "$(json_str session_id)")"
MANIFEST="$LOOP_DIR/.touched-$SID"
# GC manifests idle past the lock TTL (finished or crashed sessions)
find "$LOOP_DIR" -maxdepth 1 -name '.touched-*' -mmin "+$(( ${LOOP_LOCK_TTL:-3600} / 60 ))" \
  -exec rm -f {} + 2>/dev/null || true
if bash "$SCRIPT_DIR/loop_lock.sh" others "$SID"; then CONTENDED=1; else CONTENDED=0; fi

# --- guard 5: something to commit (worker mode: only results/ counts under .claude/loop/) ---
STATUS="$(git status --porcelain 2>/dev/null)"
if [ -n "$WORKER" ]; then
  # -uall expands collapsed untracked dirs (`?? .claude/`) into file lines, then
  # drop .claude/loop/ lines unless they are results/ (sed: on non-results lines, delete loop lines)
  STATUS="$(git status --porcelain -uall 2>/dev/null | sed '\#\.claude/loop/results#!{\#\.claude/loop/#d;}')"
fi
[ -n "$STATUS" ] || { rm -f "$MANIFEST" 2>/dev/null; exit 0; }

# --- contended non-worker tree: narrow the status to MY manifest paths ---
# (worker trees are dedicated worktrees — the worker pathspec already scopes them)
if [ "$CONTENDED" -eq 1 ] && [ -z "$WORKER" ]; then
  [ -s "$MANIFEST" ] || exit 0   # nothing of mine recorded -> stand down
  TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
  REL="$(sed "s|^$TOP/||" "$MANIFEST" | sort -u)"
  SCOPED=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line:3}"; p="${p##* -> }"
    case "$p" in \"*\") p="${p#\"}"; p="${p%\"}" ;; esac
    if printf '%s\n' "$REL" | grep -Fxq -- "$p"; then
      SCOPED="${SCOPED}${line}
"
    fi
  done <<< "$STATUS"
  STATUS="${SCOPED%$'\n'}"   # drop the trailing newline the loop appended
  [ -n "$STATUS" ] || { rm -f "$MANIFEST" 2>/dev/null; exit 0; }
fi
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
if [ -n "$WORKER" ]; then
  git add -A -- . ':!.claude/loop' >/dev/null 2>&1
  git add -A -- .claude/loop/results >/dev/null 2>&1   # re-include results/<task>.md
elif [ "$CONTENDED" -eq 1 ]; then
  # a peer session is live in this tree: stage exactly the scoped paths, never -A
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    p="${line:3}"; p="${p##* -> }"
    case "$p" in \"*\") p="${p#\"}"; p="${p%\"}" ;; esac
    git add -A -- "$p" >/dev/null 2>&1
  done <<< "$STATUS"
else
  git add -A >/dev/null 2>&1
fi
ERR="$(git commit -m "$MSG" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && rm -f "$MANIFEST" 2>/dev/null   # committed -> manifest served its purpose
{
  printf 'branch=%s\n' "$BRANCH"
  printf 'files=%s\n' "$N"
  printf 'exit=%s\n' "$RC"
  printf 'committed_epoch=%s\n' "$(date +%s 2>/dev/null || echo 0)"
  [ "$RC" -eq 0 ] || printf 'error=%s\n' "$(printf '%s' "$ERR" | tr '\n' ' ' | cut -c1-300)"
} > "$LOOP_DIR/.last-commit" 2>/dev/null || true

exit 0
