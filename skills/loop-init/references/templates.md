# loop-init templates

The files `loop-init` writes into `.claude/loop/`. Create each with detected values and TODOs (see the skill's step 3).

### .claude/loop/goal.md

```markdown
# Goal

<one sentence: what "done" means — or TODO: define the goal>

## Stop condition
The loop stops when every criterion in rubric.md passes.
Criteria must be machine-checkable; subjective wording is forbidden
(see loop-engineering skill, references/rubric-guide.md).
```

### .claude/loop/rubric.md

```markdown
# Rubric

<!-- 5-15 criteria. Every criterion MUST carry a verification command or file check. -->
<!-- Checkboxes are updated ONLY by the main agent after a verifier report. -->

- [ ] R1: <criterion> — verify: `<command>` (expect: <observable result>)
```

### .claude/loop/state.md

```markdown
# Loop State

loop_active: false
human_gate: none
iteration: 0
last_run_tokens_est: n/a

## Attempted
(nothing yet)

## Passed
(nothing yet)

## Unresolved
(nothing yet)

## Approaches tried (rejected)
<!-- Per still-unresolved criterion, the approaches already tried and why they
     failed, so the next cycle (esp. a fresh codex) never re-proposes a dead end.
     Drop a criterion's entries once it passes; keep the last ~3-5 per criterion. -->
(nothing yet)

<!-- REWRITE as a summary every cycle. Max 100 lines. Never append —
     single exception: the one-line 'loop interrupted' note the stop gate may ask for. -->
```

### .claude/loop/memory.md

```markdown
# Loop Memory

<!-- 5-step protocol: fail -> investigate -> verify -> distill -> consult.
     See loop-engineering skill, references/memory-protocol.md.
     Tag every entry [plugin] or [project]. -->

## Distilled rules (consult before every cycle)
(none yet)

## Raw log
(compress when this section exceeds 200 lines)
```

### .claude/loop/review.md

```markdown
# Cycle Review (for humans)

<!-- Overwritten every cycle. -->
- Files changed:
- Key changes:
- Risks / needs human eyes:
```

### .claude/loop/loop.config.md

```markdown
# Loop Config — the only stack- and environment-dependent file

test: <detected command or TODO: fill in manually>
lint: <detected command or TODO: fill in manually>
build: <detected command or TODO: fill in manually>

implementer: <codex if `codex --version` succeeded, else claude>
codex_args: <empty — optional extra `codex exec` flags, e.g. `-m <model>` or `-c sandbox_workspace_write.network_access=true` to allow network>
max_iterations: 10
replan_max: 2
escalation: after 3 consecutive failures of the same criterion, replan up to replan_max times (change approach / decompose / spike — see references/replan.md), then present 2-3 options

branch: <type>/<slug — this unit's work branch; branch_guard refuses to work on a protected branch>
protected_branches: main master
gate_push: false
auto_commit: true
auto_push: true
auto_pr: true
pr_draft: false
extra_gates:
```

`protected_branches`, `gate_push`, `extra_gates` drive the decision gate (`decision_gate.sh`, see the loop-engineering skill's `references/decision-gates.md`): pushing to `protected_branches` — or every push when `gate_push: true` — plus release/publish/merge are treated as irreversible (T2) and require human approval; `extra_gates` is an optional `grep -E` regex for project-specific T2 commands. `auto_commit`, `auto_push`, `auto_pr` (all default `true`) are the active side of the same doctrine — at turn end the Stop hooks commit leftover work-branch changes (`auto_commit.sh`, a local commit is always T0), push the branch (`auto_push.sh`), then open a PR (`auto_pr.sh`, via `gh`), so a human returns to a reviewable PR and their only remaining action is the T2 merge. Push still never touches a protected branch and stands down when `gate_push: true`; the PR is never opened *from* a protected branch and only when no open PR already exists (`pr_draft: true` makes it a draft). Absent keys fall back to these defaults, so existing loops need no change.

`branch` names this unit's work branch (GitHub Flow — one small unit = one `<type>/<slug>` branch off the default branch; the merge stays the one human gate). `branch_guard.sh` reads it at loop-run preflight and refuses to work on a protected branch: on `main`/`master` it creates or switches to `branch`, and if `branch` is unset/`TODO` it stops so a human names it. Derive it from the goal: **type** by keyword (`fix`/`bug`/`버그`→`fix`, `refactor`→`refactor`, `doc`→`docs`, `test`→`test`, else `feat`), **slug** = the goal lowercased with non-alphanumerics collapsed to `-`, trimmed, truncated to ~40 chars; write `TODO: <type>/<slug>` when the goal itself is a TODO. Stands down entirely when `gate_push: true` (a direct-to-main repo works on `main` by design).
