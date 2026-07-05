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

# --- Java / Android toolchain (for building Java and Android projects) ---
JAVA_VERSION="${JAVA_VERSION:-21}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
ANDROID_CMDLINE_TOOLS_VERSION="${ANDROID_CMDLINE_TOOLS_VERSION:-11076708}"

if ! command -v javac >/dev/null 2>&1; then
  echo "[entrypoint] javac not found, installing OpenJDK ${JAVA_VERSION}..."
  apt-get update
  apt-get install -y --no-install-recommends "openjdk-${JAVA_VERSION}-jdk-headless"
else
  echo "[entrypoint] javac already installed, skipping setup"
fi

JAVA_HOME="/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-$(dpkg --print-architecture)"
export JAVA_HOME

if [ ! -d "${ANDROID_SDK_ROOT}/cmdline-tools/latest" ]; then
  echo "[entrypoint] Android cmdline-tools not found, installing..."
  apt-get update
  apt-get install -y --no-install-recommends unzip
  mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
  curl -fsSL -o /tmp/cmdline-tools.zip \
    "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip"
  unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools"
  mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest"
  rm -f /tmp/cmdline-tools.zip
  yes | "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null 2>&1 || true
  "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" --install "platform-tools" >/dev/null
else
  echo "[entrypoint] Android SDK cmdline-tools already installed, skipping setup"
fi

export ANDROID_HOME="${ANDROID_SDK_ROOT}"
export ANDROID_SDK_ROOT
export GRADLE_USER_HOME="/home/node/.gradle"
export PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${JAVA_HOME}/bin:${PATH}"

# Android Gradle Plugin auto-downloads any additional platform/build-tools
# versions a given project needs (into ANDROID_SDK_ROOT) as long as licenses
# are pre-accepted above, so we don't pin specific platform/build-tools here.

# claude refuses --dangerously-skip-permissions when running as root/sudo,
# so drop to the non-root "node" user that node:22-slim already ships (uid/gid 1000).
mkdir -p /home/node/.claude /home/node/.gradle /home/node/.m2
chown -R node:node /home/node/.claude /home/node/.gradle /home/node/.m2 "${ANDROID_SDK_ROOT}"

exec gosu node claude --dangerously-skip-permissions "$@"
