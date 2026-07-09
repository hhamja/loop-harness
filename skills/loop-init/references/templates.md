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
iteration: 0
last_run_tokens_est: n/a

## Attempted
(nothing yet)

## Passed
(nothing yet)

## Unresolved
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

protected_branches: main master
gate_push: false
auto_commit: true
auto_push: true
extra_gates:
```

`protected_branches`, `gate_push`, `extra_gates` drive the decision gate (`decision_gate.sh`, see the loop-engineering skill's `references/decision-gates.md`): pushing to `protected_branches` — or every push when `gate_push: true` — plus release/publish/merge are treated as irreversible (T2) and require human approval; `extra_gates` is an optional `grep -E` regex for project-specific T2 commands. `auto_commit: true` and `auto_push: true` (both default) are the active side of the same doctrine — at turn end the Stop hooks commit leftover work-branch changes (`auto_commit.sh`, a local commit is always T0) then push the branch (`auto_push.sh`), so a human never has to say "commit and push it"; push still never touches a protected branch and stands down when `gate_push: true`. Absent keys fall back to these defaults, so existing loops need no change.
