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
# Usage: fleet [--watch [SECONDS]] [--swiftbar] [--focus PID] [--help]
#   --swiftbar emits SwiftBar/xbar plugin format (menubar title, ---, dropdown);
#   point a shim in your SwiftBar plugin folder at `fleet.sh --swiftbar`.
#   --focus raises the window hosting that session (wired to SwiftBar row clicks).
# Env:   FLEET_SESSIONS_DIR   override sessions dir (default ~/.claude/sessions; used by tests)

set -u
shopt -s nullglob

SESS_DIR="${FLEET_SESSIONS_DIR:-$HOME/.claude/sessions}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"   # absolute path for SwiftBar click actions

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
  fleet --swiftbar      SwiftBar/xbar plugin output (menubar title + dropdown)
  fleet --focus PID     raise the window hosting that session (SwiftBar row click)
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

# Read the sessions dir once. Sets globals:
#   ROWS  — sorted rows "status<TAB>pid<TAB>name<TAB>branch<TAB>cwd<TAB>idle" (all fields non-empty)
#   LIVE / STALE — counts
collect() {
  local now_ms f rows=''
  LIVE=0; STALE=0; ROWS=''
  now_ms=$(( $(date +%s) * 1000 ))

  for f in "$SESS_DIR"/*.json; do
    local pid name status kind updated cwd branch idle idle_str cwd_base key
    # One field per line, read one line each: an empty field stays an empty line.
    # (A tab/space delimiter is IFS-whitespace and would collapse empties, shifting columns.)
    { IFS= read -r pid; IFS= read -r name; IFS= read -r status
      IFS= read -r kind; IFS= read -r updated; IFS= read -r cwd
    } < <(jq -r '.pid,(.name//""),(.status//""),(.kind//""),(.updatedAt//0),(.cwd//"")' "$f" 2>/dev/null)

    [ -z "${pid:-}" ] && continue
    kill -0 "$pid" 2>/dev/null || { STALE=$(( STALE + 1 )); continue; }
    LIVE=$(( LIVE + 1 ))

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
    rows+=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$key" "$status" "$pid" "$name" "$branch" "$cwd_base" "$idle_str")$'\n'
  done

  [ -n "$rows" ] && ROWS="$(printf '%s' "$rows" | sort -t$'\t' -k1,1n -k4,4 | cut -f2-)"
}

render() {
  collect

  if [ "$LIVE" -eq 0 ]; then
    printf 'No live Claude Code sessions.'
    [ "$STALE" -gt 0 ] && printf '  (%d stale)' "$STALE"
    printf '\n'
    return
  fi

  {
    printf 'STATUS\tPID\tNAME\tBRANCH\tCWD\tIDLE\n'
    printf '%s\n' "$ROWS"
  } | column -t -s$'\t' | colorize

  printf -- '-- %d live, %d stale\n' "$LIVE" "$STALE"
}

# SwiftBar/xbar plugin format: menubar title, "---", one dropdown line per session.
render_swiftbar() {
  collect
  local w=0 b=0 status pid name branch cwd idle icon color title=''

  if [ -n "$ROWS" ]; then
    while IFS=$'\t' read -r status pid name branch cwd idle; do
      case "$status" in waiting) w=$(( w + 1 )) ;; busy) b=$(( b + 1 )) ;; esac
    done <<< "$ROWS"
  fi

  [ "$w" -gt 0 ] && title="⏳$w"
  [ "$b" -gt 0 ] && title="${title:+$title }▶$b"
  [ -z "$title" ] && title="🤖$LIVE"
  printf '%s\n---\n' "$title"

  if [ "$LIVE" -eq 0 ]; then
    printf 'No live Claude Code sessions\n'
  else
    while IFS=$'\t' read -r status pid name branch cwd idle; do
      case "$status" in
        waiting) icon='⏳'; color='orange' ;;
        busy)    icon='▶';  color='green' ;;
        idle)    icon='○';  color='gray' ;;
        *)       icon='·';  color='gray' ;;
      esac
      printf '%s %s — %s · %s · %s | color=%s bash="%s" param1=--focus param2=%s terminal=false refresh=false\n' \
        "$icon" "$name" "$cwd" "$branch" "$idle" "$color" "$SELF" "$pid"
    done <<< "$ROWS"
  fi

  printf -- '---\n%d live · %d stale\n' "$LIVE" "$STALE"
}

# Raise the window hosting session $1 (wired to SwiftBar row clicks).
# Walks the session PID's ancestors to the owning .app bundle — works for
# VS Code/Cursor including AppTranslocation paths, no hardcoded CLI location —
# then opens the session's cwd through the app's bundled CLI: an already-open
# folder focuses its existing window. Window-level only: VS Code exposes no
# external API to focus a specific terminal *tab* inside the window.
focus_session() {
  local pid=$1 f cwd cur app='' cli path
  f="$SESS_DIR/$pid.json"
  [ -f "$f" ] || { echo "fleet: no session file for pid $pid" >&2; exit 1; }
  kill -0 "$pid" 2>/dev/null || { echo "fleet: session $pid is not alive" >&2; exit 1; }
  cwd=$(jq -r '.cwd//""' "$f" 2>/dev/null)

  cur=$pid
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    cur=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
    [ -z "$cur" ] && break
    [ "$cur" -le 1 ] && break
    path=$(ps -o comm= -p "$cur" 2>/dev/null)   # full executable path on macOS
    case "$path" in
      */Contents/MacOS/*) app="${path%%/Contents/MacOS/*}"; break ;;
    esac
  done
  [ -n "$app" ] || { echo "fleet: no app window found for pid $pid (bg session?)" >&2; exit 1; }

  for cli in code cursor; do   # VS Code ships bin/code, Cursor ships both
    if [ -n "$cwd" ] && [ -x "$app/Contents/Resources/app/bin/$cli" ]; then
      exec "$app/Contents/Resources/app/bin/$cli" "$cwd"
    fi
  done
  exec osascript -e "tell application \"$app\" to activate"   # other terminal apps: app-level raise
}

case "${1:-}" in
  -h|--help)  usage ;;
  --watch)    secs="${2:-2}"; while :; do clear; render; sleep "$secs"; done ;;
  --swiftbar) render_swiftbar ;;
  --focus)    [ -n "${2:-}" ] || { usage; exit 2; }; focus_session "$2" ;;
  '')         render ;;
  *)          usage; exit 2 ;;
esac
