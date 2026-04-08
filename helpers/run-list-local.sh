#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-list-local.sh RUN_LIST [JOBS]

Description:
  Run a list of per-sample job scripts locally using xargs.

Arguments:
  RUN_LIST   Text file containing one job script path per line.
  JOBS       Number of parallel jobs. Default: 1

Notes:
  - Blank lines and comment lines beginning with # are ignored.
  - Each runnable entry should usually be a path to a shell script.
  - Each script path is executed with: bash "$script"

Examples:
  run-list-local.sh run-quast.txt
  run-list-local.sh run-quast.txt 4
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

LIST="${1:-}"
JOBS="${2:-1}"

if [[ -z "$LIST" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$LIST" ]]; then
  echo "Error: run list not found: $LIST" >&2
  exit 1
fi

if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
  echo "Error: JOBS must be an integer >= 1" >&2
  exit 1
fi

mapfile -t scripts < <(grep -Ev '^[[:space:]]*($|#)' "$LIST")

if [[ "${#scripts[@]}" -eq 0 ]]; then
  echo "Error: no runnable entries found in: $LIST" >&2
  exit 1
fi

for script in "${scripts[@]}"; do
  if [[ ! -f "$script" ]]; then
    echo "Error: listed script not found: $script" >&2
    exit 1
  fi
done

echo "Run list: $LIST"
echo "Jobs:     $JOBS"
echo "Entries:  ${#scripts[@]}"

printf '%s\0' "${scripts[@]}" \
  | xargs -0 -I{} -P "$JOBS" bash -c 'bash "$1"' _ {}
