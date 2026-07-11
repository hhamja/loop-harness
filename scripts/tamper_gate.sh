#!/usr/bin/env bash
# loopy tamper gate (PreToolUse hook, matcher: Edit|Write|NotebookEdit).
#
# The decision_gate backstop only sees Bash. But the files that decide whether a
# loop cycle passes — the tests and CI the verifier re-runs, the gate scripts and
# hooks themselves, the rubric it grades, and the .gate-approved marker — are
# edited through the Edit/Write/NotebookEdit tools, which no gate saw. An honest
# agent that "fixes a failing test" by editing the test, or a maker editing the
# very gate scripts it is graded by, silently defeats maker≠checker. Unlike the
# command-form / interpreter bypasses (accepted-by-design, `0faabb4`), this is a
# path an honest-but-forgetful agent trips, so it is IN scope for the backstop:
# a write to those paths is T2, blocked unless a human approved it via the same
# .gate-approved marker contract as decision_gate (class "tamper" or "any").
#
# Scope: acts in EVERY project (loop-independent, like decision_gate). Paths are
# matched relative to the project root (the hook cwd). Any parse doubt exits 0
# (fail-open) — a weaker parse only weakens detection, never blocks wrongly.
#
# Deny uses the official hooks schema (permissionDecision="deny") and exits 0 —
# deny JSON is only parsed on exit 0.

set -u

# shellcheck source=scripts/hook_lib.sh
. "$(cd "$(dirname "$0")" && pwd)/hook_lib.sh"
hook_init
hook_debug tamper_gate

CUR_SID="$(json_str session_id)"

# edited path: Edit/Write carry file_path, NotebookEdit carries notebook_path
P="$(tool_str file_path)"; [ -n "$P" ] || P="$(tool_str notebook_path)"
[ -n "$P" ] || exit 0

# normalize to a repo-relative path. An absolute path outside the project root is
# not ours; inside it, strip the cwd prefix so the case-match sees a rel path.
case "$P" in
  "$PWD"/*) REL="${P#"$PWD"/}" ;;
  /*)       exit 0 ;;
  *)        REL="$P" ;;
esac
[ -n "$REL" ] || exit 0

# protected diff paths — the verifier's inputs and the gates themselves.
case "$REL" in
  tests/*|.github/workflows/*|scripts/*|hooks/*|.claude/loop/rubric.md|.claude/loop/.gate-approved)
    gate_approved tamper && exit 0
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"loopy tamper_gate: editing a verifier-input / gate path (%s) is T2 — the maker must not modify the tests, CI, gate scripts, hooks, rubric, or approval marker it is graded by. Get explicit human approval, then write .claude/loop/.gate-approved (action=tamper, session_id, ts), retry, and remove the marker."}}\n' "$REL"
    exit 0
    ;;
esac
exit 0
