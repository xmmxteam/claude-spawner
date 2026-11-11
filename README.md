# claude-spawner

Headless Claude Code in Docker, controlled from the Claude mobile app via Remote Control.

An always-on **launcher** session (restricted to the scripts below and read-only `gh repo list` and `gh org list`) starts one `claude --remote-control` session per project. Sessions run in tmux, are tracked in a registry on the volume, and are resumed on container restart unless they were exited, stopped or failed. A second always-on session, `workspace`, runs an unrestricted `claude remote-control` server so the container appears as a device in the Claude app.

## Run

```bash
cp .env.example .env        # fill in tokens
mkdir secrets               # optional: kubeconfig, talosconfig
docker compose up -d --build
```

Open http://localhost:7681 (ttyd), run `claude`, and complete `/login`. The launcher starts within 30 seconds and appears in the Claude app as "Claude Spawner". Ask it to open a project.

Re-login after expiry uses the same ttyd page. Do not expose port 7681 beyond localhost, LAN or a VPN.

## Scripts (`bin/`)

| Script | Purpose |
| --- | --- |
| `launch-session <project> [--name N] [--mode default\|bypass] [--worktree] [--docker-host dind\|default]` | Start a session. Default mode is bypass. Names must start with a letter or digit, and `launcher` and `workspace` are reserved. |
| `list-sessions`, `stop-session <name>`, `resume-session <name>\|--all-running` | Manage sessions. `resume-session` also restarts a `failed` one. |
| `find-project <words...>` | Find repos under `/workspace` by words in the path. |
| `launcher-version` | Print the claude-spawner version and the versions of the installed tools. |
| `clone-repo <owner/repo\|https URL> [dest]` | Clone into `/workspace/<dest>` (default `<owner>/<repo>`), allowed hosts only. `dest` may not contain hidden components such as `.claude`. |
| `session-wrapper`, `start-launcher`, `start-workspace`, `trust-dir`, `entrypoint` | Internal. `trust-dir` pre-accepts Claude's trust dialog for a directory. |

## Versioning

Every push to `main` that CI builds publishes `ghcr.io/xmmxteam/claude-spawner` with the tags `YYYY.MM.DD.N`, `sha-<short commit>` and `latest`. `N` is the workflow run number, so versions sort in build order. The version, commit and build time are image labels and the env vars `SPAWNER_VERSION`, `SPAWNER_COMMIT` and `SPAWNER_BUILT`. Local builds report `dev`.

The build also saves the stamp and the tool versions to `/opt/launcher/version.txt`, and fails if a tool is missing. `bin/start-launcher` adds that file to the launcher's system prompt, so the launcher can report its version without running a command. A resumed Claude session ignores a new system prompt, so the launcher starts a new conversation whenever the image version changes instead of resuming. `launcher-version` prints the same report with the versions installed now, which can differ for Rust because the `claude` user can update toolchains.

## Docker

Sessions use a remote Docker host over SSH when `DEFAULT_DOCKER_HOST` (`ssh://user@host[:port]`) is set, and the local dind sidecar otherwise. `DIND_DOCKER_HOST` always points at dind. The fall back to dind when the remote host is unreachable is an instruction in `config/container-CLAUDE.md`, not code. `launch-session --docker-host dind` pins one session to dind, and `default` uses the container's `DOCKER_HOST`.

If `secrets/docker-ssh-key` exists, the entrypoint installs it into `~/.ssh` along with the optional `secrets/docker-known-hosts` and writes an ssh config entry for the host. Without the key, the container's existing SSH setup is used. A known_hosts entry for a non-default port must be written as `[host]:port`, and the remote user needs `docker` on its PATH and access to the Docker socket.

Bind mounts (`-v`, compose `./path`) resolve on the remote host, not in this container, and the `workspace` volume is shared only with dind. Use dind for anything that mounts `/workspace`.

## Notes

- The launcher is locked down by `--tools Bash` in `bin/start-launcher` and the root-owned `config/launcher-settings.json`. Managed settings are not used because they would also restrict project sessions.
- Sessions hold broad credentials and run in bypass mode by default. The container is the only sandbox.
- Unverified: whether `claude --remote-control` needs a TTY (tmux provides one), whether `/exit` returns exit code 0 (a non-zero exit marks the session `failed` rather than `finished`), whether `defaultMode: dontAsk` in `config/launcher-settings.json` denies commands outside the allowlist, whether `skipDangerousModePermissionPrompt` has any effect, and resume after a worktree switch. `--permission-mode dontAsk` itself is accepted by `claude`.
