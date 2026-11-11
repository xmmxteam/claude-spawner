# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Docker image plus compose stack that runs headless Claude Code, controlled from the Claude mobile app through Remote Control. There is no application code, only bash scripts, config and a Dockerfile. There are no tests or linters in the repo.

## Commands

- Run the stack: `cp .env.example .env`, fill it in, then `docker compose up -d --build`. The ttyd terminal is at `http://localhost:7681`, where you run `claude` and `/login` once.
- Build only: `docker build -t claude-spawner:local .`. Downloaded tools (kubectl, Go, Node and so on) resolve to "latest" at build time and stay cached until you use `--no-cache` or change the matching `--build-arg`.
- Scripts under `bin/` are bash. Check them with `bash -n` and `shellcheck` if it is installed.
- CI (`.github/workflows/image.yaml`) builds and pushes `ghcr.io/xmmxteam/claude-spawner` on every push to `main` that changes a non-markdown file. It tags the image `YYYY.MM.DD.N` (N is the run number), `sha-<short commit>` and `latest`, and passes `VERSION`, `GIT_SHA` and `BUILD_DATE` as build args. The final Dockerfile layer turns them into labels, `SPAWNER_*` env vars and `/opt/launcher/version.txt` (the output of `bin/spawner-version`), which `bin/start-launcher` appends to the launcher's system prompt. If you add a tool to the image, add it to `bin/spawner-version`. If you add a script the launcher may run, give it a skill under `config/spawner/skills/` too.

## Architecture

`bin/entrypoint` is the container entrypoint. It seeds `~/.claude` settings from `config/`, installs the Hindsight and Codex plugins once, configures git credentials, and starts tmux and ttyd. Then it loops every 30 seconds. Once a Claude login exists, it keeps two tmux sessions alive:

- `launcher` runs `bin/start-launcher`. It is a Claude session named "Claude Spawner" that is restricted to the `Bash` tool and to the scripts allowed in `config/launcher-settings.json`. Its behaviour is set by `config/launcher-prompt.md`.
- `workspace` runs `bin/start-workspace`.

The launcher starts one project session per project with `bin/launch-session`. Each project session is a tmux session running `bin/session-wrapper`, which runs `claude --remote-control <name>`.

All tmux sessions use the dedicated socket `tmux -L launcher`, through the `tm` helper in `lib/lib.sh`.

### Session registry

State lives on the home volume under `~/.launcher/` (`$STATE`). Each session has a shell-quoted var file at `sessions/<name>.env`, written by `reg_save` and read by `reg_load` in `lib/lib.sh`. The fields are `NAME DIR SID MODE WORKTREE DOCKER_HOST_ARG STATUS STARTED_ONCE`. If you add a field, add it to the `reg_save` loop and to `launch-session`. `DOCKER_HOST_ARG` holds the literal `dind` or `default` (or empty), and `start_session` resolves it on every start.

`STATUS` drives restart behaviour. A container shutdown kills sessions before the wrapper can mark them, so it stays `running` and the next boot resumes the session through `resume-session --all-running`. Claude exiting with code 0 sets `finished` and any other code sets `failed`. Neither is resumed on boot, but `resume-session <name>` restarts a `failed` one. `session-wrapper` and `start-launcher` resume only when a transcript `$HOME/.claude/projects/*/$SID.jsonl` exists.

### Layout and conventions

- Scripts in `bin/` are copied to `/opt/launcher/bin` and put on `PATH`. They source `/opt/launcher/lib/lib.sh`, which sets `set -euo pipefail` and defines `die`, `tm`, `is_live`, the registry helpers and `start_session`.
- `config/container-CLAUDE.md` is copied to `~/.claude/CLAUDE.md` inside the container on every boot, so it is the instructions file for sessions running there. This `CLAUDE.md` is for working on this repo.
- `config/user-settings.json` is merged over the container's `~/.claude/settings.json` on boot, and the seed keys win.
- The launcher is locked down by `--tools Bash` in `bin/start-launcher` plus the root-owned `config/launcher-settings.json`. Managed settings are deliberately not used, because they would also restrict project sessions. Keep the launcher's allowed commands in sync with the scripts in `bin/`.
- `clone-repo` only clones from hosts in `ALLOWED_GIT_HOSTS` and refuses destinations with hidden path components, because a cloned `.claude/settings.json` would be loaded by the launcher or a project session. `launch-session --docker-host` accepts only `dind` or `default`, so the launcher cannot point a session at an arbitrary host. Session names are checked by `valid_name` in `lib/lib.sh`.

### Dockerfile

Download tools are fetched in separate parallel stages that copy only `/out` into the final image. The final stage runs as user `claude` (UID 1000), because bypass-permissions mode is refused as root. Launcher files are copied last so edits to scripts rebuild only the final layers. Node 26 needs `libatomic1` in both the fetch stage and the final image.

### Compose

`DOCKER_HOST` defaults to `DEFAULT_DOCKER_HOST` (an `ssh://` URL) and falls back to the privileged `docker:dind` sidecar, which is always reachable at `DIND_DOCKER_HOST`. Never write the remote host's address into the repo, only the env var names. `bin/entrypoint` sets up the SSH key and config when `secrets/docker-ssh-key` exists. The `home`, `workspace` and `dind-data` volumes persist logins, repos and images. `./secrets` is mounted read-only at `/secrets` for the kubeconfig, talosconfig and `hindsight-coding-agent.json`.
