# shellcheck shell=bash
# loopy hook lib — the single home of the preamble and parsers the hook/gate
# scripts used to copy-paste: stdin/cwd handling, JSON field extraction, and
# the loop.config.md accessors the gates must agree on (a protected_branches
# parse that drifts between decision_gate and auto_push/auto_pr/branch_guard
# is a gate hole, not a style issue). Source only — no side effects:
#   . "$(cd "$(dirname "$0")" && pwd)/hook_lib.sh"
# Behavior contract: identical to the blocks it replaced; tests/run.sh
# exercises every caller against fixed inputs.

LOOP_DIR=".claude/loop"

# json_str <key> — first top-level string field from INPUT (crude sed; fine
# for the machine-written cwd/session_id/transcript_path fields).
json_str() {
  printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1
}

# hook_init — read hook stdin into INPUT, then cd to its cwd field (hooks run
# in the project cwd; prefer the field when present).
hook_init() {
  INPUT="$(cat 2>/dev/null || true)"
  local d; d="$(json_str cwd)"
  if [ -n "$d" ] && [ -d "$d" ]; then
    cd "$d" 2>/dev/null || true
  fi
}

# stop_hook_active — true when this Stop event is already a re-prompt
# (callers exit 0 to avoid an infinite block loop / acting mid-block).
stop_hook_active() {
  printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'
}

# hook_debug <name> — opt-in observability (smoke checks read this log to tell
# "field absent" apart from "value mismatch"). Default state writes nothing.
hook_debug() {
  [ "${LOOP_GUARD_DEBUG:-}" = "1" ] || return 0
  [ -d "$LOOP_DIR" ] || return 0
  printf '%s %s input=%s\n' "$(date +%s)" "$1" "$INPUT" >> "$LOOP_DIR/.hook-debug.log" 2>/dev/null || true
}

# bash_cmd — the Bash tool command from INPUT. Three tiers: jq (exact),
# python3 (exact), sed (crude last resort; may truncate at escaped quotes —
# callers fail open, so a weaker parse only weakens detection, never blocks
# wrongly).
bash_cmd() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    pass' 2>/dev/null || true
  else
    printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -n1
  fi
}

# tool_str <key> — first string field from INPUT's tool_input object. Same
# three tiers and fail-open contract as bash_cmd (jq exact, python3 exact,
# sed crude last resort); callers treat empty as "not present".
tool_str() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r ".tool_input.\"$1\" // empty" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    v = json.load(sys.stdin).get("tool_input", {}).get(sys.argv[1], "")
    print(v if isinstance(v, str) else "")
except Exception:
    pass' "$1" 2>/dev/null || true
  else
    printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1
  fi
}

# sid_safe <sid> — session id reduced to filename-safe chars (it names the
# per-session .touched-<sid> manifest); empty in -> "unknown" out. When the
# filter dropped characters, two DISTINCT sids could collapse to one name
# ("a/b" and "ab") — that collision would merge two sessions' manifests and
# defeat the peer detection, so a checksum of the raw sid disambiguates.
sid_safe() {
  local raw="${1:-}" s
  s="$(printf '%s' "$raw" | tr -cd 'A-Za-z0-9._-')"
  if [ -n "$raw" ] && [ "$s" != "$raw" ]; then
    s="${s}-$(printf '%s' "$raw" | cksum | cut -d' ' -f1)"
  fi
  printf '%s' "${s:-unknown}"
}

# field <file> <key> — value of `key=...` (first match), empty if absent.
# The marker/lock/log files (.gate-approved, .run-marker, .last-usage) all use
# this key=value format; loop_lock.sh keeps its own copy (deliberately standalone).
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n1; }

# config_field <key> — first `key: value` line from loop.config.md, raw
# (empty when the file or key is absent). Callers own default/TODO handling.
config_field() {
  sed -n "s/^$1:[[:space:]]*//p" "$LOOP_DIR/loop.config.md" 2>/dev/null | head -n1
}

# cfg_flag <key> <default> — boolean key; only the literal opposite of the
# default flips it (any other value, TODO, or absence keeps the default).
cfg_flag() {
  case "$2:$(config_field "$1")" in
    true:false) printf 'false' ;;
    false:true) printf 'true' ;;
    *)          printf '%s' "$2" ;;
  esac
}

# protected_re — validated protected_branches (default "main master") as an
# ERE alternation, e.g. "main|master".
protected_re() {
  local p re
  p="$(config_field protected_branches)"
  case "$p" in ''|TODO*|'<'*) p="main master" ;; esac
  re="$(printf '%s' "$p" | tr -s ' ' '|' | sed 's/^|//;s/|$//')"
  [ -n "$re" ] || re="main|master"
  printf '%s' "$re"
}

# gate_approved <class> — true iff .claude/loop/.gate-approved authorizes <class>
# (or "any") for THIS session within the 15-min TTL. Fail-closed on ANY parse
# doubt (return 1 -> still gated). Shared by decision_gate AND tamper_gate so the
# one human-approval contract cannot drift between them. Reads CUR_SID from the
# caller's scope (the current session id).
gate_approved() {
  local mk="$LOOP_DIR/.gate-approved" a s t now
  [ -f "$mk" ] || return 1
  a="$(field "$mk" action)"; s="$(field "$mk" session_id)"; t="$(field "$mk" ts)"
  case "$a" in "$1"|any) : ;; *) return 1 ;; esac
  # a marker MUST be session-bound: an empty session_id fails closed so a forged
  # marker cannot authorize an arbitrary session (was: empty s skipped the check).
  [ -n "$s" ] || return 1
  if [ -n "${CUR_SID:-}" ] && [ "$CUR_SID" != "unknown" ] && [ "$s" != "$CUR_SID" ]; then
    return 1
  fi
  # freshness (15 min); missing/garbage ts -> expired. A zeroed/broken clock makes
  # now-ts hugely negative and would keep an expired marker "fresh" -> fail closed.
  case "$t" in ''|*[!0-9]*) return 1 ;; esac
  now="$(date +%s 2>/dev/null || echo 0)"
  [ "$now" -gt 0 ] || return 1
  [ $((now - t)) -le 900 ] || return 1
  return 0
}
