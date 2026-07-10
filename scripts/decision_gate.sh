#!/usr/bin/env bash
# loopy decision gate (PreToolUse hook, matcher: Bash).
#
# Enforces the loop-engineering decision doctrine: an action that is IRREVERSIBLE
# or HIGH-IMPACT (T2) needs a human gate; reversible/local work (T0/T1) never does.
# This hook mechanically blocks the T2 class so the doctrine cannot be forgotten.
#
# Scope: acts ONLY inside a loop project (cwd has `.claude/loop/`). Every other
# session, and any parse doubt, exits 0 (fail-open) — general Chrome/CLI use of git
# push etc. outside a loop is never touched.
#
# T2 default set (high-signal, low false-positive):
#   - package publish (npm/pnpm/yarn/bun publish)
#   - release/submit  (gh release create, eas submit)
#   - PR merge        (gh pr merge -> merge into a protected branch)
#   - git push to a protected branch (protected_branches, default "main master")
#   - git force-push and git tag push (rewrite/publish remote history)
#   - all git push when gate_push:true (direct-to-main repos)
#   - catastrophic delete (rm -rf of / ~ $HOME)
#   - any project-specific `extra_gates:` regex from loop.config.md
# Reversible/local commands (edits, tests, local commits, WORK-branch push) pass.
#
# Bypass: a valid one-shot marker `.claude/loop/.gate-approved` (written by the main
# agent only AFTER explicit human approval) authorizes the matching action class for
# the current session within a TTL. The agent removes it right after the approved
# command. gitignored by the existing `.claude/loop/.*` rule.
#
# Deny uses the official hooks schema (permissionDecision="deny") and exits 0 —
# deny JSON is only parsed on exit 0.

set -u

INPUT="$(cat 2>/dev/null || true)"

# Hooks run in the project cwd; prefer the cwd field when present (mirrors stop_gate).
HOOK_CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" 2>/dev/null || true
fi

LOOP_DIR=".claude/loop"

# --- scope: loop projects only ---
[ -d "$LOOP_DIR" ] || exit 0

if [ "${LOOP_GUARD_DEBUG:-}" = "1" ]; then
  printf '%s decision_gate input=%s\n' "$(date +%s)" "$INPUT" >> "$LOOP_DIR/.hook-debug.log" 2>/dev/null || true
fi

# --- extract the Bash command (same three-tier extraction as verifier_guard) ---
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    pass' 2>/dev/null || true)"
else
  CMD="$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -n1)"
fi
[ -n "$CMD" ] || exit 0

CUR_SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

# --- config (the only stack-dependent knobs) ---
CONFIG="$LOOP_DIR/loop.config.md"
PROTECTED="main master"
GATE_PUSH="false"
EXTRA_GATES=""
if [ -f "$CONFIG" ]; then
  p="$(sed -n 's/^protected_branches:[[:space:]]*//p' "$CONFIG" | head -n1)"
  case "$p" in ''|TODO*|'<'*) : ;; *) PROTECTED="$p" ;; esac
  g="$(sed -n 's/^gate_push:[[:space:]]*//p' "$CONFIG" | head -n1)"
  case "$g" in true) GATE_PUSH="true" ;; esac
  EXTRA_GATES="$(sed -n 's/^extra_gates:[[:space:]]*//p' "$CONFIG" | head -n1)"
  case "$EXTRA_GATES" in TODO*|'<'*) EXTRA_GATES="" ;; esac
fi
PROT_RE="$(printf '%s' "$PROTECTED" | tr -s ' ' '|' | sed 's/^|//;s/|$//')"
[ -n "$PROT_RE" ] || PROT_RE="main|master"

# --- one-shot human-approval marker ---
# approved <class>: true if .gate-approved authorizes this class (or "any") for this
# session within the TTL. Fail-closed on any parse doubt (return 1 -> still gated).
approved() {
  mk="$LOOP_DIR/.gate-approved"
  [ -f "$mk" ] || return 1
  a="$(sed -n 's/^action=//p' "$mk" | head -n1)"
  s="$(sed -n 's/^session_id=//p' "$mk" | head -n1)"
  t="$(sed -n 's/^ts=//p' "$mk" | head -n1)"
  case "$a" in "$1"|any) : ;; *) return 1 ;; esac
  # session must match when both sides are known
  if [ -n "$CUR_SID" ] && [ "$CUR_SID" != "unknown" ] && [ -n "$s" ] && [ "$s" != "$CUR_SID" ]; then
    return 1
  fi
  # freshness (15 min); missing/garbage ts -> treat as expired
  case "$t" in ''|*[!0-9]*) return 1 ;; esac
  now="$(date +%s 2>/dev/null || echo 0)"
  [ "$now" -gt 0 ] || return 0   # no clock -> do not expire on that basis
  [ $((now - t)) -le 900 ] || return 1
  return 0
}

deny() {
  # $1 = fixed tag, $2 = action class — both chosen below, safe to interpolate.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"loopy decision_gate: T2 (irreversible / high-impact) action blocked (%s). This is a human gate — do NOT work around it. Stop, summarize in .claude/loop/review.md, and get explicit human approval. Once approved, write .claude/loop/.gate-approved (action=%s, session_id, ts), retry, then remove the marker."}}\n' "$1" "$2"
  exit 0
}

# gate <class> <tag>: block unless the human approved this class.
gate() { approved "$1" || deny "$2" "$1"; }

# segment start = beginning, or after ; & | $( `
SEG='(^|[;&|]|\$\(|`)[[:space:]]*(sudo[[:space:]]+)?'

# 1. package publish
if printf '%s' "$CMD" | grep -Eq "${SEG}(npm|pnpm|yarn|bun)[[:space:]]+publish([[:space:]]|\$)"; then
  gate publish "package publish"
fi

# 2. release / store submit
if printf '%s' "$CMD" | grep -Eq "${SEG}(npx[[:space:]]+)?eas[[:space:]]+submit([[:space:]]|\$)"; then
  gate release "eas submit"
fi
if printf '%s' "$CMD" | grep -Eq "${SEG}gh[[:space:]]+release[[:space:]]+create([[:space:]]|\$)"; then
  gate release "gh release create"
fi

# 3. PR merge into a protected branch
if printf '%s' "$CMD" | grep -Eq "${SEG}gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|\$)"; then
  gate merge "gh pr merge"
fi

# 4. git push family
if printf '%s' "$CMD" | grep -Eq "${SEG}git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*push([[:space:]]|\$)"; then
  # gate_push:true -> every push is a gate
  if [ "$GATE_PUSH" = "true" ]; then
    gate push "git push (gate_push=true)"
  fi
  # force-push -> rewrites remote history (high-impact). Match -f/--force as a
  # whole arg token in ANY position — `git[[:space:]]+push[[:space:]]` consumes the
  # only space before the first arg, so a leading `[[:space:]]-f` misses `push -f`.
  if printf '%s' "$CMD" | grep -Eq "git[[:space:]]+push[[:space:]]+([^[:space:]]+[[:space:]]+)*(--force([[:space:]=]|\$)|--force-with-lease|-f([[:space:]]|\$))"; then
    gate push "git force-push"
  fi
  # force-refspec form: `git push origin +main` / `+refs/heads/x` force-pushes a
  # ref with no -f/--force flag. A `+`-prefixed refspec token (space, `+`, then a
  # non-flag char) is a force-push of ANY branch -> same T2 as --force above.
  if printf '%s' "$CMD" | grep -Eq "git[[:space:]]+push[[:space:]].*[[:space:]][+][^[:space:]-]"; then
    gate push "git force-push (+refspec)"
  fi
  # tag push -> publishing a release ref
  if printf '%s' "$CMD" | grep -Eq "git[[:space:]]+push[[:space:]].*(--tags([[:space:]]|\$)|refs/tags/)"; then
    gate release "git tag push"
  fi
  # push targeting a protected branch (space- or colon-delimited branch token)
  if printf '%s' "$CMD" | grep -Eq "git[[:space:]]+push[[:space:]].*[[:space:]:](${PROT_RE})([[:space:]]|\$)"; then
    gate push "git push to protected branch"
  fi
fi

# 5. catastrophic delete: a WHOLE root or WHOLE home. A home SUBDIR
# (rm -rf ~/.cache) is reversible T1 and must pass — see .claude/loop/review.md.
#   /         : root — trailing space, '/', or end          (rm -rf /, //)
#   ~ /$HOME  : whole home only — optional single trailing '/' then space/end
#               (rm -rf ~, ~/, $HOME) but NOT ~/<subdir>
CATA_TGT='(/([[:space:]]|/|$)|(~|[$]HOME|[$][{]HOME[}])/?([[:space:]]|$))'
if printf '%s' "$CMD" | grep -Eq "${SEG}rm[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*[[:space:]]+${CATA_TGT}"; then
  gate destructive "catastrophic rm -rf"
fi
if printf '%s' "$CMD" | grep -Eq "${SEG}rm[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+${CATA_TGT}"; then
  gate destructive "catastrophic rm -fr"
fi

# 6. project-specific extra gates (opt-in regex; e.g. external endpoints, cost)
if [ -n "$EXTRA_GATES" ] && printf '%s' "$CMD" | grep -Eq "$EXTRA_GATES" 2>/dev/null; then
  gate custom "extra_gates match"
fi

exit 0
