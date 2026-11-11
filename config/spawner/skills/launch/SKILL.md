---
name: launch
description: Open a project in a new Claude Code session
argument-hint: <project words> [--name N] [--mode default|bypass] [--worktree] [--docker-host dind|default]
disable-model-invocation: true
allowed-tools: Bash(find-project:*), Bash(launch-session:*), Bash(clone-repo:*)
---
Open this project: $ARGUMENTS

Follow your usual steps: run find-project with the project words, then launch-session for the match. Pass only the options given above. Reply in one short line with the session name.
