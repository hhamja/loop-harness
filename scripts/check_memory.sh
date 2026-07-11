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
#   - state.md missing a deterministic contract field (loop_active / human_gate)
#     — skills and the SessionStart digest parse these to resume or gate a loop;
#     absence silently degrades resume to "no loop here".
#   - a memory.md Raw-log entry (### ...) or Distilled rule (- ...) missing its
#     mandatory [plugin]/[project] tag (memory-protocol.md: untagged = violation).
# Soft size caps (state.md >100 lines, Raw log >200 lines) are WARN-only, printed
# to stderr — a nudge, never a block.
#
# The block reason is built from static text + integer line counts only (never
# file content), so it needs no JSON escaping.
# Block JSON is only parsed on exit 0 — never combine it with exit 2.

set -u

# shellcheck source=scripts/hook_lib.sh
. "$(cd "$(dirname "$0")" && pwd)/hook_lib.sh"
hook_init
hook_debug check_memory

# --- not a loop project ---
[ -d "$LOOP_DIR" ] || exit 0

# --- already re-prompted once: never block again (avoid an infinite block loop) ---
stop_hook_active && exit 0

STATE="$LOOP_DIR/state.md"
MEMORY="$LOOP_DIR/memory.md"

violations=""
add_v() { if [ -z "$violations" ]; then violations="$1"; else violations="$violations; $1"; fi; }

# --- state.md: required deterministic fields (loop resume contract) ---
if [ -f "$STATE" ]; then
  grep -Eq '^loop_active:' "$STATE" || add_v "state.md missing 'loop_active:' field (loop resume contract)"
  grep -Eq '^human_gate:' "$STATE" || add_v "state.md missing 'human_gate:' field (loop resume contract)"
  lines="$(wc -l < "$STATE" | tr -d '[:space:]')"
  case "$lines" in ''|*[!0-9]*) lines=0 ;; esac
  [ "$lines" -gt 100 ] && printf 'check_memory: warn: state.md is %s lines (cap 100 — rewrite as a summary)\n' "$lines" >&2
fi

# --- memory.md: mandatory [plugin]/[project] tags on entries and rules ---
if [ -f "$MEMORY" ]; then
  # untagged <section-header-re> <line-re> — line number of the first untagged match
  # under that "## " section. Placeholders like "(none yet)" match neither line-re.
  untagged() {
    awk -v h="^## $1" -v p="$2" '$0~h{s=1;next} /^## /{s=0} s && $0~p && !/\[(plugin|project)\]/{print NR; exit}' "$MEMORY"
  }
  n="$(untagged 'Distilled rules' '^- ')"
  [ -n "$n" ] && add_v "memory.md Distilled rule on line $n missing [plugin]/[project] tag"
  n="$(untagged 'Raw log' '^### ')"
  [ -n "$n" ] && add_v "memory.md Raw log entry on line $n missing [plugin]/[project] tag"

  raw_lines="$(awk '/^## Raw log/{s=1;next} /^## /{s=0} s{c++} END{print c+0}' "$MEMORY")"
  [ "$raw_lines" -gt 200 ] && printf 'check_memory: warn: memory.md Raw log is %s lines (compress at 200)\n' "$raw_lines" >&2
fi

# --- verdict: block on contract/protocol violations (exit 0 so the JSON is parsed) ---
if [ -n "$violations" ]; then
  printf '{"decision":"block","reason":"Memory/state hygiene (fix before finishing): %s. See loop-engineering references/memory-protocol.md."}\n' "$violations"
fi

exit 0
