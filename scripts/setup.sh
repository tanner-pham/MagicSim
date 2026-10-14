#!/usr/bin/env bash
# Idempotent dev setup shared by local machines, CI, and cloud agents (Cursor, Claude Code, Codex).
# Safe to re-run; each step skips work that is already done.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TOOLS="$ROOT/.tools"
MAVEN_VERSION=3.9.11
MVN="$TOOLS/apache-maven-$MAVEN_VERSION/bin/mvn"

log() { printf '\n[setup] %s\n' "$*"; }

java_major() { java -version 2>&1 | awk -F'"' '/version/ { split($2, v, "."); print v[1]; exit }'; }
if ! command -v java >/dev/null || [ "$(java_major)" -lt 17 ]; then
  echo "[setup] Java 17 or newer is required (Temurin 21 recommended). Found: $(java -version 2>&1 | head -1)" >&2
  exit 1
fi

if [ ! -x "$MVN" ]; then
  log "Installing Maven $MAVEN_VERSION into .tools/"
  mkdir -p "$TOOLS"
  curl -fsSL --retry 3 "https://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz" | tar -xz -C "$TOOLS"
fi

log "Syncing Forge submodule (shallow, pinned)"
git submodule update --init --depth 1 forge

FORGE_SHA="$(git -C forge rev-parse HEAD)"
STAMP="$TOOLS/forge-flattened-$FORGE_SHA"
if [ ! -f "$STAMP" ]; then
  log "Installing Forge modules into the local Maven repo (first run takes several minutes)"
  # Forge's .mvn/maven.config uses a cwd-relative settings path, so Maven must run from forge/.
  # Forge's POMs use ${revision}; flattening writes real versions into the installed POMs so the bridge
  # can resolve them. Forge already gitignores .flattened-pom.xml, so the submodule stays clean.
  (cd forge && "$MVN" -B -q -pl forge-gui -am \
    org.codehaus.mojo:flatten-maven-plugin:1.7.0:flatten install \
    -Dflatten.mode=resolveCiFriendliesOnly -DskipTests -Dcheckstyle.skip)
  rm -f "$TOOLS"/forge-installed-* "$TOOLS"/forge-flattened-*
  touch "$STAMP"
fi

if [ -f bridge/pom.xml ]; then
  log "Building forge-bridge"
  "$MVN" -B -q -f bridge/pom.xml package -DskipTests
fi

if [ -f pnpm-workspace.yaml ]; then
  command -v pnpm >/dev/null || corepack enable
  log "Installing JS dependencies"
  if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; else pnpm install; fi
  if pnpm exec playwright --version >/dev/null 2>&1; then
    log "Installing Playwright Chromium"
    pnpm exec playwright install --with-deps chromium 2>/dev/null || pnpm exec playwright install chromium
  fi
fi

log "Done. Run scripts/verify.sh to check everything."
