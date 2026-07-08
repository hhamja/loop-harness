#!/usr/bin/env bash
# loop-harness test harness — pure bash, zero dependencies.
# Runs the hook scripts against fixed inputs and asserts exit code + stdout,
# so CI needs nothing beyond bash itself.
#   bash tests/run.sh   -> exit 0 = all pass, exit 1 = at least one failure
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"

pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

assert_exit()     { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "exit want=$1 got=$2"; fi; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "want substring: $2 | got: $1" ;; esac; }
assert_empty()    { if [ -z "$1" ]; then ok "$2"; else bad "$2" "want empty, got: $1"; fi; }

# ── verifier_guard.sh: stdin JSON -> stdout (deny JSON or empty), always exit 0 ──
guard() { printf '%s' "$1" | bash "$SCRIPTS/verifier_guard.sh"; }

test_verifier_guard() {
  printf '\nverifier_guard.sh\n'
  local out rc

  out="$(guard '{"tool_input":{"command":"rm -rf /"}}')"; rc=$?
  assert_exit 0 "$rc" "no agent_type: exit 0"
  assert_empty "$out" "no agent_type: fail-open (no deny)"

  out="$(guard '{"agent_type":"main","tool_input":{"command":"rm x"}}')"
  assert_empty "$out" "non-verifier agent: no deny"

  out="$(guard '{"agent_type":"loop-harness:verifier","tool_input":{"command":"rm -rf build"}}')"; rc=$?
  assert_exit 0 "$rc" "verifier rm: exit 0 (deny parsed only on exit 0)"
  assert_contains "$out" '"permissionDecision":"deny"' "verifier rm: deny"

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"git commit -m x"}}')"
  assert_contains "$out" '"deny"' "verifier git commit: deny"

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"sed -i s/a/b/ f"}}')"
  assert_contains "$out" '"deny"' "verifier sed -i: deny"

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"npm publish"}}')"
  assert_contains "$out" '"deny"' "verifier npm publish: deny"

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"echo hi > out.txt"}}')"
  assert_contains "$out" '"deny"' "verifier redirect to file: deny"

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"pnpm test 2>&1"}}')"
  assert_empty "$out" "verifier test 2>&1: allow (idiom)"

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"grep -q foo bar >/dev/null"}}')"
  assert_empty "$out" "verifier >/dev/null: allow (idiom)"

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"cat a | grep b"}}')"
  assert_empty "$out" "verifier read pipeline: allow"

  out="$(guard '{"agent_type":"verifier","tool_input":{}}')"
  assert_empty "$out" "verifier no command: allow"
}

# ── stop_gate.sh: stdin JSON + fixture cwd -> stdout (block JSON or empty), exit 0 ──
# Each case builds a throwaway project dir; the script cd's into input.cwd.
stop() { printf '%s' "$1" | bash "$SCRIPTS/stop_gate.sh"; }

test_stop_gate() {
  printf '\nstop_gate.sh\n'
  local tmp out

  # verdict 1: not a loop project
  tmp="$(mktemp -d)"
  out="$(stop "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "no loop dir: no block"
  rm -rf "$tmp"

  # verdict 2: stop_hook_active true (would block on verdict 4 if reached)
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'session_id=S1\n' > "$tmp/.claude/loop/.run-marker"
  printf 'x\n' > "$tmp/.claude/loop/state.md"; touch -t 202001010000 "$tmp/.claude/loop/state.md"
  out="$(stop "$(printf '{"cwd":"%s","session_id":"S1","stop_hook_active":true}' "$tmp")")"
  assert_empty "$out" "stop_hook_active: no block"
  rm -rf "$tmp"

  # verdict 3a: no marker
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  out="$(stop "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "no marker: no block"
  rm -rf "$tmp"

  # verdict 3b: marker from a different session
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'session_id=OTHER\n' > "$tmp/.claude/loop/.run-marker"
  printf 'x\n' > "$tmp/.claude/loop/state.md"; touch -t 202001010000 "$tmp/.claude/loop/state.md"
  out="$(stop "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "stale marker session: no block"
  rm -rf "$tmp"

  # verdict 4 BLOCK: same session, state.md older than marker (state not updated this run)
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'x\n' > "$tmp/.claude/loop/state.md"; touch -t 202001010000 "$tmp/.claude/loop/state.md"
  printf 'session_id=S1\n' > "$tmp/.claude/loop/.run-marker"
  out="$(stop "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_contains "$out" '"decision":"block"' "stale state.md: BLOCK"
  rm -rf "$tmp"

  # verdict 4 PASS: state.md newer than marker
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'session_id=S1\n' > "$tmp/.claude/loop/.run-marker"
  printf 'x\n' > "$tmp/.claude/loop/state.md"; touch -t 203001010000 "$tmp/.claude/loop/state.md"
  out="$(stop "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "fresh state.md: no block"
  rm -rf "$tmp"

  # verdict 4 fail-open: no state.md to judge against
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'session_id=S1\n' > "$tmp/.claude/loop/.run-marker"
  out="$(stop "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "no state.md: no block"
  rm -rf "$tmp"
}

# ── check_budget.sh: smoke — the real repo must be within budget ──
test_budget() {
  printf '\ncheck_budget.sh\n'
  local out rc
  out="$(bash "$SCRIPTS/check_budget.sh")"; rc=$?
  assert_exit 0 "$rc" "repo budget: exit 0"
  assert_contains "$out" "BUDGET OK" "repo budget: BUDGET OK"
}

test_verifier_guard
test_stop_gate
test_budget

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
