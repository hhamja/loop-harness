---
description: Scaffold .claude/loop/ state files and detect this project's test/lint/build commands
---

# loop-init — scaffold project-local loop state

Create the mutable loop state under `.claude/loop/` in the current project. The plugin itself is immutable; everything the loop learns or tracks lives in these files.

**Idempotency:** if `.claude/loop/` already exists, list its files and stop. Never overwrite existing loop state.

## Steps

Scaffold first, questions last: you often cannot tell whether anyone can answer you (headless `-p` sessions look identical to interactive ones). Creating the files NEVER waits on user input.

1. **Detect stack commands** for `loop.config.md`. Check ecosystem manifests in this order and extract test / lint / build commands:
   - `package.json` → `scripts.test` / `scripts.lint` / `scripts.build` (prefix with the package manager detected from the lockfile: npm / pnpm / yarn / bun)
   - `pyproject.toml` → pytest / ruff / mypy etc. from tool sections or dev dependencies
   - `Makefile` → `test` / `lint` / `build` targets
   - `Cargo.toml` → `cargo test` / `cargo clippy` / `cargo build`
   - `go.mod` → `go test ./...` / `go vet ./...` / `go build ./...`

   For anything missing or ambiguous, use `TODO: <fill in manually>` — do not stop to ask.
2. **Detect the implementer:** run `codex --version` via Bash. Exit 0 → write `implementer: codex`; anything else → `implementer: claude`. Never ask — this is a mechanical check. Leave `codex_args` empty either way.
3. **Create the files** from the templates below immediately, using detected values and TODOs. Goal: use the command arguments if given, else `TODO: define the goal`. Print one warning line per TODO written.
4. **Gitignore:** ensure the project `.gitignore` contains the line `.claude/loop/.*` (create `.gitignore` if missing; skip if the line already exists). Non-hidden loop files are MEANT to be committed (team sharing, session recovery).
5. **Interactive refinement (optional):** only AFTER the files exist, and only if this session is clearly interactive (a human typed the command and can reply), you may ask ONE question to fill the remaining TODOs, then update the files. If in doubt, skip — TODOs are the designed outcome. Never end the turn with questions instead of created files.
6. **Report:** created paths + remaining TODOs + the detected implementer + next steps — try `/loop-harness:loop-run --verify-only` first (grade only), then `/loop-harness:loop-run`. If `implementer: claude` because no Codex CLI was found, note: install the Codex CLI and run `codex login`, then set `implementer: codex` in loop.config.md to enable the cross-model maker/checker split.

## Templates

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
auto_push: true
extra_gates:
```

`protected_branches`, `gate_push`, `extra_gates` drive the decision gate (`decision_gate.sh`, see the loop-engineering skill's `references/decision-gates.md`): pushing to `protected_branches` — or every push when `gate_push: true` — plus release/publish/merge are treated as irreversible (T2) and require human approval; `extra_gates` is an optional `grep -E` regex for project-specific T2 commands. `auto_push: true` (the default) is the active side of the same doctrine — the Stop hook (`auto_push.sh`) pushes the current work branch at turn end so a human never has to; it never pushes a protected branch and stands down when `gate_push: true`. Absent keys fall back to these defaults, so existing loops need no change.
