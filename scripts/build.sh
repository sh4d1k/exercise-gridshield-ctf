#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

export GRIDSHIELD_BUILD_LOG_DIR="${GRIDSHIELD_BUILD_LOG_DIR:-$PROJECT_ROOT/logs/builds/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$GRIDSHIELD_BUILD_LOG_DIR"
printf '%s\n' "$GRIDSHIELD_BUILD_LOG_DIR" > "$PROJECT_ROOT/logs/current-build-dir"
cd "$PROJECT_ROOT"

scripts/run-log.sh "preflight host snapshot" -- bash -lc 'hostname; docker version; docker compose version; df -h .'
scripts/run-log.sh "generate artifacts" -- bash scripts/generate-artifacts.sh
scripts/run-log.sh "build common image" -- docker build -t gridshield/common:public src/common
scripts/run-log.sh "compose build" -- docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" build
scripts/run-log.sh "compose up" -- docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" up -d
scripts/run-log.sh "post-build snapshot" -- bash -lc 'docker container ls -a --filter name=gridshield_; find generated -maxdepth 3 -type f | sort | sed -n "1,200p"'
echo "Build log: $GRIDSHIELD_BUILD_LOG_DIR"
