#!/usr/bin/env bash
# loopy CI watch — block until THIS commit's CI run concludes, then report.
#
# Used by the drive loop's GREEN GATE — it is a tool the agent runs, NOT a hook:
# a Stop hook must never block, but CI is async (seconds to minutes after push),
# so watching belongs to the loop. Remote CI being green is a T0/T1 verification
# the loop owns and drives to green autonomously; only the MERGE is T2. On red the
# loop reopens a rubric criterion and fixes it, capped by max_iterations.
#
#   bash scripts/ci_watch.sh [timeout_seconds]   (default 300)
#
# Exit 0 = green, or nothing to watch (prints "SKIP: <reason>" — fail-open, the
#          loop is not blocked when CI can't be observed).
# Exit 1 = red: prints the failing job log tail so the loop can fix root cause.
# A deadline bounds every wait, so this can never hang the loop.
#
# Test seam: LOOP_CIWATCH_DRYRUN=1 prints "WOULD: watch ..." after the local git
# guards and touches no gh, so tests need no network or auth.

set -u

TIMEOUT="${1:-300}"
case "$TIMEOUT" in ''|*[!0-9]*) TIMEOUT=300 ;; esac

now() { date +%s 2>/dev/null || echo 0; }

# --- local guards (fail-open with a reason) ---
[ -d ".claude/loop" ] || { echo "SKIP: not a loop project"; exit 0; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "SKIP: not a git work tree"; exit 0; }
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || { echo "SKIP: detached HEAD"; exit 0; }
git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 \
  || { echo "SKIP: no upstream (push first)"; exit 0; }
SHA="$(git rev-parse HEAD 2>/dev/null || true)"
[ -n "$SHA" ] || { echo "SKIP: no commit"; exit 0; }

# --- test seam ---
if [ "${LOOP_CIWATCH_DRYRUN:-}" = "1" ]; then
  echo "WOULD: watch CI run for ${SHA} on ${BRANCH} (timeout ${TIMEOUT}s)"
  exit 0
fi

# --- gh guards ---
command -v gh >/dev/null 2>&1 || { echo "SKIP: gh not installed"; exit 0; }
gh auth status >/dev/null 2>&1 || { echo "SKIP: gh not authenticated"; exit 0; }

START="$(now)"

# --- resolve the run for THIS commit (CI may lag the push; retry to the deadline) ---
RID=""
while :; do
  RID="$(gh run list --branch "$BRANCH" --limit 20 --json databaseId,headSha \
        -q "map(select(.headSha==\"$SHA\")) | .[0].databaseId" 2>/dev/null || true)"
  case "$RID" in ''|null) RID="" ;; esac
  [ -n "$RID" ] && break
  [ "$(( $(now) - START ))" -lt "$TIMEOUT" ] || { echo "SKIP: no CI run for $SHA within ${TIMEOUT}s"; exit 0; }
  sleep 6
done

# --- poll the run to completion within the deadline ---
while :; do
  LINE="$(gh run view "$RID" --json status,conclusion -q '.status+" "+(.conclusion // "")' 2>/dev/null || true)"
  STATUS="${LINE%% *}"
  CONCL="${LINE#* }"
  if [ "$STATUS" = "completed" ]; then
    if [ "$CONCL" = "success" ]; then
      echo "GREEN: run $RID ($SHA) succeeded"
      exit 0
    fi
    echo "RED: run $RID ($SHA) -> ${CONCL:-unknown}"
    gh run view "$RID" --log-failed 2>/dev/null | tail -n 40
    exit 1
  fi
  [ "$(( $(now) - START ))" -lt "$TIMEOUT" ] || { echo "SKIP: run $RID still ${STATUS:-pending} after ${TIMEOUT}s"; exit 0; }
  sleep 8
done
