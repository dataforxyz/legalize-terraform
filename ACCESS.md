# Legalize Server — Access Guide

A small dev box for the legalize-pipeline open-source project.
Hosted on GCP (`legalize-server-26042598`), Sao Paulo region.

## Login

```sh
ssh dev@34.39.246.254
```

That's it. Public-key auth only — no password. If your key is in the server's
`~/.ssh/authorized_keys`, you're in. The server admin adds keys via the
Terraform variable `ssh_authorized_keys` (each redeploy, all listed keys
replace the set).

To request access, send the server admin your public key (one line, e.g.
`ssh-ed25519 AAAA... you@laptop`). Generate one with:

```sh
ssh-keygen -t ed25519 -C "you@laptop"
cat ~/.ssh/id_ed25519.pub   # send this line
```

## What's installed

- **Ubuntu 22.04 LTS**, 8 vCPU, 32 GB RAM, 60 GB disk
- **Docker** + Docker Compose plugin (`dev` user is in the `docker` group, no sudo needed)
- **Node.js 20 LTS** + npm
- **Python**: system `python3` + [`uv`](https://github.com/astral-sh/uv) for venvs
- **git**, **gh** (GitHub CLI), **glab** (GitLab CLI), **make**, **tmux**, **jq**
- **Claude Code** (`claude`) — Anthropic's CLI assistant
- **OpenAI Codex CLI** (`codex`)
- Both AI tools are auto-updated nightly at 06:00 UTC via cron

## What's already cloned

```
/home/dev/legalize-pipeline   # branch: feat/mx-scaffold
                              # https://github.com/jaredgoldman/legalize-pipeline
```

## Common things to do

```sh
# Pull latest pipeline changes
cd ~/legalize-pipeline && git pull

# Spin up an isolated Python env for the pipeline
cd ~/legalize-pipeline && uv venv && uv sync

# Run something in Docker
docker run --rm -it python:3.12 bash

# Persistent terminal sessions (survive disconnects)
tmux new -As work        # create or reattach session named "work"
# detach: Ctrl-b then d

# Use Claude Code in the pipeline repo
cd ~/legalize-pipeline && claude --dangerously-skip-permissions

# Use Codex CLI
cd ~/legalize-pipeline && codex --dangerously-bypass-approvals-and-sandbox
```

## Things to know

- Server has a **public IP** but only port 22 (SSH) is open to the world. No
  HTTP/HTTPS exposed — if you need to expose a web service, ask the admin to
  open the port or use an SSH tunnel:
  `ssh -NL 8080:localhost:8080 dev@34.39.246.254`
- All work as the **`dev`** user. `sudo` works passwordless if you need it.
- Be considerate with disk usage — only 60 GB total. `df -h` to check.
- Cost-aware: the box is always on. Tell the admin if you'd like it stopped
  outside work hours.

## If something breaks

- Check Docker: `docker ps`, `docker logs <name>`
- Tool versions: `claude --version`, `codex --version`, `node --version`
- Tool update history: `cat ~/.tool-updates/cron.log`
- Server-side log: `sudo tail -f /var/log/legalize-startup.log` (boot-time only)
