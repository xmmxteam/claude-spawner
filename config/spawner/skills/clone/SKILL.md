---
name: clone
description: Clone a repository into the workspace
argument-hint: <owner/repo or https URL> [dest]
disable-model-invocation: true
allowed-tools: Bash(clone-repo:*)
---
Run `clone-repo $ARGUMENTS`. If no destination is given, use the default clone locations from your instructions. Reply in one short line with where it was cloned.
