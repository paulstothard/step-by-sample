#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  summarize-status.sh OUT_DIR [--input-dir IN_DIR]

Description:
  Scan one output folder containing per-sample subfolders and summarize:
    - .done
    - .failed
    - other

Arguments:
  OUT_DIR   Output folder for one workflow step.

Options:
  --input-dir IN_DIR   Compare status against the expected input samples so
                       samples with no output directory are still reported.

Examples:
  summarize-status.sh my-step-output
  summarize-status.sh my-step-output --input-dir input-samples
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

shift
IN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-dir)
      IN="${2:?Missing value for --input-dir}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$IN" ]] && [[ ! -d "$IN" ]]; then
  echo "Error: input folder not found: $IN" >&2
  exit 1
fi

done_n=0
fail_n=0
other_n=0
conflict_n=0
extra_n=0

echo "Summary for: $OUT"
echo

if [[ -n "$IN" ]]; then
  scan_dir="$IN"
else
  scan_dir="$OUT"
fi

while IFS= read -r -d '' sample_dir; do
  sample="$(basename -- "$sample_dir")"
  status_dir="$OUT/$sample"

  if [[ -f "$status_dir/.done" ]] && [[ -f "$status_dir/.failed" ]]; then
    conflict_n=$((conflict_n + 1))
    echo "CONFLICT $sample  both .done and .failed exist"
  elif [[ -f "$status_dir/.done" ]]; then
    done_n=$((done_n + 1))
  elif [[ -f "$status_dir/.failed" ]]; then
    fail_n=$((fail_n + 1))
    echo "FAILED $sample  log: $status_dir/run.log"
  else
    other_n=$((other_n + 1))
    if [[ ! -d "$status_dir" ]]; then
      echo "PENDING $sample  no output directory"
    fi
  fi
done < <(find -L "$scan_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

if [[ -n "$IN" ]]; then
  while IFS= read -r -d '' output_dir; do
    sample="$(basename -- "$output_dir")"
    if [[ ! -d "$IN/$sample" ]]; then
      extra_n=$((extra_n + 1))
      echo "EXTRA $sample  output has no matching input sample"
    fi
  done < <(find "$OUT" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

echo
echo "Done:    $done_n"
echo "Failed:  $fail_n"
echo "Other:   $other_n"
echo "Conflict: $conflict_n"
if [[ -n "$IN" ]]; then
  echo "Extra:   $extra_n"
fi
