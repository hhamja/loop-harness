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

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"echo '\''hi'\'' > out.txt"}}')"
  assert_contains "$out" '"deny"' "verifier redirect after quoted arg: still deny"

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"grep -rn '\''foo->bar'\'' src"}}')"
  assert_empty "$out" "verifier grep arrow in quotes: allow (> is data, not a redirect)"

  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"grep -E '\''x => y'\'' f"}}')"
  assert_empty "$out" "verifier grep fat-arrow in quotes: allow"

  # shellcheck disable=SC2016  # awk's $1 is data inside single quotes, literal by design
  out="$(guard '{"agent_type":"verifier","tool_input":{"command":"awk '\''{if ($1 > 5) print}'\'' f"}}')"
  assert_empty "$out" "verifier awk > compare in quotes: allow"

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

  out="$(dgate "$tmp" "git push -f origin feature/x")"
  assert_contains "$out" '"deny"' "force-push short -f: deny (leading push space consumed)"

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

  out="$(dgate "$tmp" "rm -rf /*")"
  assert_contains "$out" '"deny"' "root glob rm -rf /*: deny (empty-var expansion)"

  out="$(dgate "$tmp" "rm -rf ~")"
  assert_contains "$out" '"deny"' "whole home ~: deny"

  out="$(dgate "$tmp" "rm -rf \$HOME")"
  assert_contains "$out" '"deny"' "whole home \$HOME: deny"

  out="$(dgate "$tmp" "rm -rf ~/.claude/skills/x")"
  assert_empty "$out" "home subdir rm: allow (reversible T1, not catastrophic)"

  out="$(dgate "$tmp" "rm -rf \$HOME/.cache")"
  assert_empty "$out" "\$HOME subdir rm: allow (reversible T1)"

  out="$(dgate "$tmp" "git commit -m x")"
  assert_empty "$out" "local commit: allow"

  out="$(dgate "$tmp" "pnpm test 2>&1")"
  assert_empty "$out" "run tests: allow"

  out="$(dgate "$tmp" "rm -rf node_modules")"
  assert_empty "$out" "rm local dir: allow"

  out="$(dgate "$tmp" "git push origin mainline")"
  assert_empty "$out" "push to mainline (not protected): allow"

  out="$(dgate "$tmp" "git push origin HEAD:refs/heads/main")"
  assert_contains "$out" '"deny"' "fully-qualified refs/heads/main: deny"

  out="$(dgate "$tmp" "git push origin feature/main")"
  assert_empty "$out" "branch with main as path segment: allow"

  # force-refspec form (`+ref`) is a force-push with no -f/--force flag -> T2 for any branch
  out="$(dgate "$tmp" "git push origin +main")"
  assert_contains "$out" '"deny"' "force-refspec +main: deny (force-push to protected)"

  out="$(dgate "$tmp" "git push origin +feature/x")"
  assert_contains "$out" '"deny"' "force-refspec +feature: deny (force-push, matches --force policy)"

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

  # unreadable clock (date +%s -> 0) must fail CLOSED: cannot verify marker freshness
  mkdir -p "$tmp/bin"
  # shellcheck disable=SC2016  # $1/$@ are literals for the shim script written to disk
  printf '#!/bin/sh\ncase "$1" in +%%s) echo 0;; *) exec /bin/date "$@";; esac\n' > "$tmp/bin/date"
  chmod +x "$tmp/bin/date"
  printf 'action=push\nsession_id=S1\nts=1000000000\n' > "$tmp/.claude/loop/.gate-approved"
  out="$(printf '{"cwd":"%s","session_id":"S1","tool_input":{"command":"git push origin main"}}' "$tmp" | PATH="$tmp/bin:$PATH" bash "$SCRIPTS/decision_gate.sh")"
  assert_contains "$out" '"deny"' "unreadable clock + old marker: fail closed (deny)"

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

# ── check_memory.sh: Stop hook — memory/state hygiene, block JSON or empty, exit 0 ──
# Blocks on contract/protocol violations (missing state field, untagged entry);
# passes on a clean or absent loop; fails open when re-prompting.
cmem() { printf '%s' "$1" | bash "$SCRIPTS/check_memory.sh"; }

test_check_memory() {
  printf '\ncheck_memory.sh\n'
  local tmp out rc

  # not a loop project
  tmp="$(mktemp -d)"
  out="$(cmem "$(printf '{"cwd":"%s"}' "$tmp")")"; rc=$?
  assert_exit 0 "$rc" "no loop dir: exit 0"
  assert_empty "$out" "no loop dir: no block"
  rm -rf "$tmp"

  # loop dir with only review.md (this repo's shape) -> nothing to judge, pass
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'x\n' > "$tmp/.claude/loop/review.md"
  out="$(cmem "$(printf '{"cwd":"%s"}' "$tmp")")"
  assert_empty "$out" "no state/memory: no block"
  rm -rf "$tmp"

  # stop_hook_active: never block again even with a violation present
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'human_gate: none\n' > "$tmp/.claude/loop/state.md"  # missing loop_active
  out="$(cmem "$(printf '{"cwd":"%s","stop_hook_active":true}' "$tmp")")"
  assert_empty "$out" "stop_hook_active: no block"
  rm -rf "$tmp"

  # clean state + clean memory (fresh init shape) -> pass
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'loop_active: false\nhuman_gate: none\niteration: 0\n' > "$tmp/.claude/loop/state.md"
  printf '## Distilled rules (consult before every cycle)\n(none yet)\n\n## Raw log\n(compress when this section exceeds 200 lines)\n' > "$tmp/.claude/loop/memory.md"
  out="$(cmem "$(printf '{"cwd":"%s"}' "$tmp")")"
  assert_empty "$out" "clean state+memory: no block"
  rm -rf "$tmp"

  # missing loop_active field -> block (drive_next contract)
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'human_gate: none\niteration: 0\n' > "$tmp/.claude/loop/state.md"
  out="$(cmem "$(printf '{"cwd":"%s"}' "$tmp")")"; rc=$?
  assert_exit 0 "$rc" "missing field: exit 0 (block parsed only on exit 0)"
  assert_contains "$out" '"decision":"block"' "missing loop_active: block"
  rm -rf "$tmp"

  # untagged distilled rule -> block; tagged -> pass
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'loop_active: true\nhuman_gate: none\n' > "$tmp/.claude/loop/state.md"
  printf '## Distilled rules\n- serialize suites that bind ports\n\n## Raw log\n' > "$tmp/.claude/loop/memory.md"
  out="$(cmem "$(printf '{"cwd":"%s"}' "$tmp")")"
  assert_contains "$out" '"decision":"block"' "untagged distilled rule: block"
  printf '## Distilled rules\n- [project] serialize suites that bind ports\n\n## Raw log\n' > "$tmp/.claude/loop/memory.md"
  out="$(cmem "$(printf '{"cwd":"%s"}' "$tmp")")"
  assert_empty "$out" "tagged distilled rule: no block"
  rm -rf "$tmp"

  # untagged raw-log entry -> block; tagged -> pass
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'loop_active: true\nhuman_gate: none\n' > "$tmp/.claude/loop/state.md"
  printf '## Distilled rules\n(none yet)\n\n## Raw log\n### R3 test flaky\n- fail: x\n' > "$tmp/.claude/loop/memory.md"
  out="$(cmem "$(printf '{"cwd":"%s"}' "$tmp")")"
  assert_contains "$out" '"decision":"block"' "untagged raw-log entry: block"
  printf '## Distilled rules\n(none yet)\n\n## Raw log\n### [project] R3 test flaky\n- fail: x\n' > "$tmp/.claude/loop/memory.md"
  out="$(cmem "$(printf '{"cwd":"%s"}' "$tmp")")"
  assert_empty "$out" "tagged raw-log entry: no block"
  rm -rf "$tmp"
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
    # Real loop projects gitignore .claude/loop/.* (loop-init) — mirror that with a
    # local exclude so the seeded dotfiles below never show as untracked (keeps the
    # "clean tree" fixtures clean; no tracked file, no extra commit).
    printf '.claude/loop/.*\n' >> .git/info/exclude
    # same-session run-marker: the auto_* hooks now gate on it (loop_lock.sh) —
    # without it they stand down, so seed it for every hook fixture (session S1).
    printf 'session_id=S1\ntimestamp=1\n' > .claude/loop/.run-marker
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
  printf 'session_id=S1\ntimestamp=1\n' > "$tmp/.claude/loop/.run-marker"
  printf 'auto_push: false\n' > "$tmp/.claude/loop/loop.config.md"
  out="$(autopush "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "auto_push=false: no push"
  rm -rf "$tmp"

  # guard 4: gate_push=true -> every push is a T2 gate, auto-push must stand down
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  printf 'session_id=S1\ntimestamp=1\n' > "$tmp/.claude/loop/.run-marker"
  printf 'gate_push: true\n' > "$tmp/.claude/loop/loop.config.md"
  out="$(autopush "$(printf '{"cwd":"%s","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "gate_push=true: no push"
  rm -rf "$tmp"

  # guard 7a: work branch, no upstream, origin exists -> first push with -u
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  out="$(autopush "$(printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp")")"
  assert_contains "$out" "WOULD: git push -u origin feature/x" "no upstream: push -u origin branch"
  rm -rf "$tmp"

  # session gate (P1): marker is session S1, but this turn is a DIFFERENT session -> stand down
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  out="$(autopush "$(printf '{"cwd":"%s/work","session_id":"OTHER"}' "$tmp")")"
  assert_empty "$out" "foreign session: no push (loop_lock gate)"
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

  # pre-push CI gate: red scripts/ci_local.sh -> stand down (no push)
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  mkdir -p "$tmp/work/scripts"; printf '#!/bin/sh\nexit 1\n' > "$tmp/work/scripts/ci_local.sh"
  chmod +x "$tmp/work/scripts/ci_local.sh"
  out="$(autopush "$(printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "ci_local red: no push"
  rm -rf "$tmp"

  # pre-push CI gate: green scripts/ci_local.sh -> push proceeds
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  mkdir -p "$tmp/work/scripts"; printf '#!/bin/sh\nexit 0\n' > "$tmp/work/scripts/ci_local.sh"
  chmod +x "$tmp/work/scripts/ci_local.sh"
  out="$(autopush "$(printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp")")"
  assert_contains "$out" "WOULD: git push" "ci_local green: push proceeds"
  rm -rf "$tmp"
}

# ── auto_commit.sh: Stop hook that commits leftover work-branch changes ──
# DRYRUN seam prints "WOULD: git commit ..." instead of committing.
autocommit() { printf '%s' "$1" | LOOP_AUTOCOMMIT_DRYRUN=1 bash "$SCRIPTS/auto_commit.sh"; }

test_auto_commit() {
  printf '\nauto_commit.sh\n'
  local tmp out before after

  # guard 1: not a loop project
  tmp="$(mktemp -d)"
  out="$(autocommit "$(printf '{"cwd":"%s"}' "$tmp")")"
  assert_empty "$out" "no loop dir: no commit"
  rm -rf "$tmp"

  # guard 2: stop_hook_active (already re-prompting)
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"; echo dirty > "$tmp/work/f2"
  out="$(autocommit "$(printf '{"cwd":"%s/work","stop_hook_active":true}' "$tmp")")"
  assert_empty "$out" "stop_hook_active: no commit"
  rm -rf "$tmp"

  # guard 3: auto_commit disabled
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"; echo dirty > "$tmp/work/f2"
  printf 'auto_commit: false\n' > "$tmp/work/.claude/loop/loop.config.md"
  out="$(autocommit "$(printf '{"cwd":"%s/work"}' "$tmp")")"
  assert_empty "$out" "auto_commit=false: no commit"
  rm -rf "$tmp"

  # guard 5: clean tree -> nothing to commit
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  out="$(autocommit "$(printf '{"cwd":"%s/work"}' "$tmp")")"
  assert_empty "$out" "clean tree: no commit"
  rm -rf "$tmp"

  # dirty work branch -> would commit (untracked file staged by add -A)
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"; echo dirty > "$tmp/work/f2"
  out="$(autocommit "$(printf '{"cwd":"%s/work"}' "$tmp")")"
  assert_contains "$out" "WOULD: git commit" "dirty branch: would commit"
  rm -rf "$tmp"

  # session gate (P1): dirty tree but a DIFFERENT session than the marker -> no commit
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"; echo dirty > "$tmp/work/f2"
  out="$(autocommit "$(printf '{"cwd":"%s/work","session_id":"OTHER"}' "$tmp")")"
  assert_empty "$out" "foreign session: no commit (loop_lock gate)"
  rm -rf "$tmp"

  # local commit is T0 even on a protected branch (direct-to-main workflow)
  tmp="$(mktemp -d)"; mk_repo "$tmp" "main"; echo dirty > "$tmp/work/f2"
  out="$(autocommit "$(printf '{"cwd":"%s/work"}' "$tmp")")"
  assert_contains "$out" "WOULD: git commit" "protected branch: still commits (push is what's gated)"
  rm -rf "$tmp"

  # real run (no dryrun): a new commit lands and the tree goes clean.
  # loop projects gitignore .claude/loop/.* (loop-init), so the hook's own
  # .last-commit log stays out of the tree — mirror that here.
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  printf '.claude/loop/.*\n' > "$tmp/work/.gitignore"
  ( cd "$tmp/work" && git add .gitignore && git commit -qm ignore )
  echo dirty > "$tmp/work/f2"
  before="$(git -C "$tmp/work" rev-list --count HEAD)"
  printf '{"cwd":"%s/work"}' "$tmp" | bash "$SCRIPTS/auto_commit.sh" >/dev/null 2>&1
  after="$(git -C "$tmp/work" rev-list --count HEAD)"
  assert_exit "$((before + 1))" "$after" "real run: exactly one new commit"
  assert_empty "$(git -C "$tmp/work" status --porcelain)" "real run: tree is clean after commit"
  rm -rf "$tmp"

  # worker mode: shared loop state doesn't count toward "something to commit"
  tmp="$(mktemp -d)"; mk_repo "$tmp" "loop/t1"
  printf 'worker: t1\n' > "$tmp/work/.claude/loop/loop.config.md"
  echo progress > "$tmp/work/.claude/loop/state.md"
  out="$(autocommit "$(printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp")")"
  assert_empty "$out" "worker + only state.md dirty: no commit"
  rm -rf "$tmp"

  # worker mode dryrun: only the source file counts (config + state filtered out)
  tmp="$(mktemp -d)"; mk_repo "$tmp" "loop/t1"
  printf 'worker: t1\n' > "$tmp/work/.claude/loop/loop.config.md"
  echo progress > "$tmp/work/.claude/loop/state.md"
  echo dirty > "$tmp/work/f2"
  out="$(autocommit "$(printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp")")"
  assert_contains "$out" "WOULD: git commit (1 files)" "worker: source counted, loop files not"
  rm -rf "$tmp"

  # worker mode real run: sources + results/<task>.md committed, shared state NOT
  tmp="$(mktemp -d)"; mk_repo "$tmp" "loop/t1"
  printf 'worker: t1\n' > "$tmp/work/.claude/loop/loop.config.md"
  echo progress > "$tmp/work/.claude/loop/state.md"
  mkdir -p "$tmp/work/.claude/loop/results"
  printf 'R1 pass\n' > "$tmp/work/.claude/loop/results/t1.md"
  echo dirty > "$tmp/work/f2"
  printf '{"cwd":"%s/work","session_id":"S1"}' "$tmp" | bash "$SCRIPTS/auto_commit.sh" >/dev/null 2>&1
  out="$(git -C "$tmp/work" show --name-only --format= HEAD)"
  assert_contains "$out" "f2" "worker real run: source committed"
  assert_contains "$out" ".claude/loop/results/t1.md" "worker real run: results/<task>.md committed"
  case "$out" in *state.md*) bad "worker real run: state.md NOT committed" "state.md in commit" ;; *) ok "worker real run: state.md NOT committed" ;; esac
  case "$out" in *loop.config.md*) bad "worker real run: worker config NOT committed" "loop.config.md in commit" ;; *) ok "worker real run: worker config NOT committed" ;; esac
  rm -rf "$tmp"
}

# ── auto_pr.sh: Stop hook that opens a PR for the pushed work branch ──
# DRYRUN seam prints "WOULD: gh pr create ..." after the local git guards and
# skips every gh call, so tests need no network or auth.
autopr() { printf '%s' "$1" | LOOP_AUTOPR_DRYRUN=1 bash "$SCRIPTS/auto_pr.sh"; }

# like mk_repo but also sets an upstream (branch pushed), which auto_pr requires.
mk_repo_pushed() { mk_repo "$1" "$2"; ( cd "$1/work" && git push -q -u origin "$2" ) >/dev/null 2>&1; }

test_auto_pr() {
  printf '\nauto_pr.sh\n'
  local tmp out

  # guard 1: not a loop project
  tmp="$(mktemp -d)"
  out="$(autopr "$(printf '{"cwd":"%s"}' "$tmp")")"
  assert_empty "$out" "no loop dir: no PR"
  rm -rf "$tmp"

  # guard 2: stop_hook_active
  tmp="$(mktemp -d)"; mk_repo_pushed "$tmp" "feature/x"
  out="$(autopr "$(printf '{"cwd":"%s/work","stop_hook_active":true}' "$tmp")")"
  assert_empty "$out" "stop_hook_active: no PR"
  rm -rf "$tmp"

  # guard 3: auto_pr disabled
  tmp="$(mktemp -d)"; mk_repo_pushed "$tmp" "feature/x"
  printf 'auto_pr: false\n' > "$tmp/work/.claude/loop/loop.config.md"
  out="$(autopr "$(printf '{"cwd":"%s/work"}' "$tmp")")"
  assert_empty "$out" "auto_pr=false: no PR"
  rm -rf "$tmp"

  # guard 5: protected branch -> never open a PR from main
  tmp="$(mktemp -d)"; mk_repo_pushed "$tmp" "main"
  out="$(autopr "$(printf '{"cwd":"%s/work"}' "$tmp")")"
  assert_empty "$out" "protected branch: no PR"
  rm -rf "$tmp"

  # guard 6: no upstream (branch never pushed) -> nothing to PR from
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  out="$(autopr "$(printf '{"cwd":"%s/work"}' "$tmp")")"
  assert_empty "$out" "no upstream: no PR"
  rm -rf "$tmp"

  # pushed work branch -> would open a PR (ready by default)
  tmp="$(mktemp -d)"; mk_repo_pushed "$tmp" "feature/x"
  out="$(autopr "$(printf '{"cwd":"%s/work"}' "$tmp")")"
  assert_contains "$out" "WOULD: gh pr create --fill (head=feature/x)" "pushed branch: would open PR"
  rm -rf "$tmp"

  # session gate (P1): pushed branch but a DIFFERENT session than the marker -> no PR
  tmp="$(mktemp -d)"; mk_repo_pushed "$tmp" "feature/x"
  out="$(autopr "$(printf '{"cwd":"%s/work","session_id":"OTHER"}' "$tmp")")"
  assert_empty "$out" "foreign session: no PR (loop_lock gate)"
  rm -rf "$tmp"

  # pr_draft:true -> --draft flag added
  tmp="$(mktemp -d)"; mk_repo_pushed "$tmp" "feature/x"
  printf 'pr_draft: true\n' > "$tmp/work/.claude/loop/loop.config.md"
  out="$(autopr "$(printf '{"cwd":"%s/work"}' "$tmp")")"
  assert_contains "$out" "--fill --draft" "pr_draft=true: draft PR"
  rm -rf "$tmp"
}

# ── ci_watch.sh: blocks on the current commit's CI run; loop-owned green gate ──
# A CLI tool (not a hook): runs in the cwd, no JSON stdin. DRYRUN prints "WOULD:"
# after the local git guards and touches no gh, so tests need no network or auth.
ciwatch() { ( cd "$1" && LOOP_CIWATCH_DRYRUN=1 bash "$SCRIPTS/ci_watch.sh" ); }

test_ci_watch() {
  printf '\nci_watch.sh\n'
  local tmp out

  # not a loop project -> skip
  tmp="$(mktemp -d)"
  out="$(ciwatch "$tmp")"
  assert_contains "$out" "SKIP: not a loop project" "no loop dir: skip"
  rm -rf "$tmp"

  # loop project on a branch but no upstream -> skip (push first)
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  out="$(ciwatch "$tmp/work")"
  assert_contains "$out" "SKIP: no upstream" "no upstream: skip"
  rm -rf "$tmp"

  # pushed branch -> would watch this commit's run
  tmp="$(mktemp -d)"; mk_repo_pushed "$tmp" "feature/x"
  out="$(ciwatch "$tmp/work")"
  assert_contains "$out" "WOULD: watch CI run" "pushed branch: would watch"
  rm -rf "$tmp"
}

# ── branch_guard.sh: preflight guard — never work on a protected branch ──
# A CLI tool (not a hook): runs in the cwd, no JSON stdin. DRYRUN prints
# "WOULD: git checkout -b <b>" instead of switching branches.
branchguard() { ( cd "$1" && LOOP_BRANCHGUARD_DRYRUN=1 bash "$SCRIPTS/branch_guard.sh" ); }

test_branch_guard() {
  printf '\nbranch_guard.sh\n'
  local tmp out rc

  # not a loop project -> skip
  tmp="$(mktemp -d)"
  out="$(branchguard "$tmp")"
  assert_contains "$out" "SKIP: not a loop project" "no loop dir: skip"
  rm -rf "$tmp"

  # already on a work branch -> respect it, do nothing
  tmp="$(mktemp -d)"; mk_repo "$tmp" "feature/x"
  out="$(branchguard "$tmp/work")"
  assert_contains "$out" "OK: already on work branch feature/x" "work branch: ok"
  rm -rf "$tmp"

  # gate_push:true (direct-to-main) -> stand down even on a protected branch
  tmp="$(mktemp -d)"; mk_repo "$tmp" "main"
  printf 'gate_push: true\nbranch: feat/x\n' > "$tmp/work/.claude/loop/loop.config.md"
  out="$(branchguard "$tmp/work")"
  assert_contains "$out" "SKIP: gate_push" "gate_push=true: skip"
  rm -rf "$tmp"

  # protected branch + branch: set -> would create the work branch
  tmp="$(mktemp -d)"; mk_repo "$tmp" "main"
  printf 'branch: feat/x\n' > "$tmp/work/.claude/loop/loop.config.md"
  out="$(branchguard "$tmp/work")"
  assert_contains "$out" "WOULD: git checkout -b feat/x" "protected + branch: would branch"
  rm -rf "$tmp"

  # protected branch + no branch: key -> NEED, exit 1 (the one hard stop)
  tmp="$(mktemp -d)"; mk_repo "$tmp" "main"
  out="$(cd "$tmp/work" && bash "$SCRIPTS/branch_guard.sh" 2>&1)"; rc=$?
  assert_exit 1 "$rc" "protected + no branch: exit 1"
  assert_contains "$out" "NEED:" "protected + no branch: NEED"
  rm -rf "$tmp"

  # real run: on main with branch: feat/x -> HEAD actually moves to feat/x
  tmp="$(mktemp -d)"; mk_repo "$tmp" "main"
  printf 'branch: feat/x\n' > "$tmp/work/.claude/loop/loop.config.md"
  ( cd "$tmp/work" && bash "$SCRIPTS/branch_guard.sh" ) >/dev/null 2>&1
  out="$(git -C "$tmp/work" symbolic-ref --short HEAD)"
  assert_contains "$out" "feat/x" "real run: HEAD moved to feat/x"
  rm -rf "$tmp"
}

# ── fleet.sh: live/stale (PID) reconciliation over a fixture sessions dir ──
# FLEET_SESSIONS_DIR injects the sessions dir; live PIDs = this shell ($$) and its
# parent ($PPID, alive for the test's duration); dead PID = 999999 (above macOS
# PID_MAX, so kill -0 fails).
test_fleet() {
  printf '\nfleet.sh\n'
  local tmp out now
  tmp="$(mktemp -d)"
  now=$(( $(date +%s) * 1000 ))
  printf '{"pid":%s,"name":"alive-wait","status":"waiting","kind":"interactive","cwd":"%s","updatedAt":%s}\n' \
    "$$" "$tmp" "$now" > "$tmp/$$.json"
  # empty status + null updatedAt: fields must not collapse/shift and must not crash arithmetic
  printf '{"pid":%s,"name":"alive-empty","status":"","kind":"interactive","cwd":"%s","updatedAt":null}\n' \
    "$PPID" "$tmp" > "$tmp/$PPID.json"
  printf '{"pid":999999,"name":"dead-one","status":"busy","kind":"interactive","cwd":"%s","updatedAt":%s}\n' \
    "$tmp" "$now" > "$tmp/999999.json"

  out="$(FLEET_SESSIONS_DIR="$tmp" bash "$SCRIPTS/fleet.sh" 2>&1)"
  case "$out" in *error*) bad "empty status: no crash" "got: $out" ;; *) ok "empty status: no crash" ;; esac
  assert_contains "$out" "alive-wait" "live PID: shown"
  assert_contains "$out" "alive-empty" "live PID w/ empty status: shown"
  case "$out" in *dead-one*) bad "dead PID: hidden" "dead-one present" ;; *) ok "dead PID: hidden" ;; esac
  assert_contains "$out" "1 stale" "dead PID counted as stale"

  # --swiftbar: menubar title with waiting count, --- separator, dead PID still hidden
  out="$(FLEET_SESSIONS_DIR="$tmp" bash "$SCRIPTS/fleet.sh" --swiftbar 2>&1)"
  assert_contains "$out" "⏳1" "swiftbar: waiting count in title"
  assert_contains "$out" "---" "swiftbar: dropdown separator"
  assert_contains "$out" "alive-wait" "swiftbar: live session listed"
  case "$out" in *dead-one*) bad "swiftbar: dead PID hidden" "dead-one present" ;; *) ok "swiftbar: dead PID hidden" ;; esac
  assert_contains "$out" "1 stale" "swiftbar: stale count in footer"
  assert_contains "$out" "param1=--focus" "swiftbar: rows carry focus click action"

  # --focus: arg validation (actual window-raising is interactive, not tested here)
  FLEET_SESSIONS_DIR="$tmp" bash "$SCRIPTS/fleet.sh" --focus >/dev/null 2>&1
  assert_exit 2 "$?" "focus: missing pid -> exit 2"
  FLEET_SESSIONS_DIR="$tmp" bash "$SCRIPTS/fleet.sh" --focus 999999 >/dev/null 2>&1
  assert_exit 1 "$?" "focus: dead pid -> exit 1"
  FLEET_SESSIONS_DIR="$tmp" bash "$SCRIPTS/fleet.sh" --focus 424242 >/dev/null 2>&1
  assert_exit 1 "$?" "focus: unknown pid -> exit 1"
  rm -rf "$tmp"
}

# ── loop_lock.sh: session-ownership + per-worktree loop lock (gate/acquire/release) ──
# Operates on ./.claude/loop, so each case runs it inside a cd'd subshell.
test_loop_lock() {
  printf '\nloop_lock.sh\n'
  local tmp L
  L="$SCRIPTS/loop_lock.sh"

  # gate P1 — marker presence + same-session
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  ( cd "$tmp" && bash "$L" gate S1 ); assert_exit 1 "$?" "gate: no marker -> stand down"
  printf 'session_id=S1\ntimestamp=1\n' > "$tmp/.claude/loop/.run-marker"
  ( cd "$tmp" && bash "$L" gate S1 ); assert_exit 0 "$?" "gate: same-session marker -> ok"
  ( cd "$tmp" && bash "$L" gate OTHER ); assert_exit 1 "$?" "gate: foreign-session marker -> stand down"
  ( cd "$tmp" && bash "$L" gate unknown ); assert_exit 0 "$?" "gate: unknown sid + marker -> ok (weak fallback)"
  rm -rf "$tmp"

  # acquire / refuse / steal
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude/loop"
  ( cd "$tmp" && bash "$L" acquire S1 111 ); assert_exit 0 "$?" "acquire: fresh -> ok"
  if [ -f "$tmp/.claude/loop/.session-lock" ]; then ok "acquire: lock written"; else bad "acquire: lock written"; fi
  ( cd "$tmp" && bash "$L" acquire S1 222 ); assert_exit 0 "$?" "acquire: same-session re-acquire -> ok"
  ( cd "$tmp" && bash "$L" acquire OTHER 333 2>/dev/null ); assert_exit 1 "$?" "acquire: foreign fresh -> refuse"

  # gate P2 — foreign fresh lock blocks even with same-session marker
  printf 'session_id=S1\ntimestamp=1\n' > "$tmp/.claude/loop/.run-marker"
  ( cd "$tmp" && bash "$L" gate S1 ); assert_exit 0 "$?" "gate: own lock -> ok"
  printf 'session_id=OTHER\npid=1\nepoch=%s\n' "$(date +%s)" > "$tmp/.claude/loop/.session-lock"
  ( cd "$tmp" && bash "$L" gate S1 ); assert_exit 1 "$?" "gate: foreign fresh lock -> stand down"

  # stale foreign lock -> gate ok + acquire steals
  printf 'session_id=OTHER\npid=1\nepoch=1\n' > "$tmp/.claude/loop/.session-lock"
  ( cd "$tmp" && bash "$L" gate S1 ); assert_exit 0 "$?" "gate: stale foreign lock -> ok"
  ( cd "$tmp" && bash "$L" acquire S1 444 ); assert_exit 0 "$?" "acquire: steal stale lock -> ok"

  # release: own removed, foreign fresh kept
  ( cd "$tmp" && bash "$L" release S1 )
  if [ -f "$tmp/.claude/loop/.session-lock" ]; then bad "release: own lock removed" "still present"; else ok "release: own lock removed"; fi
  printf 'session_id=OTHER\npid=1\nepoch=%s\n' "$(date +%s)" > "$tmp/.claude/loop/.session-lock"
  ( cd "$tmp" && bash "$L" release S1 )
  if [ -f "$tmp/.claude/loop/.session-lock" ]; then ok "release: foreign lock kept"; else bad "release: foreign lock kept" "removed"; fi

  # LOOP_LOCK_DISABLE bypasses the gate with no marker
  rm -f "$tmp/.claude/loop/.run-marker" "$tmp/.claude/loop/.session-lock"
  ( cd "$tmp" && LOOP_LOCK_DISABLE=1 bash "$L" gate S1 ); assert_exit 0 "$?" "gate: LOOP_LOCK_DISABLE bypass"

  # TTL boundary: a 10s-old foreign lock is stale at TTL=5, fresh at TTL=3600
  printf 'session_id=S1\ntimestamp=1\n' > "$tmp/.claude/loop/.run-marker"
  printf 'session_id=OTHER\npid=1\nepoch=%s\n' "$(( $(date +%s) - 10 ))" > "$tmp/.claude/loop/.session-lock"
  ( cd "$tmp" && LOOP_LOCK_TTL=5 bash "$L" gate S1 ); assert_exit 0 "$?" "gate: TTL=5, 10s-old foreign lock stale -> ok"
  ( cd "$tmp" && LOOP_LOCK_TTL=3600 bash "$L" gate S1 ); assert_exit 1 "$?" "gate: TTL=3600, 10s-old foreign lock fresh -> stand down"
  rm -rf "$tmp"
}

test_verifier_guard
test_decision_gate
test_stop_gate
test_check_memory
test_loop_lock
test_budget
test_gen_ci
test_drive_next
test_auto_push
test_auto_commit
test_auto_pr
test_ci_watch
test_branch_guard
test_fleet

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
