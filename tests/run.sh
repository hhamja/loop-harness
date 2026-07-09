#!/usr/bin/env bash
# loopy test harness — pure bash, zero dependencies.
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

  out="$(guard '{"agent_type":"loopy:verifier","tool_input":{"command":"rm -rf build"}}')"; rc=$?
  assert_exit 0 "$rc" "verifier rm: exit 0 (deny parsed only on exit 0)"
  assert_contains "$out" '"permissionDecision":"deny"' "verifier rm: deny"

  out="$(guard '{"agent_type":"loopy:auditor","tool_input":{"command":"rm -rf x"}}')"
  assert_contains "$out" '"deny"' "auditor rm: deny (read-only checker)"

  out="$(guard '{"agent_type":"loopy:architect","tool_input":{"command":"echo x > diagnosis.md"}}')"
  assert_contains "$out" '"deny"' "architect redirect: deny (read-only checker)"

  out="$(guard '{"agent_type":"loop-architect","tool_input":{"command":"cat rubric.md"}}')"
  assert_empty "$out" "architect read: allow"

  out="$(guard '{"agent_type":"loopy:design-critic","tool_input":{"command":"rm -rf x"}}')"
  assert_contains "$out" '"deny"' "design-critic rm: deny (read-only checker)"

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

# ── decision_gate.sh: stdin JSON + fixture cwd -> stdout (deny JSON or empty), exit 0 ──
# Gates T2 (irreversible/high-impact) commands inside a loop project; reversible/local
# and non-loop commands pass. Each case builds a throwaway loop project.
dgate() { printf '{"cwd":"%s","session_id":"S1","tool_input":{"command":"%s"}}' "$1" "$2" | bash "$SCRIPTS/decision_gate.sh"; }

test_decision_gate() {
  printf '\ndecision_gate.sh\n'
  local tmp out rc

  # not a loop project -> never gate
  tmp="$(mktemp -d)"
  out="$(dgate "$tmp" "git push origin main")"; rc=$?
  assert_exit 0 "$rc" "no loop dir: exit 0"
  assert_empty "$out" "no loop dir: no gate"
  rm -rf "$tmp"

  # loop project, default config (protected: main master, gate_push: false)
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'protected_branches: main master\ngate_push: false\n' > "$tmp/.claude/loop/loop.config.md"

  out="$(dgate "$tmp" "git push origin feature/x")"; rc=$?
  assert_exit 0 "$rc" "work-branch push: exit 0"
  assert_empty "$out" "work-branch push: allow"

  out="$(dgate "$tmp" "git push origin main")"
  assert_contains "$out" '"deny"' "push to protected: deny"

  out="$(dgate "$tmp" "git push --force origin feature/x")"
  assert_contains "$out" '"deny"' "force-push: deny"

  out="$(dgate "$tmp" "git push --tags")"
  assert_contains "$out" '"deny"' "tag push: deny"

  out="$(dgate "$tmp" "npm publish")"
  assert_contains "$out" '"deny"' "npm publish: deny"

  out="$(dgate "$tmp" "gh pr merge 5 --squash")"
  assert_contains "$out" '"deny"' "gh pr merge: deny"

  out="$(dgate "$tmp" "eas submit --platform ios")"
  assert_contains "$out" '"deny"' "eas submit: deny"

  out="$(dgate "$tmp" "rm -rf /")"
  assert_contains "$out" '"deny"' "catastrophic rm: deny"

  out="$(dgate "$tmp" "git commit -m x")"
  assert_empty "$out" "local commit: allow"

  out="$(dgate "$tmp" "pnpm test 2>&1")"
  assert_empty "$out" "run tests: allow"

  out="$(dgate "$tmp" "rm -rf node_modules")"
  assert_empty "$out" "rm local dir: allow"

  out="$(dgate "$tmp" "git push origin mainline")"
  assert_empty "$out" "push to mainline (not protected): allow"

  # gate_push:true raises every push to T2
  printf 'protected_branches: main\ngate_push: true\n' > "$tmp/.claude/loop/loop.config.md"
  out="$(dgate "$tmp" "git push origin feature/x")"
  assert_contains "$out" '"deny"' "gate_push=true: work-branch push denied"
  printf 'protected_branches: main master\ngate_push: false\n' > "$tmp/.claude/loop/loop.config.md"

  # valid approval marker bypasses the matching class, one-shot semantics
  printf 'action=push\nsession_id=S1\nts=%s\n' "$(date +%s)" > "$tmp/.claude/loop/.gate-approved"
  out="$(dgate "$tmp" "git push origin main")"
  assert_empty "$out" "approved push: allow"
  out="$(dgate "$tmp" "npm publish")"
  assert_contains "$out" '"deny"' "approved push != publish: still deny"

  printf 'action=push\nsession_id=S1\nts=1\n' > "$tmp/.claude/loop/.gate-approved"
  out="$(dgate "$tmp" "git push origin main")"
  assert_contains "$out" '"deny"' "expired marker: deny"

  printf 'action=push\nsession_id=OTHER\nts=%s\n' "$(date +%s)" > "$tmp/.claude/loop/.gate-approved"
  out="$(dgate "$tmp" "git push origin main")"
  assert_contains "$out" '"deny"' "wrong-session marker: deny"

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

# ── gen_ci.sh: golden — detected stack facts -> pinned CI workflow ──
gen_ci() { bash "$SCRIPTS/gen_ci.sh" "$@"; }

test_gen_ci() {
  printf '\ngen_ci.sh\n'

  gen_ci --pm pnpm --test 'pnpm test' --lint 'pnpm lint' --build 'pnpm build' \
    | diff -u "$ROOT/tests/golden/node-pnpm-full.yml" - >/dev/null
  assert_exit 0 "$?" "golden: node-pnpm-full"

  gen_ci --pm npm --test 'npm test' \
    | diff -u "$ROOT/tests/golden/node-npm-todo.yml" - >/dev/null
  assert_exit 0 "$?" "golden: node-npm-todo (TODO steps commented out)"

  gen_ci --pm bun --test 'bun test' --build 'bun run build' \
    | diff -u "$ROOT/tests/golden/node-bun.yml" - >/dev/null
  assert_exit 0 "$?" "golden: node-bun"

  gen_ci --test x >/dev/null 2>&1
  assert_exit 2 "$?" "missing --pm: exit 2"

  gen_ci --pm cargo >/dev/null 2>&1
  assert_exit 2 "$?" "unsupported --pm: exit 2"
}

# ── drive_next.sh: state.md -> one verdict token, exit 0 ──
# Deterministic driver brain: human_gate wins over loop_active; unknown gate falls through.
dnext() { bash "$SCRIPTS/drive_next.sh" "$1"; }

test_drive_next() {
  printf '\ndrive_next.sh\n'
  local tmp out rc

  tmp="$(mktemp -d)"
  out="$(dnext "$tmp")"; rc=$?
  assert_exit 0 "$rc" "no state: exit 0"
  assert_contains "$out" "idle" "no state: idle"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'loop_active: true\nhuman_gate: none\niteration: 3\n' > "$tmp/.claude/loop/state.md"
  out="$(dnext "$tmp")"
  assert_contains "$out" "run" "active + no gate: run"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'loop_active: true\nhuman_gate: ready_for_merge\n' > "$tmp/.claude/loop/state.md"
  out="$(dnext "$tmp")"
  assert_contains "$out" "notify:ready_for_merge" "ready_for_merge: notify (gate beats loop_active)"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'loop_active: false\nhuman_gate: pending_t2\n' > "$tmp/.claude/loop/state.md"
  out="$(dnext "$tmp")"
  assert_contains "$out" "notify:pending_t2" "pending_t2: notify"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'human_gate: stalled\nloop_active: false\n' > "$tmp/.claude/loop/state.md"
  out="$(dnext "$tmp")"
  assert_contains "$out" "notify:stalled" "stalled: notify"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'loop_active: false\nhuman_gate: none\n' > "$tmp/.claude/loop/state.md"
  out="$(dnext "$tmp")"
  assert_contains "$out" "idle" "inactive + no gate: idle"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'loop_active: true\nhuman_gate: bogus\n' > "$tmp/.claude/loop/state.md"
  out="$(dnext "$tmp")"
  assert_contains "$out" "run" "unknown gate: fall through, not a false gate"
  rm -rf "$tmp"
}

# ── auto_push.sh: Stop hook that pushes the current work branch at turn end ──
# DRYRUN seam prints "WOULD: git ..." instead of pushing; git fixtures use a bare origin.
autopush() { printf '%s' "$1" | LOOP_AUTOPUSH_DRYRUN=1 bash "$SCRIPTS/auto_push.sh"; }

# bare origin + work clone on branch $2 with one commit; .claude/loop present, no upstream.
mk_repo() {
  git init -q --bare "$1/origin.git"
  git clone -q "$1/origin.git" "$1/work" 2>/dev/null
  (
    cd "$1/work" || exit
    git config user.email t@t.co; git config user.name tester
    git checkout -q -B "$2"
    mkdir -p .claude/loop
    echo one > f1; git add f1; git commit -qm c1
  )
}

test_auto_push() {
  printf '\nauto_push.sh\n'
  local tmp out

  # guard 1: not a loop project
  tmp="$(mktemp -d)"
  out="$(autopush "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "no loop dir: no push"
  rm -rf "$tmp"

  # guard 2: stop_hook_active (already re-prompting)
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  out="$(autopush "$(printf '{"cwd":"%s","session_id":"S1","stop_hook_active":true}' "$tmp")")"
  assert_empty "$out" "stop_hook_active: no push"
  rm -rf "$tmp"

  # guard 3: auto_push disabled
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'auto_push: false\n' > "$tmp/.claude/loop/loop.config.md"
  out="$(autopush "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "auto_push=false: no push"
  rm -rf "$tmp"

  # guard 4: gate_push=true -> every push is a T2 gate, auto-push must stand down
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'gate_push: true\n' > "$tmp/.claude/loop/loop.config.md"
  out="$(autopush "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "gate_push=true: no push"
  rm -rf "$tmp"

  # guard 7a: work branch, no upstream, origin exists -> first push with -u
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  out="$(autopush "$(printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp")")"
  assert_contains "$out" "WOULD: git push -u origin feature/x" "no upstream: push -u origin branch"
  rm -rf "$tmp"

  # guard 7b: upstream set, branch ahead -> plain push
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  ( cd "$tmp/work" && git push -q -u origin feature/x && echo two > f2 && git add f2 && git commit -qm c2 ) >/dev/null 2>&1
  out="$(autopush "$(printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp")")"
  assert_contains "$out" "WOULD: git push" "upstream + ahead: git push"
  rm -rf "$tmp"

  # guard 7c: upstream set, not ahead -> nothing to push
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  ( cd "$tmp/work" && git push -q -u origin feature/x ) >/dev/null 2>&1
  out="$(autopush "$(printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "upstream + not ahead: no push"
  rm -rf "$tmp"

  # guard 6: current branch is protected -> never auto-push
  tmp="$(mktemp -d)"; mk_repo "$tmp" "main"
  out="$(autopush "$(printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "protected branch: no push"
  rm -rf "$tmp"
}

test_verifier_guard
test_decision_gate
test_stop_gate
test_budget
test_gen_ci
test_drive_next
test_auto_push

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
