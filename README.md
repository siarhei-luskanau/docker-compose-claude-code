# Claude Code in Docker Compose, backed by a remote Ollama server

Runs Claude Code inside an isolated Docker Compose container, using the
stock `node:22-slim` image (no custom Dockerfile - all setup happens at
container start via `entrypoint.sh`), and points it at a **remote** Ollama
server for inference instead of Anthropic's API, per the
[official manual setup](https://docs.ollama.com/integrations/claude-code#manual-setup).

## Prerequisites

- Docker and Docker Compose.
- A reachable Ollama server (remote host, tunnel, etc.) with the target
  model already pulled.

## Setup

1. Copy the env file and edit it:

   ```bash
   cp .env.example .env
   ```

2. Set `HOST_WORKDIR` to the **absolute path on your host machine** that you
   want Claude Code to operate on. It can be anywhere on the filesystem, not
   just this repo:

   ```
   HOST_WORKDIR=/Users/you/code/some-project
   ```

   The container refuses to start if this is unset (`entrypoint.sh` checks
   it and `docker-compose.yml` fails fast on the bind mount too).

3. Set `ANTHROPIC_BASE_URL` to your remote Ollama server's URL (e.g.
   `http://ollama-host.example.com:11434`, or a tunnel URL such as an ngrok
   address).

4. Set `ANTHROPIC_MODEL` (and the `ANTHROPIC_DEFAULT_*_MODEL` tier
   variables) to a model tag that **already exists** on that remote server.
   Confirm with:

   ```bash
   ollama list
   ```

   run against the remote server (e.g. `OLLAMA_HOST=http://ollama-host.example.com:11434 ollama list`,
   or by SSHing into the host running Ollama). Claude Code fails outright if
   the tag doesn't match precisely - `qwen3-coder:30b` and `qwen3-coder:30b-q4`
   are different tags.

   Note: if `ANTHROPIC_BASE_URL` is a tunnel (e.g. ngrok) on the free tier,
   the URL can change whenever the tunnel restarts. If requests start
   failing, check whether the tunnel URL changed and update `.env`.

5. Leave `ANTHROPIC_API_KEY` present but **empty** - Claude Code checks for
   this variable, and a real key would take precedence over the Ollama base
   URL.

## Running

```bash
docker compose run --rm claude-code
```

This drops you straight into an interactive Claude Code session rooted at
`/workspace` (your `HOST_WORKDIR`), launched with
`--dangerously-skip-permissions` so it never prompts for per-action
approval.

To pass arguments to `claude` instead of the default interactive session:

```bash
docker compose run --rm claude-code -p "summarize this repo"
```

You can also override `HOST_WORKDIR` per invocation without editing `.env`:

```bash
HOST_WORKDIR=/some/other/path docker compose run --rm claude-code
```

## What persists across runs

Three named volumes:

- `claude_config` -> `/root/.claude` - Claude Code's auth, settings, and
  history.
- `npm_global` -> `/usr/local/lib/node_modules` - the installed
  `@anthropic-ai/claude-code` package, so it isn't re-downloaded every run.
- `apt_cache` -> `/var/cache/apt` - downloaded `.deb` packages for
  `git`/`curl`/`ca-certificates`/`ripgrep`, so re-installs are faster.

`entrypoint.sh` skips the `apt-get`/`npm install` step entirely if `claude`
is already on `PATH`. That fast path only kicks in for a container that's
being restarted (e.g. `docker compose up` / `start` on a container that
wasn't removed). With `docker compose run --rm` (the pattern used above),
Compose creates a fresh container filesystem every time, so `entrypoint.sh`
re-runs `apt-get install` and `npm install -g` on every invocation - the
volumes still make this faster (packages come from the apt cache and the npm
package files are already present) but it isn't a full no-op. If you want
the "skip entirely" fast path, run `docker compose up -d claude-code` once
and then `docker compose exec claude-code claude --dangerously-skip-permissions`
for subsequent sessions instead of `run --rm`.

## Root vs. non-root

Claude Code refuses to run with `--dangerously-skip-permissions` as root, so
`entrypoint.sh` still runs `apt-get`/`npm install` as root (needed to write
into `/usr/local/lib/node_modules` and `/var/cache/apt`) but then drops
to the `node` user that `node:22-slim` already ships (uid/gid 1000) via
`gosu` before the final `exec claude ...`. The `claude_config` volume is
mounted at `/home/node/.claude` to match.

## Network access

No custom network policies are configured - the container uses Docker's
default bridge network with unrestricted egress, so it can freely reach your
remote Ollama server (and anything else).

## Security note

`--dangerously-skip-permissions` disables Claude Code's per-action approval
prompts. That's intentional here: this container is meant to be an isolated,
disposable sandbox. Don't reuse this compose file to run Claude Code
directly against a host environment you care about without permission
prompts enabled.
