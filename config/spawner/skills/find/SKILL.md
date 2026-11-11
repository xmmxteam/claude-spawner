---
name: find
description: Find repos in the workspace by words in the path
argument-hint: [words...]
disable-model-invocation: true
allowed-tools: Bash(find-project:*)
---
Run `find-project $ARGUMENTS` and show its output. With no words it lists every repo.
