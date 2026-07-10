#!/usr/bin/env bash
# loopy auto-PR (Stop hook).
#
# The third active complement to the decision doctrine (references/decision-gates.md):
# "opening a draft PR" is a T0 step (reversible, low blast radius) — act autonomously,
# never re-ask. auto_commit makes the commit, auto_push pushes the branch, and this
# hook opens the pull request, so the human returns to a PR ready to review + merge
# instead of a bare pushed branch. The MERGE stays the one human gate (T2).
#
# Runs LAST in the Stop chain (after the branch is pushed). Opens a PR ONLY if every
# guard holds — fail-open (exit 0, no PR) on any doubt:
#   1. .claude/loop/ exists                (else: non-loop session, do nothing)
#   2. stop_hook_active != true            (else: already re-prompting, stand down)
#   3. auto_pr != false                    (default true; opt out per project)
#   4. inside a git work tree, HEAD is a branch (not detached)
#   5. that branch is NOT protected        (never open a PR *from* main/master)
#   6. the branch has an upstream          (it was pushed — there is a head to PR from)
#   7. `gh` is installed and authenticated
#   8. there is NO open PR for this branch  (a merged/closed one + new commits -> new PR)
#
# Opens with `gh pr create --fill` (title/body from the commit log, base = the repo's
# default branch). Draft when `pr_draft: true`. Outcome logs to .claude/loop/.last-pr;
# failure never blocks the turn.
#
# Test seam: LOOP_AUTOPR_DRYRUN=1 prints "WOULD: gh pr create ..." after the local
# git guards and skips every `gh` call (so tests need no network or auth).

set -u

INPUT="$(cat 2>/dev/null || true)"

# Hooks run in the project cwd; prefer the cwd field when present (mirrors auto_push).
HOOK_CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" 2>/dev/null || true
fi

LOOP_DIR=".claude/loop"

if [ "${LOOP_GUARD_DEBUG:-}" = "1" ] && [ -d "$LOOP_DIR" ]; then
  printf '%s auto_pr input=%s\n' "$(date +%s)" "$INPUT" >> "$LOOP_DIR/.hook-debug.log" 2>/dev/null || true
fi

# --- guard 1: not a loop project ---
[ -d "$LOOP_DIR" ] || exit 0

# --- guard 2: already re-prompted once ---
if printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# --- session/loop gate (P1+P2): act only when THIS session actually ran a loop
# here (same-session .run-marker) AND no different fresh session holds the worktree
# lock. This is what stops a shared-working-tree session from opening a PR for
# another session's changes. Logic + tests: scripts/loop_lock.sh. ---
CUR_SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
bash "$(cd "$(dirname "$0")" && pwd)/loop_lock.sh" gate "$CUR_SID" || exit 0

# --- config ---
CONFIG="$LOOP_DIR/loop.config.md"
AUTO_PR="true"
PR_DRAFT="false"
PROTECTED="main master"
if [ -f "$CONFIG" ]; then
  a="$(sed -n 's/^auto_pr:[[:space:]]*//p' "$CONFIG" | head -n1)"
  case "$a" in false) AUTO_PR="false" ;; esac
  d="$(sed -n 's/^pr_draft:[[:space:]]*//p' "$CONFIG" | head -n1)"
  case "$d" in true) PR_DRAFT="true" ;; esac
  p="$(sed -n 's/^protected_branches:[[:space:]]*//p' "$CONFIG" | head -n1)"
  case "$p" in ''|TODO*|'<'*) : ;; *) PROTECTED="$p" ;; esac
fi

# --- guard 3: disabled per project ---
[ "$AUTO_PR" = "true" ] || exit 0

# --- guard 4: a git work tree with a checked-out branch (not detached) ---
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || exit 0

# --- guard 5: never open a PR from a protected branch ---
PROT_RE="$(printf '%s' "$PROTECTED" | tr -s ' ' '|' | sed 's/^|//;s/|$//')"
[ -n "$PROT_RE" ] || PROT_RE="main|master"
if printf '%s' "$BRANCH" | grep -Eq "^(${PROT_RE})$"; then
  exit 0
fi

# --- guard 6: the branch must have an upstream (it was pushed) ---
git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 || exit 0

# --- assemble the create command ---
set -- pr create --fill
[ "$PR_DRAFT" = "true" ] && set -- "$@" --draft

# --- test seam: report instead of touching gh ---
if [ "${LOOP_AUTOPR_DRYRUN:-}" = "1" ]; then
  printf 'WOULD: gh %s (head=%s)\n' "$*" "$BRANCH"
  exit 0
fi

# --- guard 7: gh installed and authenticated ---
command -v gh >/dev/null 2>&1 || exit 0
gh auth status >/dev/null 2>&1 || exit 0

# --- guard 8: no OPEN PR already exists for this branch ---
# `gh pr view` returns the latest PR of ANY state, so a merged one would mask a needed
# new PR — list open PRs for this head explicitly instead.
OPEN="$(gh pr list --head "$BRANCH" --state open --json number -q '.[].number' 2>/dev/null | head -n1)"
[ -z "$OPEN" ] || exit 0

# --- create (best-effort; failure is logged, never blocks the turn) ---
OUT="$(gh "$@" 2>&1)"; RC=$?
{
  printf 'branch=%s\n' "$BRANCH"
  printf 'cmd=gh %s\n' "$*"
  printf 'exit=%s\n' "$RC"
  printf 'created_epoch=%s\n' "$(date +%s 2>/dev/null || echo 0)"
  printf 'result=%s\n' "$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-300)"
} > "$LOOP_DIR/.last-pr" 2>/dev/null || true

exit 0
