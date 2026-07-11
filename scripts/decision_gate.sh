#!/usr/bin/env bash
# loopy decision gate (PreToolUse hook, matcher: Bash).
#
# Enforces the loop-engineering decision doctrine: an action that is IRREVERSIBLE
# or HIGH-IMPACT (T2) needs a human gate; reversible/local work (T0/T1) never does.
# This hook mechanically blocks the T2 class so the doctrine cannot be forgotten.
#
# Scope: acts in EVERY project, loop or not (loop-independent since 0.14.0). The
# T2 doctrine — merge/publish/protected-branch push is a human gate — holds
# machine-wide, so the backstop must too; an honest agent outside a loop forgets
# it just as easily. Any parse doubt exits 0 (fail-open). Config still reads
# `.claude/loop/loop.config.md` when present; absent config = the safe defaults
# (protected: main master, gate_push: false).
#
# T2 default set (high-signal, low false-positive):
#   - package publish (npm/pnpm/yarn/bun publish)
#   - release/submit  (gh release create, eas submit)
#   - PR merge        (gh pr merge -> merge into a protected branch)
#   - git push to a protected branch (protected_branches, default "main master")
#   - git force-push and git tag push (rewrite/publish remote history)
#   - all git push when gate_push:true (direct-to-main repos)
#   - catastrophic delete (rm -rf of / ~ $HOME)
#   - any project-specific `extra_gates:` regex from loop.config.md
# Reversible/local commands (edits, tests, local commits, WORK-branch push) pass.
#
# Bypass: a valid one-shot marker `.claude/loop/.gate-approved` (written by the main
# agent only AFTER explicit human approval) authorizes the matching action class for
# the current session within a TTL. The agent removes it right after the approved
# command. gitignored by the existing `.claude/loop/.*` rule.
#
# Deny uses the official hooks schema (permissionDecision="deny") and exits 0 —
# deny JSON is only parsed on exit 0.

set -u

# shellcheck source=scripts/hook_lib.sh
. "$(cd "$(dirname "$0")" && pwd)/hook_lib.sh"
hook_init

hook_debug decision_gate

CMD="$(bash_cmd)"
[ -n "$CMD" ] || exit 0

CUR_SID="$(json_str session_id)"

# --- config (the only stack-dependent knobs; accessors: hook_lib.sh) ---
GATE_PUSH="$(cfg_flag gate_push false)"
EXTRA_GATES="$(config_field extra_gates)"
case "$EXTRA_GATES" in TODO*|'<'*) EXTRA_GATES="" ;; esac
PROT_RE="$(protected_re)"

# --- one-shot human-approval marker ---
# gate_approved (hook_lib.sh) decides whether .gate-approved authorizes a class
# for this session within the TTL — shared with tamper_gate so the approval
# contract can't drift between the two gates.

deny() {
  # $1 = fixed tag, $2 = action class — both chosen below, safe to interpolate.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"loopy decision_gate: T2 (irreversible / high-impact) action blocked (%s). This is a human gate — do NOT work around it. Stop, summarize in .claude/loop/review.md, and get explicit human approval. Once approved, write .claude/loop/.gate-approved (action=%s, session_id, ts), retry, then remove the marker."}}\n' "$1" "$2"
  exit 0
}

# gate <class> <tag>: block unless the human approved this class.
gate() { gate_approved "$1" || deny "$2" "$1"; }

# 1. package publish
if printf '%s' "$CMD" | grep -Eq "${SEG}(npm|pnpm|yarn|bun)[[:space:]]+publish([[:space:]]|\$)"; then
  gate publish "package publish"
fi

# 2. release / store submit
if printf '%s' "$CMD" | grep -Eq "${SEG}(npx[[:space:]]+)?eas[[:space:]]+submit([[:space:]]|\$)"; then
  gate release "eas submit"
fi
if printf '%s' "$CMD" | grep -Eq "${SEG}gh[[:space:]]+release[[:space:]]+create([[:space:]]|\$)"; then
  gate release "gh release create"
fi

# 3. PR merge into a protected branch
if printf '%s' "$CMD" | grep -Eq "${SEG}gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|\$)"; then
  gate merge "gh pr merge"
fi

# 4. git push family
if printf '%s' "$CMD" | grep -Eq "${SEG}git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*push([[:space:]]|\$)"; then
  # gate_push:true -> every push is a gate
  if [ "$GATE_PUSH" = "true" ]; then
    gate push "git push (gate_push=true)"
  fi
  # force-push -> rewrites remote history (high-impact). Match -f/--force as a
  # whole arg token in ANY position — `git[[:space:]]+push[[:space:]]` consumes the
  # only space before the first arg, so a leading `[[:space:]]-f` misses `push -f`.
  if printf '%s' "$CMD" | grep -Eq "git[[:space:]]+push[[:space:]]+([^[:space:]]+[[:space:]]+)*(--force([[:space:]=]|\$)|--force-with-lease|-f([[:space:]]|\$))"; then
    gate push "git force-push"
  fi
  # force-refspec form: `git push origin +main` / `+refs/heads/x` force-pushes a
  # ref with no -f/--force flag. A `+`-prefixed refspec token (space, `+`, then a
  # non-flag char) is a force-push of ANY branch -> same T2 as --force above.
  if printf '%s' "$CMD" | grep -Eq "git[[:space:]]+push[[:space:]].*[[:space:]][+][^[:space:]-]"; then
    gate push "git force-push (+refspec)"
  fi
  # tag push -> publishing a release ref
  if printf '%s' "$CMD" | grep -Eq "git[[:space:]]+push[[:space:]].*(--tags([[:space:]]|\$)|refs/tags/)"; then
    gate release "git tag push"
  fi
  # push targeting a protected branch (space- or colon-delimited branch token,
  # or a fully-qualified refs/heads/<protected> refspec)
  if printf '%s' "$CMD" | grep -Eq "git[[:space:]]+push[[:space:]].*([[:space:]:](${PROT_RE})|refs/heads/(${PROT_RE}))([[:space:]]|\$)"; then
    gate push "git push to protected branch"
  fi
fi

# 5. catastrophic delete: a WHOLE root or WHOLE home. A home SUBDIR
# (rm -rf ~/.cache) is reversible T1 and must pass — see .claude/loop/review.md.
#   /         : root — trailing space, '/', '*', or end     (rm -rf /, //, /*)
#   ~ /$HOME  : whole home only — optional single trailing '/' then space/end
#               (rm -rf ~, ~/, $HOME) but NOT ~/<subdir>
# The root/home target may sit in ANY operand position, not just first after the
# flags — `(...[[:space:]]+)?` skips leading safe operands so `rm -rf ./dist /`
# and a later `$VAR` expanding to `/` are still caught (honest stray-space footgun).
CATA_TGT='(/([[:space:]]|/|[*]|$)|(~|[$]HOME|[$][{]HOME[}])/?([[:space:]]|$))'
if printf '%s' "$CMD" | grep -Eq "${SEG}rm[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*([rR][a-zA-Z]*[fF]|[fF][a-zA-Z]*[rR])[a-zA-Z]*[[:space:]]+([^;&|]*[[:space:]]+)?${CATA_TGT}"; then
  gate destructive "catastrophic rm -rf/-fr"
fi

# 6. project-specific extra gates (opt-in regex; e.g. external endpoints, cost)
if [ -n "$EXTRA_GATES" ] && printf '%s' "$CMD" | grep -Eq "$EXTRA_GATES" 2>/dev/null; then
  gate custom "extra_gates match"
fi

exit 0
