#!/usr/bin/env bash
# loopy auto-push (Stop hook).
#
# Realizes the decision doctrine's T0 rule "pushing a work branch is reversible ->
# act autonomously, never re-ask" (references/decision-gates.md). decision_gate.sh
# BLOCKS pushing a protected branch; this hook is its complement — it PUSHES the
# current work branch at turn end so the human never has to say "and push it".
# Interactive and loop sessions alike: since 0.13.0 no .run-marker is required.
#
# Push ONLY if every guard holds — fail-open (exit 0, no push) on any doubt:
#   1. .claude/loop/ exists                (else: non-loop session, do nothing)
#   2. stop_hook_active != true            (else: already re-prompting, don't push)
#   3. auto_push != false                  (default true; opt out per project)
#   4. gate_push != true                   (direct-to-main repo: every push is T2 ->
#                                           auto-push would contradict the gate)
#   5. inside a git work tree, HEAD is a branch (not detached)
#   6. that branch is NOT in protected_branches (default "main master") — a protected
#      branch is never auto-pushed; that stays a human gate (decision_gate.sh)
#   7. there is something to push:
#        upstream set     -> only when ahead > 0 (`git push`)
#        no upstream, origin exists, HEAD has a commit -> `git push -u origin <branch>`
#
# NEVER force-pushes, never pushes tags. Push failure NEVER blocks the turn: the
# outcome is logged to .claude/loop/.last-push and the hook still exits 0.
#
# Test seam: LOOP_AUTOPUSH_DRYRUN=1 prints "WOULD: <cmd>" instead of pushing.
# This hook writes nothing to stdout in normal operation (a silent enforcer).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/hook_lib.sh
. "$SCRIPT_DIR/hook_lib.sh"
hook_init
hook_debug auto_push

# --- guard 1: not a loop project ---
[ -d "$LOOP_DIR" ] || exit 0

# --- guard 2: already re-prompted once (avoid pushing mid-block) ---
stop_hook_active && exit 0

# (No session/loop gate since 0.13.0: pushing publishes COMMITS, and commits are
# already correctly scoped per session by auto_commit's manifest staging — so a
# work-branch push is safe from any session, interactive or loop. The shared-tree
# entanglement lived in `git add -A`, not in push.)

# --- guard 3 & 4: disabled, or a direct-to-main repo where every push is a gate
# (config accessors: hook_lib.sh — the same parse decision_gate enforces with) ---
[ "$(cfg_flag auto_push true)" = "true" ] || exit 0
[ "$(cfg_flag gate_push false)" != "true" ] || exit 0

# --- guard 5: a git work tree with a checked-out branch (not detached) ---
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || exit 0   # detached HEAD -> never auto-push

# --- guard 6: the current branch must not be protected ---
if printf '%s' "$BRANCH" | grep -Eq "^($(protected_re))$"; then
  exit 0
fi

# --- guard 7: decide what (if anything) to push ---
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  # upstream set: push only when the branch is ahead of it
  AHEAD="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  case "$AHEAD" in ''|*[!0-9]*) AHEAD=0 ;; esac
  [ "$AHEAD" -gt 0 ] || exit 0
  set -- push
else
  # no upstream: first push needs an origin remote and at least one local commit
  git remote get-url origin >/dev/null 2>&1 || exit 0
  git rev-parse --verify -q HEAD >/dev/null 2>&1 || exit 0
  set -- push -u origin "$BRANCH"
fi

# --- pre-push local-CI gate: never push a red tree ---
# If the repo ships scripts/ci_local.sh (the single source of the CI checks), run
# it and stand down on failure, so a red commit never reaches origin and the PR
# never shows a red required check. Absent script -> no gate (other projects use
# their own verify command). ponytail: this pays CI's lint+test cost locally at
# turn end — that is the point; upgrade path is a per-project verify_cmd key.
if [ -x scripts/ci_local.sh ] && ! bash scripts/ci_local.sh >/dev/null 2>&1; then
  { printf 'branch=%s\ncmd=(skipped: ci_local.sh red)\nexit=1\nupdated_epoch=%s\n' \
      "$BRANCH" "$(date +%s 2>/dev/null || echo 0)"; } > "$LOOP_DIR/.last-push" 2>/dev/null || true
  exit 0
fi

# --- test seam: print the command instead of running it ---
if [ "${LOOP_AUTOPUSH_DRYRUN:-}" = "1" ]; then
  printf 'WOULD: git %s\n' "$*"
  exit 0
fi

# --- push (best-effort; failure is logged, never blocks the turn) ---
ERR="$(git "$@" 2>&1)"; RC=$?
{
  printf 'branch=%s\n' "$BRANCH"
  printf 'cmd=git %s\n' "$*"
  printf 'exit=%s\n' "$RC"
  printf 'updated_epoch=%s\n' "$(date +%s 2>/dev/null || echo 0)"
  [ "$RC" -eq 0 ] || printf 'error=%s\n' "$(printf '%s' "$ERR" | tr '\n' ' ' | cut -c1-300)"
} > "$LOOP_DIR/.last-push" 2>/dev/null || true

exit 0
