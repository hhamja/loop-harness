#!/usr/bin/env bash
# loopy local CI — the SINGLE SOURCE of the checks CI runs, runnable locally.
#
# .github/workflows/ci.yml calls this script, so "green locally" and "green in
# CI" cannot drift: run `bash scripts/ci_local.sh` before a branch is pushed and
# a pass here is a pass there. auto_push.sh runs it too and stands down when red,
# so a red commit never reaches origin (and never shows a red check on the PR).
#
# Exit 0 = all green. Any failing check aborts (set -e) with a non-zero exit.

set -eu

cd "$(dirname "$0")/.." || exit 1

echo "== shellcheck =="
shellcheck scripts/*.sh tests/*.sh

echo "== bash -n (syntax) =="
for f in scripts/*.sh tests/*.sh; do
  bash -n "$f"
done

echo "== manifest JSON =="
for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  jq empty "$j"
done
jq -e '.name and .version and .description and .author.name' \
  .claude-plugin/plugin.json > /dev/null
jq -e '.name and .owner.name and (.plugins | length > 0)' \
  .claude-plugin/marketplace.json > /dev/null

echo "== budget (CLAUDE.md: descriptions + SKILL bodies) =="
bash scripts/check_budget.sh

echo "== hook contract tests =="
bash tests/run.sh

echo "ALL GREEN"
