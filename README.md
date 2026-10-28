# claude-launcher

Headless Claude Code in Docker, controlled from the Claude mobile app via Remote Control.

An always-on **launcher** session (restricted to six scripts) starts one `claude --remote-control` session per project. Sessions run in tmux, are tracked in a registry on the volume, and are resumed on container restart unless they were exited or stopped.

## Run

```bash
cp .env.example .env        # fill in tokens
mkdir secrets               # optional: kubeconfig, talosconfig
docker compose up -d --build
```

Open http://localhost:7681 (ttyd), run `claude`, and complete `/login`. The launcher starts within 30 seconds and appears in the Claude app as "launcher". Ask it to open a project.

Re-login after expiry uses the same ttyd page. Do not expose port 7681 beyond localhost, LAN or a VPN.

## Scripts (`bin/`)

| Script | Purpose |
| --- | --- |
| `launch-session <project> [--name N] [--mode default\|bypass] [--worktree] [--docker-host dind\|desktop\|tcp://h:p]` | Start a session. Default mode is bypass. |
| `list-sessions`, `stop-session <name>`, `resume-session <name>\|--all-running` | Manage sessions. |
| `find-project <words...>` | Find repos under `/workspace` by words in the path. |
| `clone-repo <owner/repo\|https URL> [dest]` | Clone into `/workspace/<dest>` (default `<owner>/<repo>`), allowed hosts only. |
| `session-wrapper`, `start-launcher`, `entrypoint` | Internal. |

## Notes

- The launcher is locked down by `--tools Bash` in `bin/start-launcher` and the root-owned `config/launcher-settings.json`. Managed settings are not used because they would also restrict project sessions.
- Sessions hold broad credentials and run in bypass mode by default. The container is the only sandbox.
- Unverified: whether `claude --remote-control` needs a TTY (tmux provides one), whether `/exit` returns a clean exit code, whether `--permission-mode dontAsk` and `skipDangerousModePermissionPrompt` behave as assumed, and resume after a worktree switch.
