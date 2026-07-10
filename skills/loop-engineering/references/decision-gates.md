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
auto_commit: true                 # true (default) = Stop hook commits leftover work at turn end
auto_push: true                   # true (default) = Stop hook auto-pushes the work branch
auto_pr: true                     # true (default) = Stop hook opens a PR for the pushed branch
pr_draft: false                   # true = open that PR as a draft
extra_gates:                      # optional grep -E regex for project-specific T2 (e.g. external endpoints, paid builds)
```

The hook is scoped to loop projects only (a cwd with `.claude/loop/`); it never touches general git use elsewhere.

Three Stop-hook scripts are the **active complement** to the block — the T0 rule "act autonomously, never re-ask" made mechanical for the steps a human should never have to prompt. They run in order (commit → push → PR) so a turn ends with the work on a reviewable PR, and the human's only remaining action is the T2 merge:

`scripts/auto_commit.sh` runs first: if the work tree has uncommitted changes it commits them (`git add -A`) with a generic backstop message, so a turn never ends with verified work left uncommitted. It is NOT gated on `protected_branches`/`gate_push` — a local commit is unconditionally T0 (undo with `git reset`), including on `main` in a direct-to-main repo where the workflow is "commit locally, human gates the push". The primary path is still the agent committing inline with a written message; this hook only fires when it didn't. Opt out with `auto_commit: false`. Commit failure logs to `.claude/loop/.last-commit` and never blocks the turn.

`scripts/auto_push.sh` runs next: it pushes the current work branch so a human never has to say "and push it". It never pushes a `protected_branches` branch (that stays a human gate), stands down when `gate_push: true`, never force-pushes or pushes tags, and logs any failure to `.claude/loop/.last-push` without ever blocking the turn. Opt out with `auto_push: false`. **Pre-push CI gate:** if the repo ships an executable `scripts/ci_local.sh` (the single source of the checks `ci.yml` runs), auto_push runs it first and stands down when it is red — so a red commit never reaches origin and the PR never shows a failing required check. The commit still lands locally (T0); only the push waits for green.

`scripts/auto_pr.sh` runs last: once the branch is pushed it opens a pull request (`gh pr create --fill` — title/body from the commit log, base = the repo's default branch) so the human returns to a reviewable PR, not a bare branch. Opening a PR is T0 (reversible: close it; the *merge* is the T2 gate). It never opens a PR *from* a protected branch, requires an upstream (the branch was pushed) plus an authenticated `gh`, and — since a branch can carry a merged/closed PR and new commits — only creates when there is no *open* PR for the branch. `pr_draft: true` opens it as a draft. Opt out with `auto_pr: false`; outcome logs to `.claude/loop/.last-pr` and never blocks the turn.

**After the PR: keeping CI green is the loop's, not the human's.** CI runs async on GitHub, so no Stop hook can wait on it — watching + fixing a red run is multi-step loop work, owned by `loop-run`, not a fire-and-forget hook. A red run is reversible/local to fix (T0/T1), so the loop drives it to green autonomously and never leaves it or asks: the green gate runs `scripts/ci_watch.sh` (blocks on the run, prints the failing log on red), reopens the failing check as a rubric criterion, and loops — bounded by `max_iterations`. Only when it is *stuck* past the cap does it escalate (stuck = human judgment, not risk). Never disable/skip the check to force green — that is T2-class test/CI tampering. The **merge stays the one human gate.**

## Passing a gate (the one-shot marker)

When a T2 action is genuinely needed and a human has **explicitly approved** it:

1. The main agent writes `.claude/loop/.gate-approved` with three lines: `action=<class>` (`push`/`merge`/`publish`/`release`/`destructive`/`custom`, or `any`), `session_id=<current session>`, `ts=<epoch seconds>`.
2. Retry the command — the hook allows it while the marker matches the action class, the session, and is under 15 minutes old.
3. Remove the marker immediately after. It is single-use; never leave it lying around, and never write it without a human actually saying yes.

The marker is gitignored (`.claude/loop/.*`). Writing it *is* the act of recording that a human opened the gate — do not forge it to route around approval.

## Relation to the three principles

This is the orchestration layer over maker/checker: the upper model classifies and delegates T0/T1 freely; only T2 escalates. The `auditor` subagent (see `/loopy:loop-audit`) later checks that the loop actually held this line — no reversible step wrongly gated (over-confirmation), no T2 action taken without a gate (under-confirmation).
