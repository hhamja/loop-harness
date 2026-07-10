#!/usr/bin/env bash
# loopy session state digest (SessionStart hook).
#
# Injects every .claude/loop/state.md in the project (root + nested, e.g. a
# monorepo's apps/*/) into session context — SessionStart stdout becomes
# context verbatim, no JSON envelope needed. Motivation: "read state.md before
# answering" was prompt guidance only, so sessions kept trusting stale
# cross-session memory over fresh disk state; injecting the disk state up
# front turns that discipline into a mechanism.
#
# Fail-open on every doubt: no root state.md (not a loop project, and the
# cheap guard that skips the find on non-loop repos) -> silent exit 0.
# Never blocks, never exits nonzero.

set -u

# shellcheck source=scripts/hook_lib.sh
. "$(cd "$(dirname "$0")" && pwd)/hook_lib.sh"
hook_init

# --- not a loop project (nested-only repos are deliberately skipped) ---
[ -f "$LOOP_DIR/state.md" ] || exit 0

printf '# Loop State Digest (SessionStart 자동 주입 — 디스크 state가 메모리의 status보다 우선)\n'

# ponytail: 통째 주입 — 중첩 state.md가 많아 비대해지면 Unresolved만 추출로 다운그레이드
# find matches the root file too (*/ covers ./); _template dirs are scaffolding.
find . -path './.git' -prune -o -path '*/node_modules' -prune -o -path '*_template*' -prune \
  -o -path "*/$LOOP_DIR/state.md" -print 2>/dev/null | sort |
while IFS= read -r f; do
  printf '\n## %s\n' "${f#./}"
  # strip <!-- --> comments (the template's REWRITE instruction must not reach
  # context); lines that were pure comment vanish, blank lines survive.
  awk '{
    out=""; line=$0
    while (length(line)) {
      if (inC) { j=index(line,"-->"); if (j) { line=substr(line,j+3); inC=0 } else line="" }
      else { i=index(line,"<!--"); if (i) { out=out substr(line,1,i-1); line=substr(line,i+4); inC=1 }
             else { out=out line; line="" } }
    }
    if (out != "" || $0 == "") print out
  }' "$f" 2>/dev/null || true
done

exit 0
