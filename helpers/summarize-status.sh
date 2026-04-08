#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  summarize-status.sh OUT_DIR

Description:
  Scan one output folder containing per-sample subfolders and summarize:
    - .done
    - .failed
    - other

Arguments:
  OUT_DIR   Output folder for one workflow step.

Examples:
  summarize-status.sh my-step-output
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

OUT="${1:-}"

if [[ -z "$OUT" ]]; then
  usage
  exit 1
fi

if [[ ! -d "$OUT" ]]; then
  echo "Error: output folder not found: $OUT" >&2
  exit 1
fi

done_n=0
fail_n=0
other_n=0

echo "Summary for: $OUT"
echo

while IFS= read -r sample_dir; do
  sample="$(basename "$sample_dir")"

  if [[ -f "$sample_dir/.done" ]]; then
    done_n=$((done_n + 1))
  elif [[ -f "$sample_dir/.failed" ]]; then
    fail_n=$((fail_n + 1))
    echo "FAILED $sample  log: $sample_dir/run.log"
  else
    other_n=$((other_n + 1))
  fi
done < <(find "$OUT" -mindepth 1 -maxdepth 1 -type d | sort)

echo
echo "Done:    $done_n"
echo "Failed:  $fail_n"
echo "Other:   $other_n"
