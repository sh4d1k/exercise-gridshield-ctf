#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
COMPOSE_FILE="$PROJECT_ROOT/infra/docker-compose.yml"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-gridshield}"
GENERATED_DIR="$PROJECT_ROOT/generated"
export PROJECT_ROOT COMPOSE_FILE COMPOSE_PROJECT_NAME GENERATED_DIR

current_build_dir() {
  if [[ -n "${GRIDSHIELD_BUILD_LOG_DIR:-}" ]]; then
    mkdir -p "$GRIDSHIELD_BUILD_LOG_DIR"
    printf '%s\n' "$GRIDSHIELD_BUILD_LOG_DIR"
    return
  fi
  local state="$PROJECT_ROOT/logs/current-build-dir"
  if [[ -f "$state" ]]; then
    cat "$state"
    return
  fi
  local dir="$PROJECT_ROOT/logs/builds/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$dir"
  printf '%s\n' "$dir" > "$state"
  printf '%s\n' "$dir"
}
