#!/usr/bin/env bash
# loopy memory/state hygiene gate (Stop hook).
#
# The memory subsystem's own "done is machine-checked" enforcement. state.md and
# memory.md hygiene are otherwise only prompt guidance (memory-protocol.md,
# apply-report.md); this hook makes the load-bearing rules machine-checked so the
# agent cannot silently skip them — the doctrine says no component grades its own
# work, and until now the memory subsystem graded itself.
#
# Fail-open on every doubt. BLOCKS only on contract/protocol violations:
#   - state.md missing a deterministic field drive_next.sh parses
#     (loop_active / human_gate) — absence silently degrades the driver to idle.
#   - a memory.md Raw-log entry (### ...) or Distilled rule (- ...) missing its
#     mandatory [plugin]/[project] tag (memory-protocol.md: untagged = violation).
# Soft size caps (state.md >100 lines, Raw log >200 lines) are WARN-only, printed
# to stderr — a nudge, never a block.
#
# The block reason is built from static text + integer line counts only (never
# file content), so it needs no JSON escaping.
# Block JSON is only parsed on exit 0 — never combine it with exit 2.

set -u

INPUT="$(cat 2>/dev/null || true)"

# Hooks run in the project cwd; prefer the cwd field from the input if present.
HOOK_CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" 2>/dev/null || true
fi

LOOP_DIR=".claude/loop"

if [ "${LOOP_GUARD_DEBUG:-}" = "1" ] && [ -d "$LOOP_DIR" ]; then
  printf '%s check_memory input=%s\n' "$(date +%s)" "$INPUT" >> "$LOOP_DIR/.hook-debug.log" 2>/dev/null || true
fi

# --- not a loop project ---
[ -d "$LOOP_DIR" ] || exit 0

# --- already re-prompted once: never block again (avoid an infinite block loop) ---
if printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

STATE="$LOOP_DIR/state.md"
MEMORY="$LOOP_DIR/memory.md"

violations=""
add_v() { if [ -z "$violations" ]; then violations="$1"; else violations="$violations; $1"; fi; }

# --- state.md: required deterministic fields (drive_next.sh contract) ---
if [ -f "$STATE" ]; then
  grep -Eq '^loop_active:' "$STATE" || add_v "state.md missing 'loop_active:' field (drive_next.sh reads it)"
  grep -Eq '^human_gate:' "$STATE" || add_v "state.md missing 'human_gate:' field (drive_next.sh reads it)"
  lines="$(wc -l < "$STATE" | tr -d '[:space:]')"
  case "$lines" in ''|*[!0-9]*) lines=0 ;; esac
  [ "$lines" -gt 100 ] && printf 'check_memory: warn: state.md is %s lines (cap 100 — rewrite as a summary)\n' "$lines" >&2
fi

# --- memory.md: mandatory [plugin]/[project] tags on entries and rules ---
if [ -f "$MEMORY" ]; then
  # Distilled rules: "- " bullets between "## Distilled rules" and the next "## " header.
  # Placeholders like "(none yet)" are not "- " bullets, so they are not flagged.
  untagged_rule="$(awk '
    /^## Distilled rules/ {sec=1; next}
    /^## / {sec=0}
    sec && /^- / && !/\[plugin\]/ && !/\[project\]/ {print NR; exit}
  ' "$MEMORY")"
  [ -n "$untagged_rule" ] && add_v "memory.md Distilled rule on line $untagged_rule missing [plugin]/[project] tag"

  # Raw log: "### " entry headings after "## Raw log".
  untagged_entry="$(awk '
    /^## Raw log/ {sec=1; next}
    /^## / {sec=0}
    sec && /^### / && !/\[plugin\]/ && !/\[project\]/ {print NR; exit}
  ' "$MEMORY")"
  [ -n "$untagged_entry" ] && add_v "memory.md Raw log entry on line $untagged_entry missing [plugin]/[project] tag"

  raw_lines="$(awk '/^## Raw log/{s=1;next} /^## /{s=0} s{c++} END{print c+0}' "$MEMORY")"
  [ "$raw_lines" -gt 200 ] && printf 'check_memory: warn: memory.md Raw log is %s lines (compress at 200)\n' "$raw_lines" >&2
fi

# --- verdict: block on contract/protocol violations (exit 0 so the JSON is parsed) ---
if [ -n "$violations" ]; then
  printf '{"decision":"block","reason":"Memory/state hygiene (fix before finishing): %s. See loop-engineering references/memory-protocol.md."}\n' "$violations"
fi

exit 0
