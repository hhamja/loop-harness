# Memory Protocol (5 steps)

Purpose: turn failures into compounding, session-surviving rules. A failure that stops at step 1 is noise; the compounding value appears only when an entry reaches step 5.

> Not everything a failure teaches is a durable rule. A *rejected approach* ("tried X, verifier still failed") is run-scoped episodic state — it belongs in state.md's `## Approaches tried`, pruned when the criterion passes. A *distilled rule* is a cross-run lesson that outlives the criterion — it belongs here in memory.md. Do not promote a one-off dead end into a distilled rule.

| Step | Name | What to write |
|---|---|---|
| 1 | fail | What was attempted, the exact error/symptom, command + output snippet |
| 2 | investigate | Root-cause hypothesis and how you checked it |
| 3 | verify | The hypothesis confirmed as fact (reproduced or disproved) |
| 4 | distill | The general rule, phrased so a future session can apply it without this context |
| 5 | consult | Every loop-run reads `## Distilled rules` BEFORE cycle 1 (loop-run does this automatically) |

## File layout (memory.md)

- `## Distilled rules (consult before every cycle)` stays at the TOP — one bullet per rule, each still carrying its `[plugin]`/`[project]` tag.
- `## Raw log` below holds in-progress entries (steps 1-3). When it exceeds 200 lines, compress it: drop resolved entries whose rule was distilled, merge duplicates. Never touch the distilled section while compressing.

## Entry template (Raw log)

```markdown
### [project] R3 test flaky
- fail: `npm test` exited 1 on 2nd run; error: EADDRINUSE :3000
- investigate: suspected two suites bind the same port; checked with lsof during run
- verify: reproduced — health.test and server.test both bind :3000 concurrently
- distill: -> moved to Distilled rules: "[project] serialize suites that bind ports, or randomize test ports"
```

An entry that cannot reach `verify` stays in the raw log as an open question — do not distill unverified hypotheses.

## Tag rules ([plugin] / [project]) — mandatory

- `[plugin]`: defect or notable behavior of the loopy itself (hook not firing, agent tool dropped, command misparsed, env var missing).
- `[project]`: defect of the target project (failing test, missing dependency, misconfigured build).
- Never distill across tags — a `[project]` fact must not become a `[plugin]` rule or vice versa. This keeps harness lessons portable between projects.
- Untagged entries are protocol violations; tag them when seen.
