#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ $# -lt 3 || "$2" != "--" ]]; then
  echo 'Usage: scripts/run-log.sh "<intent>" -- <command> [args...]' >&2
  exit 2
fi

intent="$1"
shift 2
log_dir="$(current_build_dir)"
mkdir -p "$log_dir/stdout" "$log_dir/stderr"
tsv="$log_dir/commands.tsv"
[[ -f "$tsv" ]] || printf 'start_utc\thost\tpwd\tintent\tcommand\texit_code\tduration_sec\tstdout\tstderr\n' > "$tsv"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
safe="$(printf '%s' "$intent" | tr -cs 'A-Za-z0-9_.-' '_' | sed 's/^_//;s/_$//' | cut -c1-80)"
stdout="$log_dir/stdout/${stamp}_${safe}.out"
stderr="$log_dir/stderr/${stamp}_${safe}.err"
start_epoch="$(date +%s)"
cmd_display="$(printf '%q ' "$@")"

echo "[run-log] $intent"
echo "[run-log] $cmd_display"
"$@" >"$stdout" 2>"$stderr"
code=$?
end_epoch="$(date +%s)"
duration=$((end_epoch - start_epoch))
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$stamp" "$(hostname)" "$(pwd)" "$intent" "$cmd_display" "$code" "$duration" "$stdout" "$stderr" >> "$tsv"
if [[ "$code" -ne 0 ]]; then
  echo "[run-log] command failed with exit $code" >&2
  echo "[run-log] stderr: $stderr" >&2
  exit "$code"
fi
