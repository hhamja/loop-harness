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

# shellcheck source=scripts/hook_lib.sh
. "$(cd "$(dirname "$0")" && pwd)/hook_lib.sh"
hook_init
hook_debug verifier_guard

# --- scope: only the read-only checker agents are inspected ---
if command -v jq >/dev/null 2>&1; then
  AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)"
else
  AGENT_TYPE="$(json_str agent_type)"
fi

case "$AGENT_TYPE" in
  *verifier*|*auditor*|*architect*|*critic*) : ;;   # inspect below (all read-only checkers)
  *) exit 0 ;;                             # fail-open: missing field or other agent -> never block
esac

# --- extract the Bash command (read-only checkers only from here on) ---
CMD="$(bash_cmd)"
[ -n "$CMD" ] || exit 0

deny() {
  # $1 is a fixed tag chosen below — safe to interpolate into JSON
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"loopy verifier_guard: this read-only checker (verifier/auditor/architect/critic) must not modify files — blocked write-capable Bash (%s). Report a FAIL/finding with evidence instead of modifying anything."}}\n' "$1"
  exit 0
}

# segment start = beginning, or after ; & | $( `
SEG='(^|[;&|]|\$\(|`)[[:space:]]*(sudo[[:space:]]+)?'

# Drop quoted spans ONCE, up front: a command name OR a `>` inside quotes is DATA
# (a grep pattern like 'a|rm -rf|b', an awk '>' compare), not a command or a
# redirect — read-only checkers grep such source constantly, and matching the
# raw command false-positives on their own patterns. Every match below runs
# against this quote-stripped form.
NQ="$(printf '%s' "$CMD" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"

if printf '%s' "$NQ" | grep -Eq "${SEG}(rm|mv|cp|ln|dd|truncate|tee|chmod|chown|rmdir|unlink)([[:space:]]|\$)"; then
  deny "file-mutating command"
fi

if printf '%s' "$NQ" | grep -Eq "${SEG}sed[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*i"; then
  deny "sed -i"
fi

if printf '%s' "$NQ" | grep -Eq "${SEG}git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(commit|push|checkout|reset|clean|restore|rebase|merge|apply|stash|rm|mv)([[:space:]]|\$)"; then
  deny "git write command"
fi

if printf '%s' "$NQ" | grep -Eq "${SEG}(npm|pnpm|yarn)[[:space:]]+publish"; then
  deny "package publish"
fi

# Redirects: quoted spans already dropped above. Strip the allowed idioms
# (2>&1, >&2, [n]>/dev/null, &>/dev/null); any remaining `>` is a redirect to a
# file path -> deny.
STRIPPED="$(printf '%s' "$NQ" | sed -E "s/[0-9]?>&[0-9]//g; s/&>[[:space:]]*\/dev\/null//g; s/[0-9]?>>?[[:space:]]*\/dev\/null//g")"
if printf '%s' "$STRIPPED" | grep -q '>'; then
  deny "file redirect"
fi

exit 0
