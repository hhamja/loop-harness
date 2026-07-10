#!/usr/bin/env bash
# fleet — at-a-glance view of every LIVE Claude Code session on this machine.
#
# Claude Code already writes each session's state to ~/.claude/sessions/<PID>.json
# (name, status busy|waiting|idle, cwd, updatedAt) and rewrites it on every state
# change. So this is just: read that dir, drop sessions whose PID is dead, and
# print the rest waiting-first. No hooks, no transcript parsing. Read-only.
#
# The data is machine-wide regardless of where you run this from — a session in
# any project shows up. Symlink it onto PATH to run `fleet` from anywhere.
#
# Usage: fleet [--watch [SECONDS]] [--help]
# Env:   FLEET_SESSIONS_DIR   override sessions dir (default ~/.claude/sessions; used by tests)

set -u
shopt -s nullglob

SESS_DIR="${FLEET_SESSIONS_DIR:-$HOME/.claude/sessions}"

# ANSI colors only on a real terminal; empty (and colorize() cats through) otherwise.
if [ -t 1 ]; then
  C_WAIT=$'\033[1;33m'; C_BUSY=$'\033[32m'; C_IDLE=$'\033[2m'; C_RST=$'\033[0m'
else
  C_WAIT=''; C_BUSY=''; C_IDLE=''; C_RST=''
fi

usage() {
  cat <<'EOF'
fleet — live Claude Code sessions across all projects, waiting-for-input first.

  fleet                 print once
  fleet --watch [SECS]  refresh every SECS seconds (default 2); Ctrl-C to quit
  fleet --help          this help

Env: FLEET_SESSIONS_DIR   override the sessions dir (default ~/.claude/sessions)
EOF
}

human_idle() { # $1 = seconds -> "2s" / "3m" / "1h"
  local s=$1
  if   [ "$s" -lt 60 ];   then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm' $(( s / 60 ))
  else                         printf '%dh' $(( s / 3600 ))
  fi
}

status_key() { # sort order: waiting(bottleneck) first, then busy, idle, unknown
  case "$1" in
    waiting) printf 0 ;; busy) printf 1 ;; idle) printf 2 ;; *) printf 3 ;;
  esac
}

# Color each aligned row by its leading STATUS word (whole-row emphasis).
colorize() {
  if [ -z "$C_WAIT" ]; then cat; return; fi
  local line
  while IFS= read -r line; do
    case "$line" in
      waiting*) printf '%s%s%s\n' "$C_WAIT" "$line" "$C_RST" ;;
      busy*)    printf '%s%s%s\n' "$C_BUSY" "$line" "$C_RST" ;;
      idle*)    printf '%s%s%s\n' "$C_IDLE" "$line" "$C_RST" ;;
      *)        printf '%s\n' "$line" ;;
    esac
  done
}

render() {
  local now_ms live=0 stale=0 rows='' f
  now_ms=$(( $(date +%s) * 1000 ))

  for f in "$SESS_DIR"/*.json; do
    local pid name status kind updated cwd branch idle idle_str cwd_base key row
    # One field per line, read one line each: an empty field stays an empty line.
    # (A tab/space delimiter is IFS-whitespace and would collapse empties, shifting columns.)
    { IFS= read -r pid; IFS= read -r name; IFS= read -r status
      IFS= read -r kind; IFS= read -r updated; IFS= read -r cwd
    } < <(jq -r '.pid,(.name//""),(.status//""),(.kind//""),(.updatedAt//0),(.cwd//"")' "$f" 2>/dev/null)

    [ -z "${pid:-}" ] && continue
    kill -0 "$pid" 2>/dev/null || { stale=$(( stale + 1 )); continue; }
    live=$(( live + 1 ))

    [ -z "$name" ] && name='-'
    [ "$kind" = 'bg' ] && name="$name (bg)"
    [ -z "$status" ] && status='?'

    branch='-'
    if [ -n "$cwd" ]; then
      branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch='-'
      [ -z "$branch" ] && branch='-'
    fi

    idle_str='?'
    case "$updated" in
      ''|0|*[!0-9]*) : ;;  # missing / zero / non-numeric -> keep "?"
      *) idle=$(( (now_ms - updated) / 1000 )); [ "$idle" -lt 0 ] && idle=0
         idle_str=$(human_idle "$idle") ;;
    esac

    cwd_base='-'; [ -n "$cwd" ] && cwd_base=$(basename "$cwd")
    key=$(status_key "$status")
    row=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$key" "$status" "$pid" "$name" "$branch" "$cwd_base" "$idle_str")
    rows+="$row"$'\n'
  done

  if [ "$live" -eq 0 ]; then
    printf 'No live Claude Code sessions.'
    [ "$stale" -gt 0 ] && printf '  (%d stale)' "$stale"
    printf '\n'
    return
  fi

  # header + rows sorted by status-key then name, sort-key column stripped, aligned, colored.
  {
    printf 'STATUS\tPID\tNAME\tBRANCH\tCWD\tIDLE\n'
    printf '%s' "$rows" | sort -t$'\t' -k1,1n -k4,4 | cut -f2-
  } | column -t -s$'\t' | colorize

  printf -- '-- %d live, %d stale\n' "$live" "$stale"
}

case "${1:-}" in
  -h|--help) usage ;;
  --watch)   secs="${2:-2}"; while :; do clear; render; sleep "$secs"; done ;;
  '')        render ;;
  *)         usage; exit 2 ;;
esac
