# codex implementer procedure

The `codex` path of the loop-run Implement step. One FRESH `codex exec` per cycle — never `resume`; the prompt is rebuilt from disk each cycle (memory lives on disk, not in context).

1. Write `.claude/loop/.codex-prompt` with: the goal (goal.md); each unresolved criterion verbatim with its verification command; the last verifier failure reasons; the `## Approaches tried (rejected)` entries for those criteria from state.md; the `## Distilled rules` section of memory.md; then these fixed guardrails — "Do NOT modify anything under `.claude/loop/` — loop state belongs to the orchestrator. Do NOT run git commit or git push. Do NOT re-propose any approach listed under 'Approaches tried' — it already failed. Work only toward the listed criteria; make the smallest change that could pass them. End your reply with the list of files you changed."
2. Run it as ONE Bash call with a generous timeout (10 min — Codex edits can take minutes; the default 2-min Bash timeout would kill it mid-edit). Splice a non-empty `codex_args:` from loop.config.md in before the `-`:

   ```bash
   codex exec --full-auto --skip-git-repo-check --output-last-message .claude/loop/.codex-last - < .claude/loop/.codex-prompt > .claude/loop/.codex-log 2>&1
   ```

3. Read ONLY `.claude/loop/.codex-last`. NEVER read `.codex-log` — it is a human debugging artifact and would flood your context.
4. If the command exits non-zero: retry the identical command once. If it fails again, implement this cycle yourself (claude path) and record "codex exec failed, fell back to claude (cycle N)" in state.md and memory.md. Codex stays the implementer for the next cycle (the preflight verdict stands).
