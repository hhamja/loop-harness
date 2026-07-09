#!/usr/bin/env bash
# loopy verifier guard (PreToolUse hook, matcher: Bash).
#
# Scope: acts ONLY when the hook input's agent_type contains "verifier", "auditor",
# "architect", or "critic" (partial match — survives namespace prefixes like "loopy:verifier").
# A missing agent_type field, a non-matching value, or any parse doubt -> allow (fail-open).
# The main agent and every other agent are NEVER blocked here.
#
# Invariant enforced: these read-only checkers must not modify source or loop state files.
# Incidental writes by test/build runners (cache, coverage) are out of scope.
#
# Deny response uses the official hooks schema (hookSpecificOutput.permissionDecision
# = "deny") and exits 0 — deny JSON is only parsed on exit 0.

set -u

INPUT="$(cat 2>/dev/null || true)"

# Debug observability: opt-in only (smoke checks depend on this log to tell
# "field absent" apart from "value mismatch"). Default state writes nothing.
if [ "${LOOP_GUARD_DEBUG:-}" = "1" ]; then
  HOOK_CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  DBG_DIR="${HOOK_CWD:-.}/.claude/loop"
  if [ -d "$DBG_DIR" ]; then
    printf '%s verifier_guard input=%s\n' "$(date +%s)" "$INPUT" >> "$DBG_DIR/.hook-debug.log" 2>/dev/null || true
  fi
fi

# --- scope: only the read-only checker agents are inspected ---
if command -v jq >/dev/null 2>&1; then
  AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)"
else
  AGENT_TYPE="$(printf '%s' "$INPUT" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi

case "$AGENT_TYPE" in
  *verifier*|*auditor*|*architect*|*critic*) : ;;   # inspect below (all read-only checkers)
  *) exit 0 ;;                             # fail-open: missing field or other agent -> never block
esac

# --- extract the Bash command (read-only checkers only from here on) ---
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    pass' 2>/dev/null || true)"
else
  # last-resort crude extraction; may truncate at escaped quotes, which only
  # weakens detection for the verifier (never affects other agents)
  CMD="$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -n1)"
fi
[ -n "$CMD" ] || exit 0

deny() {
  # $1 is a fixed tag chosen below — safe to interpolate into JSON
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"loopy verifier_guard: this read-only checker (verifier/auditor/architect) must not modify files — blocked write-capable Bash (%s). Report a FAIL/finding with evidence instead of modifying anything."}}\n' "$1"
  exit 0
}

# segment start = beginning, or after ; & | $( `
SEG='(^|[;&|]|\$\(|`)[[:space:]]*(sudo[[:space:]]+)?'

if printf '%s' "$CMD" | grep -Eq "${SEG}(rm|mv|cp|ln|dd|truncate|tee|chmod|chown|rmdir|unlink)([[:space:]]|\$)"; then
  deny "file-mutating command"
fi

if printf '%s' "$CMD" | grep -Eq "${SEG}sed[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*i"; then
  deny "sed -i"
fi

if printf '%s' "$CMD" | grep -Eq "${SEG}git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(commit|push|checkout|reset|clean|restore|rebase|merge|apply|stash|rm|mv)([[:space:]]|\$)"; then
  deny "git write command"
fi

if printf '%s' "$CMD" | grep -Eq "${SEG}(npm|pnpm|yarn)[[:space:]]+publish"; then
  deny "package publish"
fi

# Redirects: strip the allowed idioms first (2>&1, >&2, [n]>/dev/null, &>/dev/null),
# then any remaining > means a redirect to a file path -> deny.
STRIPPED="$(printf '%s' "$CMD" | sed -E 's/[0-9]?>&[0-9]//g; s/&>[[:space:]]*\/dev\/null//g; s/[0-9]?>>?[[:space:]]*\/dev\/null//g')"
if printf '%s' "$STRIPPED" | grep -q '>'; then
  deny "file redirect"
fi

exit 0
