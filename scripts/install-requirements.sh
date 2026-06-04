#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REQ_FILE="$PROJECT_ROOT/requirements.txt"

show_help() {
  cat <<'EOF'
Usage: ./scripts/install-requirements.sh [--dry-run] [--no-update] [--help]

Install host prerequisites for Exercise Gridshield on Debian/Ubuntu.

Options:
  --dry-run      Show the packages that would be installed, but do not install.
  --no-update    Skip apt-get update before installation.
  --help         Show this help message.
EOF
}

DRY_RUN=0
NO_UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-update) NO_UPDATE=1 ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; show_help; exit 2 ;;
  esac
done

if [[ ! -f "$REQ_FILE" ]]; then
  echo "Requirements file not found: $REQ_FILE" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installer currently supports Debian/Ubuntu hosts with apt-get." >&2
  exit 1
fi

mapfile -t packages < <(grep -E '^[[:alnum:]]' "$REQ_FILE")
if [[ ${#packages[@]} -eq 0 ]]; then
  echo "No packages found in $REQ_FILE" >&2
  exit 1
fi

echo "Requirements file: $REQ_FILE"
echo "Packages to install:"
for pkg in "${packages[@]}"; do
  echo "  - $pkg"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run only; no packages will be installed."
  exit 0
fi

if [[ "$NO_UPDATE" -eq 0 ]]; then
  echo "Updating package lists..."
  sudo apt-get update
fi

echo "Installing packages..."
sudo apt-get install -y "${packages[@]}"

echo "Host prerequisites installed."
