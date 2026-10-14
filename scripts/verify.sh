#!/usr/bin/env bash
# Runs every verification rung that exists so far (see spec §9.2). Exits non-zero on the first failure.
set -euo pipefail
cd "$(dirname "$0")/.."
MVN="$PWD/.tools/apache-maven-3.9.11/bin/mvn"
ran=0

step() { printf '\n[verify] %s\n' "$1"; ran=$((ran + 1)); }

if [ -f bridge/pom.xml ]; then
  step "1-2. Bridge unit, scenario and contract tests"
  "$MVN" -B -q -f bridge/pom.xml verify
fi

if [ -f pnpm-workspace.yaml ]; then
  step "3. Typecheck, lint, unit tests (all workspaces)"
  pnpm -r --if-present typecheck
  pnpm -r --if-present lint
  pnpm -r --if-present test
fi

if [ -x scripts/e2e-headless-game.sh ]; then
  step "4. Full headless 4-player game"
  scripts/e2e-headless-game.sh
fi

if [ -x scripts/e2e-web.sh ]; then
  step "5. App web build + Playwright screenshots"
  scripts/e2e-web.sh
fi

if [ "$ran" -eq 0 ]; then
  echo "[verify] No verification rungs exist yet (no bridge/ or pnpm workspace)."
fi
echo "[verify] Passed $ran rung(s)."
