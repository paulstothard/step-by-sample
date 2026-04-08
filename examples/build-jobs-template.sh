#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Customize the parameters at the top of this script, then run:
    ./build-jobs-template.sh

Parameters (edit in script):
  IN       Input directory with sample subdirectories
  OUT      Output directory (will be created)
  JOB_DIR  Directory for generated job scripts
  LIST     Path to generated run list file
  MODE     Which samples to include: unfinished, failed, all
  FORCE    1 to include all regardless of status, 0 to respect MODE

Description:
  Generate per-sample job scripts and a run list for a workflow step.
  The run list can be executed locally or on Slurm.

Examples:
  # Build jobs for unfinished samples
  ./build-jobs-template.sh

  # Build jobs for failed samples only
  MODE="failed" ./build-jobs-template.sh
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
JOB_DIR="${JOB_DIR:-jobs-quast}"
LIST="${LIST:-run-quast.txt}"
MODE="${MODE:-unfinished}" # unfinished, failed, all
FORCE="${FORCE:-0}"

# Validate inputs
if [[ ! -d "$IN" ]]; then
  echo "Error: input directory not found: $IN" >&2
  exit 1
fi

if [[ "$MODE" != "unfinished" ]] && [[ "$MODE" != "failed" ]] && [[ "$MODE" != "all" ]]; then
  echo "Error: MODE must be one of: unfinished, failed, all" >&2
  exit 1
fi

# Convert to absolute paths for safety
IN="$(cd "$IN" && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# Count and display samples
n_total=$(find "$IN" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
echo "Found $n_total samples in $IN"
echo "Building jobs for MODE=$MODE"
echo

mkdir -p "$JOB_DIR"
: >"$LIST"

while IFS= read -r -d '' sample_dir; do
  sample="$(basename "$sample_dir")"
  out_dir="$OUT/$sample"
  log="$out_dir/run.log"
  done="$out_dir/.done"
  fail="$out_dir/.failed"
  job="$JOB_DIR/$sample.sh"

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
  # mapfile -t reads < <(find "$sample_dir" -maxdepth 1 -type f -name "*_R1.fastq.gz" -o -name "*_R2.fastq.gz" | sort)
  # r1=""
  # r2=""
  # for read in "${reads[@]}"; do
  #   if [[ "$read" =~ _R1\.fastq\.gz$ ]]; then r1="$read"; fi
  #   if [[ "$read" =~ _R2\.fastq\.gz$ ]]; then r2="$read"; fi
  # done
  # if [[ -z "$r1" ]] || [[ -z "$r2" ]]; then
  #   echo "SKIP  $sample  no paired-end files found"
  #   continue
  # fi

  ######################################################################
  # EDIT THIS SECTION: check that the expected input file(s) exist
  ######################################################################

  if [ ! -f "$f" ]; then
    echo "SKIP  $sample  missing input: $f"
    continue
  fi

  # Paired-end example:
  # if [[ -z "$r1" ]] || [[ -z "$r2" ]] || [[ ! -f "$r1" ]] || [[ ! -f "$r2" ]]; then
  #   echo "SKIP  $sample  missing or incomplete paired input"
  #   continue
  # fi

  ######################################################################
  # Usually do not edit below here
  ######################################################################

  should_run=0

  if [ "$FORCE" -eq 1 ]; then
    should_run=1
  elif [ "$MODE" = "all" ]; then
    should_run=1
  elif [ "$MODE" = "unfinished" ]; then
    if [ ! -f "$done" ]; then
      should_run=1
    fi
  elif [ "$MODE" = "failed" ]; then
    if [ -f "$fail" ]; then
      should_run=1
    fi
  else
    echo "Unknown MODE: $MODE" >&2
    exit 1
  fi

  if [ "$should_run" -eq 0 ]; then
    echo "SKIP  $sample"
    continue
  fi

  cat >"$job" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# For testing: preserve TEST_COMMAND if set
TEST_COMMAND="${TEST_COMMAND:-}"

sample="$sample"
sample_dir="$sample_dir"
out_dir="$out_dir"
log="$log"
done="$done"
fail="$fail"

mkdir -p "\$out_dir"
rm -f "\$fail"
rm -f "\$done"

########################################################################
# Sample-specific input paths
########################################################################

f="$f"

# Paired fixed example:
# r1="\$r1"
# r2="\$r2"

########################################################################
# Input validation
########################################################################

if [ ! -f "\$f" ]; then
  echo "FAIL  \$sample  missing input: \$f"
  : > "\$fail"
  exit 1
fi

# Paired-end example:
# if [ ! -f "\$r1" ] || [ ! -f "\$r2" ]; then
#   echo "FAIL  \$sample  missing paired input"
#   : > "\$fail"
#   exit 1
# fi

# Paired-end validation with empty check:
# if [[ -z "\$r1" ]] || [[ -z "\$r2" ]] || [[ ! -f "\$r1" ]] || [[ ! -f "\$r2" ]]; then
#   echo "FAIL  \$sample  missing or incomplete paired input"
#   : > "\$fail"
#   exit 1
# fi

echo "START \$sample"

{
  echo "=== \$sample ==="
  date
  echo "Sample dir: \$sample_dir"
  echo "Output dir: \$out_dir"
  echo

  ######################################################################
  # EDIT THIS SECTION: put the real command here
  ######################################################################

  # For testing: use TEST_COMMAND if set (not for production use)
  if [[ -n "\${TEST_COMMAND:-}" ]]; then
    \$TEST_COMMAND "\$out_dir" "\$f" "\$sample"
  else
    # Example: plain local command
    quast -o "\$out_dir" "\$f"
  fi

  # Example: Docker version of the same command
  # docker run --rm \
  #   -v "\$(pwd)":/work \
  #   -u "\$(id -u)":"\$(id -g)" \
  #   -w /work \
  #   quay.io/biocontainers/quast:5.2.0--py310pl5321hc8f18ef_2 \
  #   quast -o "\$out_dir" "\$f"

  # Example: paired-end command
  # fastp \
  #   -i "\$r1" \
  #   -I "\$r2" \
  #   -o "\$out_dir/R1.fastq.gz" \
  #   -O "\$out_dir/R2.fastq.gz"

  # Example: paired-end Docker command
  # docker run --rm \
  #   -v "\$(pwd)":/work \
  #   -u "\$(id -u)":"\$(id -g)" \
  #   -w /work \
  #   quay.io/biocontainers/fastp:0.23.4--h5f740d0_3 \
  #   fastp \
  #   -i "\$r1" \
  #   -I "\$r2" \
  #   -o "\$out_dir/R1.fastq.gz" \
  #   -O "\$out_dir/R2.fastq.gz"

} >"\$log" 2>&1

status=\$?

if [ \$status -eq 0 ]; then
  : > "\$done"
  rm -f "\$fail"
  echo "DONE  \$sample"
  exit 0
else
  : > "\$fail"
  echo "FAIL  \$sample  see \$log"
  exit 1
fi
EOF

  chmod +x "$job"
  echo "$job" >>"$LIST"
  echo "ADD   $sample  $job"
done < <(find "$IN" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

n_jobs=$(wc -l <"$LIST" | tr -d ' ')
echo
echo "Summary:"
echo "  Total samples: $n_total"
echo "  Jobs created:  $n_jobs"
echo "  Job dir:       $JOB_DIR"
echo "  Run list:      $LIST"
