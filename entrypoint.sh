#!/usr/bin/env bash
set -euo pipefail

: "${HOST_WORKDIR:?HOST_WORKDIR is not set. Set it in .env or pass HOST_WORKDIR=/path/on/host docker compose up}"
: "${ANTHROPIC_BASE_URL:?ANTHROPIC_BASE_URL is not set. Point it at your remote Ollama server, e.g. http://ollama-host.example.com:11434}"
: "${ANTHROPIC_AUTH_TOKEN:?ANTHROPIC_AUTH_TOKEN is not set. Ollama ignores the value but Claude Code requires one, e.g. ollama}"
: "${ANTHROPIC_MODEL:?ANTHROPIC_MODEL is not set. It must match a model tag that already exists on the remote Ollama server}"

if [ -z "${ANTHROPIC_API_KEY+x}" ]; then
  echo "ANTHROPIC_API_KEY is not set. It must be present (may be empty) - see .env.example" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "[entrypoint] claude not found on PATH, installing dependencies..."
  apt-get update
  apt-get install -y --no-install-recommends git curl ca-certificates ripgrep gosu
  npm install -g @anthropic-ai/claude-code
else
  echo "[entrypoint] claude already installed, skipping setup"
fi

# claude refuses --dangerously-skip-permissions when running as root/sudo,
# so drop to the non-root "node" user that node:22-slim already ships (uid/gid 1000).
mkdir -p /home/node/.claude
chown -R node:node /home/node/.claude

exec gosu node claude --dangerously-skip-permissions "$@"
