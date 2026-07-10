---
name: loop-init
description: Scaffold .claude/loop/ state files and detect this project's test/lint/build commands
disable-model-invocation: true
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
3. **Create the files** from the templates in `references/templates.md` immediately, using detected values and TODOs. Goal: use the command arguments if given, else `TODO: define the goal`; derive `branch:` from it (`<type>/<slug>`, see templates.md). Print one warning line per TODO written.
4. **Gitignore:** ensure the project `.gitignore` contains the line `.claude/loop/.*` (create `.gitignore` if missing; skip if the line already exists). Non-hidden loop files are MEANT to be committed (team sharing, session recovery).
5. **Interactive refinement (optional):** only AFTER the files exist, and only if this session is clearly interactive (a human typed the command and can reply), you may ask ONE question to fill the remaining TODOs, then update the files. If in doubt, skip — TODOs are the designed outcome. Never end the turn with questions instead of created files.
6. **Report:** created paths + remaining TODOs + the detected implementer + next steps — try `/loopy:loop-run --verify-only` first (grade only), then `/loopy:loop-run`. If `implementer: claude` because no Codex CLI was found, note: install the Codex CLI and run `codex login`, then set `implementer: codex` in loop.config.md to enable the cross-model maker/checker split.
