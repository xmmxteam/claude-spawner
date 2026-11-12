#!/usr/bin/env bash
# Shared helpers for the launcher scripts. Source this file; do not execute it.
set -euo pipefail

WORKSPACE=${WORKSPACE:-/workspace}
STATE=${LAUNCHER_STATE:-$HOME/.launcher}
SESSIONS=$STATE/sessions
mkdir -p "$SESSIONS"

die() { echo "error: $*" >&2; exit 1; }

# All launcher-managed tmux sessions live on one dedicated socket.
tm() { tmux -L launcher "$@"; }
is_live() { tm has-session -t "=$1" 2>/dev/null; }

# Names must not start with "-" (they reach claude as an argument) and must not clash with the
# launcher and workspace tmux sessions that share the socket.
valid_name() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $1 != launcher && $1 != workspace ]]; }
reg_file() { echo "$SESSIONS/$1.env"; }

# Registry entries are shell-quoted var files: NAME DIR SID MODE WORKTREE DOCKER_HOST_ARG STATUS STARTED_ONCE CREATED
reg_load() {
  valid_name "$1" || die "invalid session name: $1"
  local f; f=$(reg_file "$1")
  [[ -f $f ]] || die "no such session: $1"
  # shellcheck disable=SC1090
  source "$f"
}

reg_save() {
  local f v; f=$(reg_file "$NAME")
  { for v in NAME DIR SID MODE WORKTREE DOCKER_HOST_ARG STATUS STARTED_ONCE CREATED; do
      printf '%s=%q\n' "$v" "${!v-}"
    done; } > "$f.tmp"
  mv "$f.tmp" "$f"
}

# Delete the entries of sessions that finished or failed and were last changed more than
# PRUNE_DAYS ago. Running sessions are never touched. The entrypoint calls this every 30 seconds.
PRUNE_DAYS=30
prune_sessions() {
  local f n
  while IFS= read -r -d '' f; do
    n=$(basename "$f" .env)
    valid_name "$n" || continue
    if ( reg_load "$n"; [[ $STATUS == finished || $STATUS == failed ]] ) && ! is_live "$n"; then
      rm -f "$f"
    fi
  done < <(find "$SESSIONS" -maxdepth 1 -name '*.env' -mmin +$((PRUNE_DAYS * 24 * 60)) -print0)
  return 0
}

# Start (or restart) the tmux session for a registered entry.
start_session() {
  local cmd
  cmd="session-wrapper $(printf %q "$1")"
  (
    reg_load "$1"
    # DOCKER_HOST_ARG is "", "default" (the container's DOCKER_HOST) or "dind". Both are resolved
    # here, not at launch, so a resumed session follows the current environment.
    local url=
    case $DOCKER_HOST_ARG in
      ""|default) ;;
      dind) url=${DIND_DOCKER_HOST:-tcp://dind:2375} ;;
      *) url=$DOCKER_HOST_ARG ;; # entries written before the literal names existed hold a URL
    esac
    [[ -n $url ]] && cmd="env DOCKER_HOST=$(printf %q "$url") $cmd"
    tm new-session -d -s "$NAME" -c "$DIR" "$cmd"
  )
}
