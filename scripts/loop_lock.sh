#!/usr/bin/env bash
# loopy session ownership + per-worktree loop lock — the single tested home of the
# concurrency logic the Stop hooks and loop-run preflight need. Operates on
# .claude/loop/ relative to the CURRENT directory (callers cd into the project first).
#
# Why: the auto_commit/push/pr Stop hooks fire on EVERY Stop in a repo that has
# .claude/loop/, and auto_commit does `git add -A`. In a shared working tree two
# sessions then entangle each other's changes. This script gates those side effects.
#
# Subcommands:
#   gate <cur_sid>        exit 0 = the auto_* hook MAY act, exit 1 = stand down.
#                         P1: act only when a same-session .run-marker exists
#                             (this session actually ran a loop here).
#                         P2: never act while a DIFFERENT fresh session holds
#                             .session-lock.
#   others <cur_sid>      exit 0 = a DIFFERENT live session is present in this
#                         tree (fresh .session-lock by another sid, or a fresh
#                         foreign .touched-* manifest — which doubles as a
#                         presence marker: Bash-only sessions bump it too).
#                         auto_commit narrows its staging to this session's
#                         manifest on 0, sweeps with add -A on 1. <cur_sid> is
#                         reduced to its sid_safe form.
#   acquire <sid> <pid>   take/refresh .session-lock. exit 0 = owned by <sid>,
#                         exit 1 = a different fresh session owns it (refuse).
#   release <sid>         drop .session-lock if owned by <sid> (or stale/absent).
#
# Escape hatch: LOOP_LOCK_DISABLE=1 makes gate/acquire pass unconditionally.
# TTL: a lock older than LOOP_LOCK_TTL seconds (default 3600) is stale (crash
# backstop) and may be stolen. "known" sid = non-empty and != "unknown".

set -u

LOOP_DIR=".claude/loop"
MARKER="$LOOP_DIR/.run-marker"
LOCK="$LOOP_DIR/.session-lock"
TTL="${LOOP_LOCK_TTL:-3600}"

now() { date +%s; }

# field <file> <key>  -> value of `key=...` (first match), empty if absent
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1; }

known() { [ -n "$1" ] && [ "$1" != "unknown" ]; }

# lock_is_stale  -> 0 (true) if LOCK absent, or its epoch is missing/non-numeric,
# or older than TTL. Callers guard on `[ -f "$LOCK" ]` first where it matters.
lock_is_stale() {
  local e age
  e="$(field "$LOCK" epoch)"
  case "$e" in ''|*[!0-9]*) return 0 ;; esac
  age=$(( $(now) - e ))
  [ "$age" -gt "$TTL" ]
}

write_lock() { printf 'session_id=%s\npid=%s\nepoch=%s\n' "$1" "$2" "$(now)" > "$LOCK"; }

# file_fresh <path> — 0 (true) when the file's mtime is within TTL. GNU stat
# (-c) FIRST: it hard-fails on BSD, while BSD's -f is *silently wrong* on GNU
# (-f = file-system mode there; %m prints the mount point, not an epoch) — so
# the GNU form must be the one probed. Unreadable mtime -> not fresh (fails
# toward "alone": the wider add -A backstop).
file_fresh() {
  local e
  e="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo)"
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  [ $(( $(now) - e )) -le "$TTL" ]
}

cmd_gate() {
  local cur_sid="${1:-}"
  [ "${LOOP_LOCK_DISABLE:-}" = "1" ] && return 0

  # P1 — this session must have actually run a loop here (same-session marker).
  [ -f "$MARKER" ] || return 1
  local m_sid; m_sid="$(field "$MARKER" session_id)"
  if known "$m_sid" && known "$cur_sid"; then
    [ "$m_sid" = "$cur_sid" ] || return 1   # a different session's loop -> stand down
  fi
  # (unknown on either side: marker presence is the weak signal; P2 covers safety)

  # P2 — a different fresh session holding the worktree lock blocks us.
  if [ -f "$LOCK" ] && ! lock_is_stale; then
    local l_sid; l_sid="$(field "$LOCK" session_id)"
    if known "$l_sid" && known "$cur_sid" && [ "$l_sid" != "$cur_sid" ]; then
      return 1
    fi
  fi
  return 0
}

cmd_others() {
  local cur_sid="${1:-}"
  [ "${LOOP_LOCK_DISABLE:-}" = "1" ] && return 1
  # reduce to the same filename-safe form touch_track names manifests with
  cur_sid="$(printf '%s' "$cur_sid" | tr -cd 'A-Za-z0-9._-')"
  [ -n "$cur_sid" ] || cur_sid="unknown"

  # a fresh lock held by a different known session
  if [ -f "$LOCK" ] && ! lock_is_stale; then
    local l_sid; l_sid="$(field "$LOCK" session_id)"
    if known "$l_sid" && [ "$l_sid" != "$cur_sid" ]; then
      return 0
    fi
  fi

  # a fresh foreign manifest: another session edited files here within TTL
  local m
  for m in "$LOOP_DIR"/.touched-*; do
    [ -f "$m" ] || continue
    [ "$m" = "$LOOP_DIR/.touched-$cur_sid" ] && continue
    if file_fresh "$m"; then return 0; fi
  done
  return 1
}

cmd_acquire() {
  local sid="${1:-}" pid="${2:-}"
  [ "${LOOP_LOCK_DISABLE:-}" = "1" ] && return 0
  [ -d "$LOOP_DIR" ] || return 0

  if [ -f "$LOCK" ] && ! lock_is_stale; then
    local l_sid; l_sid="$(field "$LOCK" session_id)"
    if known "$l_sid" && known "$sid" && [ "$l_sid" != "$sid" ]; then
      printf 'loop_lock: worktree already held by session %s (started %ss ago). Run in a separate git worktree, stop that session, or wait for the lock to expire (TTL %ss).\n' \
        "$l_sid" "$(( $(now) - $(field "$LOCK" epoch) ))" "$TTL" >&2
      return 1
    fi
    # mine (or ambiguous) -> refresh below
    write_lock "$sid" "$pid"
    return 0
  fi

  # absent or stale: create atomically when absent (noclobber), else overwrite the stale one.
  if [ ! -f "$LOCK" ]; then
    # ponytail: set -C makes first-create atomic; a simultaneous first-acquire in the
    # same tree (rare) can still race — gate + marker are the backstop. Upgrade to an
    # mkdir lock if that race ever bites.
    if ( set -C; write_lock "$sid" "$pid" ) 2>/dev/null; then return 0; fi
    # lost the create race: re-evaluate as held
    local l_sid; l_sid="$(field "$LOCK" session_id)"
    if ! lock_is_stale && known "$l_sid" && known "$sid" && [ "$l_sid" != "$sid" ]; then
      printf 'loop_lock: worktree just taken by session %s.\n' "$l_sid" >&2
      return 1
    fi
  fi
  write_lock "$sid" "$pid"
  return 0
}

cmd_release() {
  local sid="${1:-}"
  [ -f "$LOCK" ] || return 0
  local l_sid; l_sid="$(field "$LOCK" session_id)"
  if [ -z "$l_sid" ] || [ -z "$sid" ] || [ "$l_sid" = "$sid" ] || lock_is_stale; then
    rm -f "$LOCK"
  fi
  return 0
}

case "${1:-}" in
  gate)    shift; cmd_gate "$@";    exit $? ;;
  others)  shift; cmd_others "$@"; exit $? ;;
  acquire) shift; cmd_acquire "$@"; exit $? ;;
  release) shift; cmd_release "$@"; exit $? ;;
  *) printf 'usage: loop_lock.sh {gate <sid>|others <sid>|acquire <sid> <pid>|release <sid>}\n' >&2; exit 2 ;;
esac
