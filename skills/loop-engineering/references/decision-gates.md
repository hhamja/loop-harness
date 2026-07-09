# Decision Gates — reversibility × impact, not "may I ask?"

Human confirmation is the loop's bottleneck. Reduce it by classifying each side-effecting action *before* acting, and gating only the class that cannot be undone. The wrong question is "should I ask?" — the right one is **"can this be undone, and how big is the blast radius?"**

Classify by two axes and take the higher:

- **Reversibility** — can I fully restore the prior state with a local, cheap action (git reset, delete a branch, restore a file)?
- **Impact / blast radius** — how many people, systems, or dollars does it touch if wrong?

## Tiers

**T0 — reversible & local → act autonomously, never re-ask.**
File reads/edits, running tests/typecheck/lint/build, local branch work, local commits, **pushing a work branch**, opening a draft PR. The upper model (main agent) decides and either does it or delegates to the implementer/`explorer`. Re-confirming a T0 step ("shall I start implementing?", "proceed to the next file?") is over-confirmation — forbidden.

**T1 — reversible but shared/observable → act, but record.**
Reversible actions that others can see or that touch remote state cheaply. Do them, and note them in `review.md` so a human can scan what changed.

**T2 — irreversible OR high-impact → human gate.**
Merge into a protected branch (`gh pr merge`), release/publish (`npm/pnpm/yarn/bun publish`, `eas submit`, `gh release create`, tag push), force-push (rewrites remote history), external sends, cost-incurring calls, catastrophic deletes. Stop, summarize context in `review.md`, and get explicit human approval. This is the *only* class that should ever block the loop on a human.

Default gate boundary is the **merge/release line**, not the push line: pushing a work branch is reversible (delete the branch), so it is T0. A repo that pushes straight to `main` should set `gate_push: true` to raise every push to T2.

## Mechanical enforcement

`scripts/decision_gate.sh` (PreToolUse Bash hook) hard-blocks the T2 command set inside any loop project, so the doctrine cannot be silently skipped. It reads three optional keys from `loop.config.md`:

```markdown
protected_branches: main master   # push targeting these is T2 (default: main master)
gate_push: false                  # true = every git push is T2 (direct-to-main repos)
auto_push: true                   # true (default) = Stop hook auto-pushes the work branch
extra_gates:                      # optional grep -E regex for project-specific T2 (e.g. external endpoints, paid builds)
```

The hook is scoped to loop projects only (a cwd with `.claude/loop/`); it never touches general git use elsewhere.

`scripts/auto_push.sh` (Stop hook) is the **active complement** to the block: at turn end inside a loop project it pushes the current work branch — the T0 rule "act autonomously, never re-ask" made mechanical, so a human never has to say "and push it". It never pushes a `protected_branches` branch (that stays a human gate), stands down when `gate_push: true`, never force-pushes or pushes tags, and logs any failure to `.claude/loop/.last-push` without ever blocking the turn. Opt out with `auto_push: false`.

## Passing a gate (the one-shot marker)

When a T2 action is genuinely needed and a human has **explicitly approved** it:

1. The main agent writes `.claude/loop/.gate-approved` with three lines: `action=<class>` (`push`/`merge`/`publish`/`release`/`destructive`/`custom`, or `any`), `session_id=<current session>`, `ts=<epoch seconds>`.
2. Retry the command — the hook allows it while the marker matches the action class, the session, and is under 15 minutes old.
3. Remove the marker immediately after. It is single-use; never leave it lying around, and never write it without a human actually saying yes.

The marker is gitignored (`.claude/loop/.*`). Writing it *is* the act of recording that a human opened the gate — do not forge it to route around approval.

## Relation to the three principles

This is the orchestration layer over maker/checker: the upper model classifies and delegates T0/T1 freely; only T2 escalates. The `auditor` subagent (see `/loop-harness:loop-audit`) later checks that the loop actually held this line — no reversible step wrongly gated (over-confirmation), no T2 action taken without a gate (under-confirmation).
