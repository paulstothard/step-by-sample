#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Customize the parameters at the top of this script, then run:
    ./single-local-template.sh

Parameters (edit in script):
  IN      Input directory with sample subdirectories
  OUT     Output directory (will be created)
  JOBS    Number of parallel jobs
  FORCE   1 to rerun done samples, 0 to skip
  DRY     1 for dry run, 0 for actual execution

Description:
  Run one workflow step locally with per-sample processing.
  Each sample gets its own run.log, .done, or .failed marker.

Examples:
  # Default run
  ./single-local-template.sh

  # After editing parameters in the script
  FORCE=1 DRY=1 ./single-local-template.sh  # Override for testing
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../helpers/common.sh" ]]; then
  source "$SCRIPT_DIR/../helpers/common.sh"
fi

# Default parameters (override via environment variables for testing)
IN="${IN:-shovill_output}"
OUT="${OUT:-quast_output}"
JOBS="${JOBS:-4}"
FORCE="${FORCE:-0}"
DRY="${DRY:-0}"

# Trap handler for cleanup
cleanup() {
  :
}
trap cleanup EXIT INT TERM

# Validate inputs
if [[ ! -d "$IN" ]]; then
  echo "Error: input directory not found: $IN" >&2
  exit 1
fi

if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
  echo "Error: JOBS must be a positive integer" >&2
  exit 1
fi

# Convert to absolute paths for safety
IN="$(cd "$IN" && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# Count and display samples
n_samples=$(find "$IN" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
echo "Found $n_samples samples in $IN"
echo "Starting processing with $JOBS parallel jobs..."
echo

start_time=$(date +%s)

run_one() {
  sample_dir="$1"
  sample="$(basename "$sample_dir")"
  out_dir="$OUT/$sample"
  log="$out_dir/run.log"
  done="$out_dir/.done"
  fail="$out_dir/.failed"

  mkdir -p "$out_dir"
  rm -f "$fail"

  ######################################################################
  # EDIT THIS SECTION: define the input file(s) for one sample
  ######################################################################

  # For testing: use generic data.txt if TEST_COMMAND is set
  if [[ -n "${TEST_COMMAND:-}" ]]; then
    f="$sample_dir/data.txt"
  else
    # Example 1: one file with a fixed name in each sample folder
    f="$sample_dir/contigs.fasta"
  fi

  # Example 2: paired files with fixed names
  # r1="$sample_dir/R1.fastq.gz"
  # r2="$sample_dir/R2.fastq.gz"

  # Example 3: paired files with variable names such as sample_R1.fastq.gz
  # mapfile -t reads < <(find_paired_reads "$sample_dir" "*_R1.fastq.gz" "*_R2.fastq.gz") 2>/dev/null || true
  # r1="${reads[0]:-}"
  # r2="${reads[1]:-}"
  # Alternative without common.sh:
  # r1="$(find "$sample_dir" -maxdepth 1 -type f -name "*_R1.fastq.gz" | head -n 1)"
  # r2="$(find "$sample_dir" -maxdepth 1 -type f -name "*_R2.fastq.gz" | head -n 1)"

  ######################################################################
  # EDIT THIS SECTION: check that the expected input file(s) exist
  ######################################################################

  if [ ! -f "$f" ]; then
    echo "FAIL  $sample  missing input: $f"
    : >"$fail"
    return 1
  fi

  # Paired-end example:
  # if [[ -z "$r1" ]] || [[ -z "$r2" ]] || [[ ! -f "$r1" ]] || [[ ! -f "$r2" ]]; then
  #   echo "FAIL  $sample  missing or incomplete paired input"
  #   : > "$fail"
  #   return 1
  # fi

  ######################################################################
  # Usually do not edit below here
  ######################################################################

  if [ "$FORCE" -ne 1 ] && [ -f "$done" ]; then
    echo "SKIP  $sample"
    return 0
  fi

  rm -f "$done"

  if [ "$DRY" -eq 1 ]; then
    echo "DRY   $sample"
    return 0
  fi

  echo "START $sample"

  {
    echo "=== $sample ==="
    date
    echo "Sample dir: $sample_dir"
    echo "Output dir: $out_dir"
    echo

    ####################################################################
    # EDIT THIS SECTION: put the real command here
    ####################################################################

    # For testing: use TEST_COMMAND if set (not for production use)
    if [[ -n "${TEST_COMMAND:-}" ]]; then
      $TEST_COMMAND "$out_dir" "$f" "$sample"
    else
      # Example: plain local command
      quast -o "$out_dir" "$f"
    fi

    # Example: Docker version of the same command
    # docker run --rm \
    #   -v "$(pwd)":/work \
    #   -u "$(id -u)":"$(id -g)" \
    #   -w /work \
    #   quay.io/biocontainers/quast:5.2.0--py310pl5321hc8f18ef_2 \
    #   quast -o "$out_dir" "$f"

    # Example: paired-end command
    # fastp \
    #   -i "$r1" \
    #   -I "$r2" \
    #   -o "$out_dir/R1.fastq.gz" \
    #   -O "$out_dir/R2.fastq.gz"

    # Example: paired-end Docker command
    # docker run --rm \
    #   -v "$(pwd)":/work \
    #   -u "$(id -u)":"$(id -g)" \
    #   -w /work \
    #   quay.io/biocontainers/fastp:0.23.4--h5f740d0_3 \
    #   fastp \
    #   -i "$r1" \
    #   -I "$r2" \
    #   -o "$out_dir/R1.fastq.gz" \
    #   -O "$out_dir/R2.fastq.gz"

  } >"$log" 2>&1

  status=$?

  if [ $status -eq 0 ]; then
    : >"$done"
    rm -f "$fail"
    echo "DONE  $sample"
    return 0
  else
    : >"$fail"
    echo "FAIL  $sample  see $log"
    return 1
  fi
}

export OUT FORCE DRY
export -f run_one

# Process samples with space-safe handling
mapfile -d '' -t sample_dirs < <(find "$IN" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
if [[ ${#sample_dirs[@]} -eq 0 ]]; then
  echo "Error: no sample directories found in $IN" >&2
  exit 1
fi

printf '%s\0' "${sample_dirs[@]}" \
  | xargs -0 -I{} -P "$JOBS" bash -c 'run_one "$@"' _ {}

echo
echo "Summary"

done_n=0
fail_n=0
other_n=0

while IFS= read -r -d '' sample_dir; do
  sample="$(basename "$sample_dir")"
  out_dir="$OUT/$sample"

  if [[ -f "$out_dir/.done" ]]; then
    done_n=$((done_n + 1))
  elif [[ -f "$out_dir/.failed" ]]; then
    fail_n=$((fail_n + 1))
    echo "FAILED $sample  log: $out_dir/run.log"
  else
    other_n=$((other_n + 1))
  fi
done < <(find "$IN" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

echo "Done:    $done_n"
echo "Failed:  $fail_n"
echo "Other:   $other_n"

end_time=$(date +%s)
elapsed=$((end_time - start_time))
if command -v format_time >/dev/null 2>&1; then
  echo "Time:    $(format_time $elapsed)"
else
  echo "Time:    ${elapsed}s"
fi
