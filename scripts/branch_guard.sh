#!/usr/bin/env bash
# loopy branch guard — enforce "no standalone work on a protected branch".
#
# Run at loop-run preflight (references/preflight.md), NOT a Stop hook: it must
# run BEFORE the first cycle so work never lands on main. GitHub Flow — one work
# unit = one <type>/<slug> branch off the default branch; the merge stays the one
# human gate. This is the entry-side complement to decision_gate.sh (which BLOCKS
# pushing a protected branch) and auto_push.sh (which PUSHES a work branch).
#
#   bash scripts/branch_guard.sh
#
# Fail-open (exit 0) whenever there is nothing to do:
#   SKIP: not a loop project / not a git tree / detached HEAD / gate_push
#   OK:   already on work branch <b>       (respect where the human put us)
#   BRANCHED: <b> (from <base>)            (created or switched to the work branch)
# The ONE hard stop is exit 1:
#   NEED: ...                              (on a protected branch, but no usable
#                                           'branch:' key, or the checkout failed)
#
# Test seam: LOOP_BRANCHGUARD_DRYRUN=1 prints "WOULD: git checkout -b <b>" instead
# of touching git, so tests need no branch mutation.

set -u

LOOP_DIR=".claude/loop"

# --- fail-open guards ---
[ -d "$LOOP_DIR" ] || { echo "SKIP: not a loop project"; exit 0; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "SKIP: not a git work tree"; exit 0; }
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || { echo "SKIP: detached HEAD"; exit 0; }

# --- config (same parser as auto_push.sh) ---
CONFIG="$LOOP_DIR/loop.config.md"
GATE_PUSH="false"
PROTECTED="main master"
WORKBRANCH=""
if [ -f "$CONFIG" ]; then
  g="$(sed -n 's/^gate_push:[[:space:]]*//p' "$CONFIG" | head -n1)"
  case "$g" in true) GATE_PUSH="true" ;; esac
  p="$(sed -n 's/^protected_branches:[[:space:]]*//p' "$CONFIG" | head -n1)"
  case "$p" in ''|TODO*|'<'*) : ;; *) PROTECTED="$p" ;; esac
  WORKBRANCH="$(sed -n 's/^branch:[[:space:]]*//p' "$CONFIG" | head -n1)"
fi

# --- direct-to-main repos gate every push; this guard stands down there ---
[ "$GATE_PUSH" != "true" ] || { echo "SKIP: gate_push (direct-to-main)"; exit 0; }

# --- already on a work branch? respect it, do nothing ---
PROT_RE="$(printf '%s' "$PROTECTED" | tr -s ' ' '|' | sed 's/^|//;s/|$//')"
[ -n "$PROT_RE" ] || PROT_RE="main|master"
if ! printf '%s' "$BRANCH" | grep -Eq "^(${PROT_RE})$"; then
  echo "OK: already on work branch $BRANCH"
  exit 0
fi

# --- on a protected branch: must move to the configured work branch ---
case "$WORKBRANCH" in
  ''|TODO*|'<'*)
    echo "NEED: set 'branch: <type>/<slug>' in $CONFIG before running on $BRANCH"
    exit 1
    ;;
esac

# --- test seam ---
if [ "${LOOP_BRANCHGUARD_DRYRUN:-}" = "1" ]; then
  echo "WOULD: git checkout -b $WORKBRANCH (from $BRANCH)"
  exit 0
fi

# --- create or switch to the work branch (uncommitted changes carry over) ---
if git show-ref --verify --quiet "refs/heads/$WORKBRANCH"; then
  ERR="$(git checkout -q "$WORKBRANCH" 2>&1)"; RC=$?
else
  ERR="$(git checkout -q -b "$WORKBRANCH" 2>&1)"; RC=$?
fi
if [ "$RC" -eq 0 ]; then
  echo "BRANCHED: $WORKBRANCH (from $BRANCH)"
  exit 0
fi
echo "NEED: could not switch to '$WORKBRANCH' from $BRANCH: $(printf '%s' "$ERR" | tr '\n' ' ' | cut -c1-160)"
exit 1
