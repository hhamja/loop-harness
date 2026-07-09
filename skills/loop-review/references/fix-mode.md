# loop-review — fix mode (`--fix`)

Without `--fix`, loop-review is review-only: write `harness-review.md` and stop. With `--fix`, after the review you autonomously remediate the high-severity findings on a fresh branch and stop at a PR — the human gate is the merge, nothing before it (§5). You never fix or grade your own findings: they become a rubric and `loop-run`'s verified maker/checker loop closes them.

## 1. Partition the findings

- **Auto-fixable** — CONFIRMED, high-severity, and expressible as a machine-checkable `verify:` command: a reproduction whose SECURE outcome is a command exit / grep. E.g. a gate-bypass regex, a checker-guard denylist gap, a parsing/portability bug.
- **Escalate-only** — architecture/design decisions with no single machine check: "no holdout suite", "the approval marker is forgeable by design", "add observability counters". Do NOT auto-build these. They go into the PR body and the report as "human decision required".

If nothing is auto-fixable, say so and stop after the review — do not open an empty branch.

## 2. Open a review branch (T0)

From the current branch (never a protected one): `git checkout -b review/harness-fixes-<short-slug>`. Branch, edits, commits, and work-branch push are all reversible/local — act without asking (§5 T0).

## 3. Turn findings into a frozen rubric

In `<target>/.claude/loop/` (run `/loopy:loop-init` first if it is not initialized), write:

- `goal.md`: "Close the high-severity harness holes listed in harness-review.md."
- `rubric.md`: **one criterion per auto-fixable finding, whose `verify:` command IS that finding's reproduction, asserting the SECURE outcome** — the exploit is now blocked / the bug no longer manifests. Example for the H1-style push bypass:
  `- [ ] R1: git -C bypass blocked — verify: printf '{"cwd":"'$PWD'","tool_input":{"command":"git -C . push origin main"}}' | bash scripts/decision_gate.sh | grep -q '"deny"'`
- Add ONE regression criterion: the project's existing test suite passes (e.g. `bash tests/run.sh`). This is mandatory when fixing the harness's OWN gate scripts/hooks — a fix that closes one gate while weakening another must fail the rubric.

Criteria must be machine-checkable (a command that exits 0), never subjective. They are the acceptance standard; loop-run must never weaken them (its replan rules already forbid this).

## 4. Delegate to loop-run (do NOT fix or grade yourself)

Run `/loopy:loop-run` until the rubric passes. This reuses the entire verified loop — you add nothing to it:

- the maker (Codex or Claude) writes the fix;
- the independent read-only `verifier` re-runs each `verify:` (the exploit → must now be blocked) — maker ≠ checker;
- safety rails apply: `max_iterations`, 3-consecutive-failure replan/escalate, no unbounded loop (the §6 circuit breaker);
- the green gate (`auditor` + `/code-review`) runs before "done";
- `auto_push` pushes the review branch each turn (T0); `decision_gate` mechanically blocks any merge / publish / protected-push / force-push (T2) throughout.

If a criterion cannot be closed within the caps, loop-run escalates it — it stays OPEN in the PR as "unresolved, human needed", never silently dropped or weakened.

## 5. Stop at the human gate — prepare the PR

When loop-run reaches `human_gate: ready_for_merge`, open a **draft** PR to the base branch (T0 — a draft PR and the push are reversible; the MERGE is the T2 human gate). Best-effort `gh pr create --draft`; if `gh` is unavailable, print the branch and the body for the human. The PR body is compressed per §5 — never a diff dump:

- **Closed:** each finding + its now-passing `verify:` proof (before → after).
- **Left for you (human decision):** the escalate-only design items + why they are not auto-fixable.
- **Rollback:** the branch itself; nothing irreversible happened.

## 6. Report

Branch, criteria closed with proof, items escalated, PR link. State explicitly: "'done' is a claim — you review and merge (T2). Nothing was merged, published, or pushed to a protected branch."
