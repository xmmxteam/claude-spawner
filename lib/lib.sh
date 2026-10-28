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

valid_name() { [[ $1 =~ ^[A-Za-z0-9._-]+$ ]]; }
reg_file() { echo "$SESSIONS/$1.env"; }

# Registry entries are shell-quoted var files: NAME DIR SID MODE WORKTREE DOCKER_HOST_ARG STATUS STARTED_ONCE
reg_load() {
  valid_name "$1" || die "invalid session name: $1"
  local f; f=$(reg_file "$1")
  [[ -f $f ]] || die "no such session: $1"
  # shellcheck disable=SC1090
  source "$f"
}

reg_save() {
  local f v; f=$(reg_file "$NAME")
  { for v in NAME DIR SID MODE WORKTREE DOCKER_HOST_ARG STATUS STARTED_ONCE; do
      printf '%s=%q\n' "$v" "${!v-}"
    done; } > "$f.tmp"
  mv "$f.tmp" "$f"
}

# Start (or restart) the tmux session for a registered entry.
start_session() {
  local cmd
  cmd="session-wrapper $(printf %q "$1")"
  (
    reg_load "$1"
    [[ -n $DOCKER_HOST_ARG ]] && cmd="env DOCKER_HOST=$(printf %q "$DOCKER_HOST_ARG") $cmd"
    tm new-session -d -s "$NAME" -c "$DIR" "$cmd"
  )
}
