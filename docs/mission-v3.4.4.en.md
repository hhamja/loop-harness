# Mission: Loop Harness — Build a Universal Loop-Engineering Claude Code Plugin (v3.4.4 final)

[**English**](mission-v3.4.4.en.md) | [한국어](mission-v3.4.4.md)

Copy everything below and paste it into Claude Code.

**v3.4.3 → v3.4.4 summary of changes:** Three fixes from empirical review (measured on Claude Code v2.1.201) — ① Corrected the dogfooding permission mode: headless (`-p`) cannot show permission prompts, so under `acceptEdits` **every Bash tool call is denied** (empirically confirmed — the loop's test runs, verifier grading, and smoke checks are all impossible; smoke check ② additionally produced a false positive where the permission-layer denial was misread as a guard deny) → replaced with `--permission-mode bypassPermissions` (restricted to throwaway dogfooding projects). Hook denies were empirically confirmed to fire independently of permission mode, so smoke check ②'s verdict premise still holds ② Extended the verifier_guard fallback trigger — previously only "`agent_type` field absent" was defined; now it also covers "field present but value mismatch (deny non-firing demonstrated via the debug log, after one retry with an adjusted match string)": this removes the deadlock path where, in a value-mismatch environment, neither branch of the acceptance criterion (actual blocking / field-absent fallback) could be satisfied. Acceptance criteria, smoke check ②, and the README limitation wording are synchronized ③ Scoped the `--verify-only` read-only guarantee wording to "a fresh session with no residual marker" — if a marker persists in the same session, even a verify-only turn's termination reaches check 4 and updates `.last-usage`, so the "one line in state.md is the only exception" wording was self-contradictory (mechanism unchanged — the guarantee is defined over persistent files (commit targets), with hidden temp files explicitly out of scope). No structural design changes (no new files or hook events).

**v3.4.2 → v3.4.3 summary of changes:** Specified the session_id acquisition mechanism — removing a silent-failure path. ① The acquisition path of the session_id written to `.run-marker` was unspecified (a wrong or missing value makes check 3 always pass, silently neutralizing the entire Stop gate) → now explicitly the Bash environment variable `CLAUDE_CODE_SESSION_ID`. Since this variable is not in the official docs it is treated as version-dependent (confirmed to exist in v2.1.201) and demonstrated by smoke check ③; if unset, `unknown` is recorded ② Added a branch to check 3: `unknown`/unparseable → pass (fail-open); the gate being permanently inactive in environments without the env var is stated as known limitation 3 (fail-open direction — in such environments `.last-usage` is also not recorded, and the token item and Stop-hook-guard item of the acceptance criteria are alternatively satisfied by the README limitation note) ③ New smoke check ③ — verify the env var exists + cross-check that the session_id in `.run-marker` matches the session_id in the stop hook input (defends against contamination from parent-env inheritance in nested headless sessions) ④ Two implementation-pitfall hints added — stat portability for check 4's mtime lookup (macOS/Linux branching or `[ -ot ]` file comparison), and hook-script debug observability (`LOOP_GUARD_DEBUG=1` logs the received input JSON — the means for smoke check ②'s "field absent" demonstration and ③'s match cross-check; disabled by default) ⑤ Noted in the `.last-usage` comment that subsequent non-loop turns in the same session can mix into the delta. No structural design changes (no new files or hook events).

**v3.4.1 → v3.4.2 summary of changes:** Documentation-consistency fixes — ① Scoped the hooks spec's "only the Stop event is used" wording to loop gate verdicts: resolves the textual contradiction with verifier_guard.sh's PreToolUse(Bash) registration (required by the verifier spec and acceptance criteria) ② Added `.claude-plugin/marketplace.json` to the deliverable structure — README requirements and acceptance criteria synchronized so install path ① (via marketplace) works with this repository alone ③ Clarified the ambiguous "passed through check 3" wording in the `.last-usage` recording condition to "reached check 4 (same-session marker present)" ④ Noted that `disallowedTools` support in sub-agent frontmatter may also be version-dependent (if unsupported it is merely ignored and harmless — the primary defense is the absence of Write/Edit from the tools allowlist). No structural design changes.

**v3.4 → v3.4.1 summary of changes:** Edge-case spec fixes — ① Stop gate check 4 now explicitly passes (fail-open) when state.md is absent ② When a `--verify-only` turn is blocked by a residual marker from the same session, the one-line write to state.md is the sole exception to the read-only guarantee — stated in known limitation 2, the README, and the acceptance criteria (no-modification verification is measured against a fresh session) ③ Scoped state.md's "no append" rule to cycle updates only (the one-line unblocking append is an exception) ④ Extended loop-init detection examples to non-JS ecosystems (pyproject.toml, Makefile, Cargo.toml, etc.). No structural design changes.

**v3.3 → v3.4 summary of changes:** ① Corrected two stale factual assertions in the verifier spec — softened "sub-agent frontmatter hooks/permissionMode unsupported" to "version-dependent, unconfirmed for plugin-distributed agents, assume unsupported"; corrected "plugins cannot ship permissions deny" to "some versions can ship settings.json, but it applies session-wide and cannot be scoped to the verifier alone." The design conclusion (a plugin-level PreToolUse hook as the primary means) is unchanged ② Handling for Stop gate check 4's false-block scenario — the block reason now includes a branch instruction "if this turn was unrelated to the loop, append exactly one line 'loop interrupted' to state.md and finish," and "in a loop-run session interrupted without updating state.md, the next turn's termination may be blocked once (self-resolves after one write)" is stated as a known limitation in the hooks spec and README.

**v3.2 → v3.3 summary of changes:** ① Defined the fallback for an **absent** `agent_type` field — if the smoke check confirms the hook input has no `agent_type` field at all, verifier_guard stays inactive (fully fail-open), the defense is downgraded to the double layer of `disallowedTools` + explicit prohibition instructions in the verifier prompt, with a one-line note in the README known limitations. The related acceptance criterion is satisfied by "actual blocking **or** documented downgrade" ② Relaxed the clean-rerun criterion — "zero plugin code modifications" is redefined as "zero plugin **logic** modifications (docs/comment/README edits excluded)," and failures from external factors (network, package registry, scaffolding tool versions, etc.) are not counted as failures; only the affected step is retried.

**v3.1 → v3.2 summary of changes:** ① `--verify-only` does not write `.run-marker` — guaranteeing the whole process is read-only (writing the marker would deadlock: Stop gate check 4 would block verify-only itself) ② Corrected the token-estimate unit from "per cycle" to "per run" — the Stop hook fires only once per loop-run invocation (one turn), so per-cycle measurement is structurally impossible ③ Specified allowed exceptions to verifier_guard's redirect blocking (`2>&1`, `>/dev/null`, etc.) — prevents false positives on test-command idioms ④ Defined the `agent_type` verdict as substring match (contains "verifier") + fail-open when the field is absent, and added a positive test of actual verifier blocking to dogfooding and the acceptance criteria ⑤ Specified non-interactive (headless) rules — loop-init auto-detects instead of asking, records a TODO placeholder on failure and proceeds; expected escalation behavior in headless = print options + record the reason + exit ⑥ Added a verifier tool-availability smoke check to dogfooding (defends against the reported issue of the first/last item of a plugin agent's tools list being dropped) ⑦ Scoped `.last-usage` recording to "same-session marker present" + noted in a comment that a residual `.run-marker` is intended behavior.

## Global rules

- Language: all plugin files (SKILL.md, commands, agent definitions, README, scripts) are written in English (token efficiency, portability). Word budgets are counted in English words via `wc -w`. Chat reports and the final usage summary are in English.
- Output location: `loop-harness/` in the current working directory
- Versioning: a version field in plugin.json, CHANGELOG.md at the root — in preparation for redeployment to existing projects.
- Command notation: plugin commands are always exposed namespaced as `/loop-harness:<name>`. `/loop-init` etc. in this document are shorthand; user-facing docs (README, quickstart) must use the full form (`/loop-harness:loop-init`).
- Path rule: when hooks.json references scripts, always use `${CLAUDE_PLUGIN_ROOT}`-based paths — relative paths break on global install (plugins are copied to a cache directory at install time).

## Background (reference concept summary — no link fetching needed)

Loop engineering: instead of prompting the agent directly every turn, you design "a system that prompts the agent."

- Loop = a recursive structure that repeats execute → collect feedback → self-correct until a verifiable stop condition (goal/rubric) is met
- Six components: Automations (commands/hooks), Worktrees (parallel isolation), Skills (externalized project knowledge), Plugins (distribution unit), Sub-agents (maker/checker separation), Memory (disk-based state)
- Three core principles:
  1. The agent that wrote the code must not grade its own homework → an independent-context verifier sub-agent grades
  2. "Done" is a claim, not a proof → stop conditions must be mechanically checkable (tests pass, lint clean, files exist, etc.)
  3. The model forgets everything between runs → memory lives on disk, not in context
- Five-stage memory protocol: fail (record the failure) → investigate (find the cause) → verify (promote to verified fact) → distill (generalize into a rule) → consult (reference the rules on the next run). Cross-session compounding only happens if all five stages are completed.
- Three boundary principles (must be included in the README): ① "done" is a claim, not a proof — final verification is a human's job ② comprehension debt — force a human-facing review summary of loop outputs ③ loops, verifiers, and subagents consume tokens — always weigh cost versus benefit

## Goal

Build a Claude Code plugin `loop-harness` that ports to any new project (MVP) with "one plugin install (per machine) + one `/loop-harness:loop-init` (per project)."

Design invariant: plugin = immutable logic (global install), `.claude/loop/` = mutable state (project-local, created by loop-init)

## Deliverable structure

```
loop-harness/
├── .claude-plugin/
│   ├── plugin.json                     # Manifest (version required). Only manifest-type files live here
│   └── marketplace.json                # Self-hosted marketplace manifest — for install path ① (marketplace add)
├── CHANGELOG.md
├── README.md                           # See "README requirements" below
├── commands/                           # Everything below is relative to the plugin root
│   ├── loop-init.md                    # Scaffolds .claude/loop/ + auto-detects the stack.
│   │                                   #   Interactive: ask the user when detection fails
│   │                                   #   Non-interactive (-p): never ask — detect from package.json scripts,
│   │                                   #   pyproject.toml, Makefile, Cargo.toml, and other ecosystem manifests;
│   │                                   #   on failure, write a "TODO:" placeholder to loop.config.md + warn, then proceed
│   ├── loop-run.md                     # See "Loop execution model" below
│   └── loop-status.md                  # Prints a summary of state.md
├── agents/
│   ├── verifier.md                     # Grading only (see "verifier spec" below)
│   └── explorer.md                     # Codebase exploration only (optional), read-only. model: haiku in
│                                       #   frontmatter for low cost. When to use it is specified in SKILL.md
├── skills/loop-engineering/
│   ├── SKILL.md                        # YAML frontmatter (name, description) required.
│   │                                   # Body ≤ 500 words: overview + routing for when to read references only
│   └── references/
│       ├── memory-protocol.md          # 5-stage protocol details + entry templates + [plugin]/[project] tag rules
│       ├── rubric-guide.md             # How to write verifiable criteria, ≥3 good/bad example pairs,
│       │                               # incl. 1 machine-verification example for non-code artifacts (docs, etc.)
│       └── worktree-guide.md           # Parallel-execution procedure + merge policy — reference only. No MVP command uses it
├── hooks/hooks.json                    # Auto-discovered (no plugin.json reference needed). See "hooks spec" below
└── scripts/
    ├── check_budget.sh                 # See "Token budget" below
    ├── stop_gate.sh                    # Stop hook verdict + per-run token estimate recording (see "hooks spec")
    └── verifier_guard.sh               # PreToolUse(Bash): blocks the verifier's write-leaning commands (see "verifier spec")
```

worktree-guide.md merge policy: parallel agents never write directly to the main state.md. Each writes to `.claude/loop/results/<task>.md`; only the orchestrator merges.

Project-local files created by loop-init:

```
.claude/loop/
├── goal.md          # Stop condition (mechanically checkable forms only)
├── rubric.md        # 5–15 grading criteria, each with [ ]/[x] + an explicit verification command
├── state.md         # Attempted / passed / unresolved / per-run token estimates + loop-active flag
│                    #   — "summary-updated" every cycle (cycle updates must not append; 100-line cap.
│                    #     Exception: the one-line 'loop interrupted' append that clears a Stop gate block)
│                    #   The active flag is informational for humans and loop-status. Hook block verdicts
│                    #   are based on .run-marker (hooks spec)
├── memory.md        # 5-stage protocol log. Distilled rules stay at the top; compress raw fail logs past 200 lines
├── review.md        # Human-facing review summary of the latest cycle (changed files, key changes, risks)
│                    #   — overwritten every cycle
├── loop.config.md   # test/lint/build commands + max_iterations (default 10) + escalation policy
│                    #   — the only stack-dependent point
├── .run-marker      # Written at loop-run start: session_id + timestamp. --verify-only does NOT write it.
│                    #   session_id is obtained from $CLAUDE_CODE_SESSION_ID (see "Loop execution model")
│                    #   Not deleted after normal completion (intended behavior — see hooks spec). Temp file; never commit
└── .last-usage      # Per-run token estimate written by stop_gate.sh (cumulative transcript size + delta vs. previous).
                     #   Subsequent non-loop turns in the same session also reach check 4, so non-loop usage
                     #   can mix into the delta (accepted as a limitation of the estimate). Temp file; never commit
```

- loop-init adds `.claude/loop/.*` (hidden temp files) to .gitignore. Committing the remaining files is the recommended default (team sharing, session recovery); the README states this policy.

## Verifier spec

- A separate sub-agent with an independent context. Grades against rubric.md only.
- frontmatter: `tools: Read, Grep, Glob, Bash` + `disallowedTools: Write, Edit` (dual defense).
- Known-issue defense: there are reports that the first/last item of a plugin agent's frontmatter tools list gets dropped at spawn. Demonstrate via the smoke check in work-order step 3; if reproduced, mitigate (e.g., reorder the list) and record it in memory.md with a `[plugin]` tag.
- Note: the tools field accepts bare tool names only (no specifiers like `Bash(npm test:*)`). No "read-only Bash" option exists either. `disallowedTools` support in sub-agent frontmatter may likewise be version-dependent — if unsupported it is merely ignored and harmless; the primary defense is that Write/Edit are absent from the tools allowlist in the first place. hooks/permissionMode support in sub-agent frontmatter is version-dependent, and behavior in plugin-distributed agents in particular is unconfirmed — this design assumes unsupported. Some versions support shipping settings.json in a plugin, but permissions rules apply session-wide and cannot be scoped to the verifier alone → the primary means of blocking write-leaning Bash for the verifier only is a plugin-level PreToolUse hook (verifier_guard.sh).
- verifier_guard.sh (PreToolUse, matcher: Bash):
  - Scope verdict: inspect only when the hook input's `agent_type` **contains** "verifier" (substring match, to tolerate value-shape changes such as namespace prefixes). If the `agent_type` field is absent or does not match, always pass (fail-open) — never block Bash from the main agent or any other agent.
  - **Fallback (required):** if the smoke check in work-order step 3 confirms that ⓐ the hook input has no `agent_type` field at all, or ⓑ the field exists but its value never contains "verifier" even when the verifier is spawned, so deny does not fire — demonstrated via the `LOOP_GUARD_DEBUG` log (in this case, retry once with the match string adjusted to the actual value shape from the log; if it still does not fire) — then scope determination is impossible in this environment → ① keep the guard inactive (fully fail-open) ② downgrade the defense to `disallowedTools: Write, Edit` + explicit prohibition instructions in the verifier prompt (list the forbidden write-leaning Bash commands in the body of verifier.md) ③ add a one-line note to the README "Known limitations" ④ record in memory.md with a `[plugin]` tag. In this case the verifier-blocking acceptance criterion is satisfied by the "documented downgrade."
  - Blocked patterns: rm, mv, cp, sed -i, tee, `>`/`>>` redirects to file paths, chmod, git commit/push/checkout/reset, npm publish, etc.
  - Allowed exceptions (false-positive prevention, required): `2>&1`, `>/dev/null`, `2>/dev/null`, `&>/dev/null` — blocking these idioms would make the verifier unable to run test commands at all.
  - On block, return the official hooks-schema deny response (hookSpecificOutput with permissionDecision "deny" + a reason).
  - Debug observability (required): when the `LOOP_GUARD_DEBUG=1` environment variable is set, both verifier_guard.sh and stop_gate.sh append the received hook input JSON to `.claude/loop/.hook-debug.log` (hidden temp file — covered by the `.claude/loop/.*` gitignore rule). In the default (unset) state, nothing is written — the `--verify-only` no-modification guarantee assumes debug is off. Smoke check ②'s discrimination between "agent_type field absent" and "value mismatch," and ③'s session_id cross-check, are only possible via this log.
  - The invariant is not "fully read-only" but **"no modification of source or loop state files."** Incidental writes from running tests/builds (caches, coverage, etc.) are allowed.
- The verifier returns a verdict report only (per-criterion pass/fail + supporting command output). The main agent, upon receiving the report, updates the rubric.md checkboxes and state.md. The verifier modifies no files.

## Loop execution model (/loop-harness:loop-run)

- Default behavior: repeat cycles until every rubric criterion passes or a safety rail triggers.
- Options: `--once` = run exactly 1 cycle (incremental adoption, cost control). `--verify-only` = run verifier grading once with no implementation and print the report (for reviewing existing code; the entry point of incremental adoption). **`--verify-only` is read-only end to end: it writes or modifies no files, including `.run-marker`** (measured against a fresh session with no residual marker — if a marker persists in the same session, stop_gate updates `.last-usage` at turn end; see the hooks spec and known limitation 2) — writing the marker would make Stop gate check 4 block verify-only itself.
- 1 cycle = implement → verifier grading (phase gate, once at cycle end only) → main agent updates rubric/state/memory/review.
- At start, loop-run writes session_id + timestamp to `.claude/loop/.run-marker` (except `--verify-only`). session_id is obtained from the Bash environment variable `CLAUDE_CODE_SESSION_ID` — treated as version-dependent since it is not in the official docs, and demonstrated by smoke check ③ in work-order step 3. If unset/empty, record `unknown` (fail-open at check 3 of the hooks spec).
- Token recording: an agent cannot directly know its own token usage. The unit of record is a **run (= one loop-run invocation)** — the Stop hook fires only once at turn end, so per-cycle measurement is structurally impossible; do not claim it. stop_gate.sh computes an estimate from the hook input's transcript size (bytes/4), writes the cumulative value and the delta vs. the previous record to `.last-usage`, and the main agent folds it into state.md at the next update, explicitly labeled an "estimate." Do not claim precise measurement.
- Loop safety rails (required):
  - If loop.config.md's max_iterations is exceeded: stop the loop + record the stop reason in state.md
  - If the same criterion fails 3 times in a row: stop the loop + escalate to the user with 2–3 options. In non-interactive (headless) runs no response can be received, so expected behavior = print the options + record the stop reason in state.md + exit.
  - An "infinite retry until pass" implementation with no safety rails is forbidden

## Hooks spec

- Only the `Stop` event is used for loop gate verdicts. SubagentStop is not used — the verifier modifies no files, so demanding a state.md update on SubagentStop would deadlock. verifier_guard.sh's `PreToolUse(Bash)` registration is separate from this (see the verifier spec); both events are registered together in hooks.json.
- stop_gate.sh verdict order (block only if ALL apply):
  1. No `.claude/loop/` → pass (protects loop-unrelated sessions)
  2. Input's `stop_hook_active == true` → pass (prevents infinite block loops)
  3. No `.run-marker`, marker's session_id ≠ current session_id, or marker's session_id is `unknown`/unparseable → pass (protects new sessions from being blocked by a residual marker after a force-kill. In runs where the session_id could not be obtained the gate is inactive — fail-open, known limitation 3)
  4. state.md mtime < marker timestamp → block: exit 0 + `{"decision":"block","reason":"state.md not updated this run. If this turn was loop work: update state.md (attempted / passed / unresolved). If this turn was unrelated to the loop: append exactly one line 'loop interrupted (previous run did not update state)' to state.md, then finish."}`
     — the reason's branch instruction handles the false-block scenario (in the same session as a loop-run that stopped without updating state.md, a later loop-unrelated turn gets blocked once). It converts the forced update from noise into a useful interruption record, and once state.md has been written once, mtime > marker timestamp, so it self-resolves afterwards. If state.md itself is missing (partial init, manual deletion, etc.), the mtime comparison is impossible, so pass without blocking (fail-open — the principle of never blocking when a verdict is impossible). Implementation hint: mtime lookup flags differ between macOS (`stat -f %m`) and Linux (`stat -c %Y`), so branch on uname — or, equivalently, compare against the marker file's own mtime with `[ state.md -ot .run-marker ]` (the marker is written at run start).
- `.last-usage` is written only when the run did not hit the pass (early-exit) branches of checks 1–3 and reached check 4 — i.e., only when a same-session marker exists. This preserves the no-modification guarantee for loop-unrelated sessions and for fresh-session `--verify-only` (if a marker persists in the same session, `.last-usage` is updated even at the end of a `--verify-only` turn).
- `.run-marker` is not deleted after normal completion — once state.md has been updated even once, mtime > marker timestamp, so subsequent stops naturally pass check 4. State this intent in a comment in stop_gate.sh (prevents mistaking the residual marker for a bug).
- Block responses follow the official hooks schema (JSON decision:block). Caution: block JSON is **parsed only on exit 0** — combined with exit 2, the JSON is ignored.
- Known limitation 1: in `claude --resume` sessions, the session_id change can neutralize the gate via check 3. This fails in the fail-open (non-blocking) direction, so accept it and state it in one line in the README.
- Known limitation 2: in the same session as a loop-run that stopped without updating state.md, the termination of a later loop-unrelated turn can be blocked once by check 4 (self-resolves after the one-line state.md write per the reason's branch instruction). It is the only false-block-direction limitation, so state it in one line in the README. If that turn is `--verify-only`, the one-line state.md write that clears the block is the sole exception to the read-only guarantee (defined over persistent, commit-target files) — the hidden temp file `.last-usage` is outside the guarantee's scope and is always updated when check 4 is reached. The acceptance criteria's `--verify-only` no-modification verification is performed with no residual marker present (a fresh session).
- Known limitation 3: in versions/environments where `CLAUDE_CODE_SESSION_ID` is not provided to the Bash environment, the marker's session_id is recorded as `unknown` and the Stop gate always passes (inactive) via check 3. This fails in the fail-open direction, so accept it, and add the one-line README note only if demonstrated by smoke check ③. In such environments `.last-usage` (per-run token estimates) is not recorded either (check 4 is never reached).
- All script paths are referenced as `${CLAUDE_PLUGIN_ROOT}/scripts/...`.

## Token budget (hard constraints)

- Resident surface area (skill description + sum of command/agent descriptions) ≤ 300 words
- SKILL.md body ≤ 500 words; details split into references/ and loaded only when needed
- `scripts/check_budget.sh` counts both and returns the numbers + pass/fail via exit code — budget compliance is proven only by this script's output
- Call the verifier only at phase gates (cycle end). Never per file edit
- Deterministic/repetitive work (state-file parsing, budget checks, hook verdicts, token estimation) is handled by scripts, not prompts

## Core requirements

1. Maker/Checker separation: the implementing agent and the verifier must be separate sub-agents (per the spec above). The loop must not end before all criteria pass — except a stop when a safety rail triggers.
2. Stack agnosticism: no stack-dependent code in the loop logic. Must work unmodified on both a Next.js/TypeScript project and a Phaser 3 + Vite project. Stack differences are absorbed solely by the command mapping in loop.config.md.
3. Only verifiable stop conditions: every rubric criterion must be decidable by running a command or inspecting files. Subjective criteria like "the code is clean" are forbidden.
4. File-based memory: all loop state lives on disk in `.claude/loop/`. The next session must be able to resume from where it stopped by reading only `.claude/loop/`, with state.md as the entry point.
5. Incremental adoption: parts of the loop must be usable on their own — `--verify-only` (grading only) → `--once` (single cycle) → full loop. Document the adoption path in the README.

## README requirements

- Two install paths:
  - ① via marketplace: `/plugin marketplace add <repo>` → `/plugin install loop-harness@<marketplace>`. State that marketplace.json is included at `.claude-plugin/marketplace.json`, so this repository can be added as a marketplace as-is.
  - ② local development: `claude --plugin-dir ./loop-harness` (absolute path recommended)
- 3-minute quickstart — all commands written in full namespaced form (`/loop-harness:loop-init`, etc.)
- Incremental adoption path (`--verify-only` → `--once` → full loop)
- Token-cost caveats
- The three boundary principles
- `.claude/loop/` commit policy (commit everything except temp files, recommended)
- One-line known limitation: in `--resume` sessions the Stop gate may be inactive due to session_id changes
- One-line known limitation: in a loop-run session that stopped without updating state.md, the next turn's termination may be blocked once (self-resolves after a one-line state.md write. If that turn is `--verify-only`, this is the sole exception to the read-only guarantee — defined over persistent files; the temp file `.last-usage` is out of scope)
- Known limitation (add only if applicable): in environments where the hook input provides no `agent_type` (or its value cannot identify the verifier), verifier write-blocking is downgraded to `disallowedTools` + prompt prohibition instructions
- Known limitation (add only if applicable): in environments where `CLAUDE_CODE_SESSION_ID` is not provided to the Bash environment (or mismatches due to nested-session inheritance), the Stop gate is inactive (fail-open direction)

## Work order

1. Create the plugin skeleton per the structure above → write each file (commands → agents → skills → hooks → scripts, in that order)
2. Run `check_budget.sh` → confirm the budget passes (fix and rerun if not)
3. Dogfooding A — the execution method is fixed as follows:
   - Run headless nested sessions in the target project directory: `claude -p "<instruction or /loop-harness:command>" --plugin-dir <absolute plugin path> --permission-mode bypassPermissions`, with a per-call timeout (e.g., 10 minutes)
   - Permission-mode caution: headless cannot show permission prompts, so under `acceptEdits` every Bash tool call is denied (measured on v2.1.201 — the loop, the verifier, and the smoke checks are all impossible; smoke ②'s positive test produced a false positive where a permission-layer denial was misread as a guard deny). Use `bypassPermissions` only for throwaway dogfooding projects. Hook denies fire independently of permission mode (empirically confirmed), so smoke ②'s positive/negative test premise holds
   - If custom slash commands do not run under `-p`, fall back to passing the command file's body directly as the prompt, and record that fact in memory.md with a `[plugin]` tag
   - Cost control: dogfooding rubric of 3–5 criteria, max_iterations set to 3
   - **Three smoke checks (① and ② run right after loop-init, before entering the first cycle; ③'s match cross-check runs after the first loop-run turn ends):**
     - ① Give the verifier a harmless inspection task that uses each of the 4 tools Read/Grep/Glob/Bash once, confirming all are actually usable (defends against the tools-list first/last item drop issue). On failure, mitigate (e.g., reorder the list) and record `[plugin]` in memory.md
     - ② Have the verifier deliberately attempt `git commit --allow-empty -m test` to confirm verifier_guard's deny actually fires (positive test), and simultaneously confirm the main agent's identical command is NOT blocked (negative test). **If deny does not fire, determine the cause via verifier_guard's `LOOP_GUARD_DEBUG=1` log (without the log you cannot distinguish a value mismatch from an absent field): if the field itself is absent, apply the verifier-spec fallback immediately; if the field exists but the value does not hit the substring match, adjust the match string to the actual value from the log and retry once — if it still does not fire, apply the same fallback. In both cases the positive-test requirement is replaced by confirming execution of the downgrade path (disallowedTools + prompt prohibition + README note + memory record).**
     - ③ Confirm `CLAUDE_CODE_SESSION_ID` exists in the Bash environment. If absent, confirm the `unknown` fallback (check 3 fail-open) works, and add the one-line README known limitation + a `[plugin]` record in memory.md. If present, after the first loop-run turn ends, cross-check via the `LOOP_GUARD_DEBUG=1` log that `.run-marker`'s session_id matched the stop hook input's session_id (defends against contamination from parent-session env inheritance in nested headless sessions). On mismatch, likewise add the one-line README limitation + memory record (the gate goes inactive in the fail-open direction)
   - Content: empty Next.js project (create-next-app, network required) → loop-init → set one small feature as the goal (e.g., health-check API + tests) → run the loop → confirm verifier grading and state/memory/review updates
4. During A, session-resume test: force-kill the child process mid-loop with timeout/kill → in a new headless session run `/loop-harness:loop-status` → confirm it resumes from the stopping point using `.claude/loop/` alone. Also confirm the residual .run-marker (another session's session_id) does not block the new session's termination
5. During A, safety-rail test: deliberately add 1 impossible-to-pass criterion to the rubric and confirm escalation actually triggers after 3 consecutive failures. In headless, the check target is "escalation options printed + stop reason recorded in state.md + exit." (Remove the criterion afterwards)
6. Dogfooding B: repeat the step 3 procedure on a Phaser 3 + Vite project
7. Record problems found during dogfooding via the 5-stage protocol in memory.md while fixing the plugin (improving the plugin itself with a loop). Tag records `[plugin]` (harness defect) / `[project]` (target-project defect) to prevent contamination of the distill stage
8. Clean rerun: after all fixes are complete, rerun the A/B dogfooding from scratch and confirm it passes with **zero plugin logic modifications** (docs/comment/README edits do not count as logic changes). Failures caused by factors external to the plugin — network, package registries, scaffolding tool versions, etc. — do not count as failures; retry only the affected step (record the error cause in state.md to distinguish external factors). Maximum 3 attempts; beyond that, summarize the failure causes, report to the human, and stop

## Acceptance criteria (all must be met for completion)

- [ ] New-project adoption procedure = 1 install + 1 loop-init. README documents both install paths (including the marketplace add step)
- [ ] The verifier grades in an independent context, with Write/Edit not granted + `disallowedTools` declared + an `agent_type`-scoped (substring match, fail-open when the field is absent) PreToolUse guard actually configured — the verifier's write-leaning Bash is actually blocked with a deny (positive test) and the main agent's identical command is not blocked, both demonstrated. **However, in environments where the smoke check demonstrates an absent `agent_type` field or a value mismatch (deny still not firing after one retry with an adjusted match string), this criterion is satisfied by executing the fallback (guard inactive + disallowedTools + prompt prohibition + README limitation note + memory record)**
- [ ] The verifier can actually use all 4 frontmatter tools (Read/Grep/Glob/Bash) (demonstrated by the work-order step 3 smoke check)
- [ ] Rubric checkbox/state.md updates are consistently performed by the main agent (the verifier only returns reports)
- [ ] Every rubric criterion is mechanically verifiable
- [ ] After a session force-kill and restart, execution can continue from `.claude/loop/` alone (demonstrated by work-order step 4)
- [ ] max_iterations + 3-consecutive-failure escalation works — headless: options printed + reason recorded + exit (demonstrated by work-order step 5)
- [ ] Clean rerun passes dogfooding on both Next.js/Phaser — zero plugin logic modifications (docs/comments excluded); external-factor failures handled by retry, with causes recorded in state.md
- [ ] check_budget.sh passes (300 resident words, 500-word SKILL.md body) — output attached
- [ ] review.md generated every cycle (addresses comprehension debt)
- [ ] memory.md actually contains 5-stage progression traces (fail→distill) and [plugin]/[project] tags
- [ ] state.md stays summary-updated within the 100-line cap and records per-run token estimates (produced by stop_gate.sh). However, in environments where smoke check ③ demonstrates the session_id cannot be obtained, this is alternatively satisfied by the README limitation note
- [ ] Stop hook triple guard verified: ① loop-unrelated session not blocked ② not blocked when stop_hook_active ③ residual marker (other session) not blocked. However, in environments where smoke check ③ demonstrates session_id unavailability/mismatch, this is alternatively satisfied by documenting "gate inactive + README limitation note"
- [ ] `--verify-only` prints only a grading report for existing code and modifies no files (including not writing `.run-marker`) + is not blocked by the Stop gate — verified against a fresh session with no residual marker (see the exception in known limitation 2)
- [ ] plugin.json has a version, `.claude-plugin/` has marketplace.json, and CHANGELOG.md exists at the root
- [ ] README includes the quickstart (fully namespaced commands) + the incremental adoption path + the three boundary principles

## Pre-questions

Ask any pre-implementation questions (target stack, issue tracker/CI, etc.) all at once. If no answers arrive, state the following defaults and proceed: stack-agnostic (loop-init detects — asks only in interactive mode on detection failure; non-interactive writes a TODO placeholder and proceeds), no issue-tracker/CI integration, test/lint/build commands detected by loop-init (package.json scripts, pyproject.toml, Makefile, Cargo.toml, and other ecosystem manifests) or asked for, then recorded in loop.config.md.

## Progress rules

- On completing each step, report the produced file paths and the acceptance-criteria check status
- For unclear decisions, do not guess — ask with 2–3 options + trade-offs
- Never declare "done" while acceptance criteria are unmet
