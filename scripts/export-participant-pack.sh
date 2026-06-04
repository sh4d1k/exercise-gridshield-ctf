#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

cd "$PROJECT_ROOT"
mkdir -p dist
pack="dist/gridshield-participant-pack.zip"
rm -f "$pack"

if [[ ! -d generated/m1/evidence ]]; then
  echo "generated/m1/evidence is missing. Run ./scripts/build.sh first." >&2
  exit 1
fi

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/gridshield-participant/evidence"
cp participant/brief.md "$tmp/gridshield-participant/brief.md"
cp participant/rules.md "$tmp/gridshield-participant/rules.md"
cp participant/connection_guide.md "$tmp/gridshield-participant/connection_guide.md"
cp generated/m1/evidence/archive.enc "$tmp/gridshield-participant/evidence/"
cp generated/m1/evidence/case_notes.txt "$tmp/gridshield-participant/evidence/"
cp generated/m1/evidence/ransom_note.txt "$tmp/gridshield-participant/evidence/"
cp -a generated/m1/evidence/volatility "$tmp/gridshield-participant/evidence/"

cat > "$tmp/gridshield-participant/README.txt" <<'TXT'
Exercise Gridshield participant package.

Start with brief.md and connection_guide.md.

The large endpoint.vmem memory image is not included in this zip by default.
Collect it from M1 at /evidence/endpoint.vmem after starting the local Docker lab.
TXT

(cd "$tmp" && zip -qr "$PROJECT_ROOT/$pack" gridshield-participant)
echo "Wrote $pack"
