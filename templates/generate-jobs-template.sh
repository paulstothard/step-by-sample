#!/usr/bin/env bash
set -euo pipefail

if ((BASH_VERSINFO[0] < 4)); then
  echo "Error: step-by-sample requires Bash 4 or newer (found $BASH_VERSION)" >&2
  exit 2
fi

usage() {
  cat <<'EOF'
Usage:
  Customize the parameters at the top of this script, then run:
    ./generate-jobs-template.sh

Parameters (edit in script):
  IN       Input directory with sample subdirectories
  OUT      Output directory (will be created)
  JOB_DIR  Directory for generated job scripts
  LIST     Path to generated run list file
  MODE     Which samples to include: unfinished, failed, all
  FORCE    1 to include all regardless of status, 0 to respect MODE
  STRICT   1 to fail generation when any sample is missing its input
  INPUT_MODE    single or paired-fixed
  INPUT_NAME    File name for single mode. Default: input.dat
  R1_NAME       Forward-read file name. Default: R1.fastq.gz
  R2_NAME       Reverse-read file name. Default: R2.fastq.gz
  STEP_COMMAND  Optional executable called for each sample. Its arguments are:
                  single:       OUT_DIR INPUT_FILE SAMPLE_NAME
                  paired-fixed: OUT_DIR R1_FILE R2_FILE SAMPLE_NAME

Description:
  Generate per-sample job scripts and a run list for a workflow step.
  The run list can be executed locally or on Slurm.

Examples:
  # Generate jobs for unfinished samples
  ./generate-jobs-template.sh

  # Generate jobs for failed samples only
  MODE="failed" ./generate-jobs-template.sh
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Resolve paths without allowing a user's CDPATH setting to add output.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -f "$SCRIPT_DIR/../lib/common.sh" ]]; then
  source "$SCRIPT_DIR/../lib/common.sh"
elif [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
  # This is the expected location after following the README and copying the
  # template from templates/ into the repository root.
  source "$SCRIPT_DIR/lib/common.sh"
fi

# Default parameters (override via environment variables for testing)
IN="${IN:-input-samples}"
OUT="${OUT:-my-step-output}"
JOB_DIR="${JOB_DIR:-jobs-my-step}"
LIST="${LIST:-run-my-step.txt}"
MODE="${MODE:-unfinished}" # unfinished, failed, all
FORCE="${FORCE:-0}"
STRICT="${STRICT:-0}"
INPUT_MODE="${INPUT_MODE:-single}"
INPUT_NAME="${INPUT_NAME:-}"
R1_NAME="${R1_NAME:-R1.fastq.gz}"
R2_NAME="${R2_NAME:-R2.fastq.gz}"
# TEST_COMMAND is retained as a backwards-compatible test hook.
STEP_COMMAND="${STEP_COMMAND:-${TEST_COMMAND:-}}"

if [[ -z "$INPUT_NAME" ]]; then
  if [[ -n "${TEST_COMMAND:-}" ]]; then
    INPUT_NAME="data.txt"
  else
    INPUT_NAME="input.dat"
  fi
fi

if [[ -n "$STEP_COMMAND" ]] && [[ "$STEP_COMMAND" == */* ]]; then
  if [[ ! -x "$STEP_COMMAND" ]]; then
    echo "Error: STEP_COMMAND is not executable: $STEP_COMMAND" >&2
    exit 1
  fi
  STEP_COMMAND="$(CDPATH='' cd -- "$(dirname -- "$STEP_COMMAND")" && pwd -P)/$(basename -- "$STEP_COMMAND")"
fi

# Validate inputs
if [[ ! -d "$IN" ]]; then
  echo "Error: input directory not found: $IN" >&2
  exit 1
fi

if [[ "$MODE" != "unfinished" ]] && [[ "$MODE" != "failed" ]] && [[ "$MODE" != "all" ]]; then
  echo "Error: MODE must be one of: unfinished, failed, all" >&2
  exit 1
fi

if [[ "$FORCE" != "0" ]] && [[ "$FORCE" != "1" ]]; then
  echo "Error: FORCE must be 0 or 1" >&2
  exit 1
fi

if [[ "$STRICT" != "0" ]] && [[ "$STRICT" != "1" ]]; then
  echo "Error: STRICT must be 0 or 1" >&2
  exit 1
fi

if [[ "$INPUT_MODE" != "single" ]] && [[ "$INPUT_MODE" != "paired-fixed" ]]; then
  echo "Error: INPUT_MODE must be one of: single, paired-fixed" >&2
  exit 1
fi

for input_name in "$INPUT_NAME" "$R1_NAME" "$R2_NAME"; do
  if [[ "$input_name" == */* ]] || [[ "$input_name" == *$'\n'* ]] || [[ "$input_name" == *$'\r'* ]]; then
    echo "Error: input file names must be plain file names without slashes or newlines: $input_name" >&2
    exit 1
  fi
done

# Convert to absolute paths for safety
IN="$(CDPATH='' cd -- "$IN" && pwd -P)"
mkdir -p "$OUT"
OUT="$(CDPATH='' cd -- "$OUT" && pwd -P)"
mkdir -p "$(dirname "$JOB_DIR")"
JOB_DIR="$(CDPATH='' cd -- "$(dirname -- "$JOB_DIR")" && pwd -P)/$(basename -- "$JOB_DIR")"
mkdir -p "$JOB_DIR"
mkdir -p "$(dirname "$LIST")"
LIST="$(CDPATH='' cd -- "$(dirname -- "$LIST")" && pwd -P)/$(basename -- "$LIST")"

# Count and display samples
n_total=$(find -L "$IN" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
echo "Found $n_total samples in $IN"
echo "Generating jobs for MODE=$MODE"
echo

: >"$LIST"

n_jobs=0
n_missing=0
n_status_skipped=0

while IFS= read -r -d '' sample_dir; do
  sample="$(basename "$sample_dir")"
  out_dir="$OUT/$sample"
  log="$out_dir/run.log"
  done="$out_dir/.done"
  fail="$out_dir/.failed"
  job="$JOB_DIR/$sample.sh"

  if [[ "$sample" == *$'\n'* ]] || [[ "$sample" == *$'\r'* ]]; then
    echo "Error: sample names cannot contain newlines: $sample" >&2
    exit 1
  fi

  ######################################################################
  # EDIT THIS SECTION: define the input file(s) for one sample
  ######################################################################

  f=""
  r1=""
  r2=""

  if [[ "$INPUT_MODE" == "single" ]]; then
    f="$sample_dir/$INPUT_NAME"
  else
    r1="$sample_dir/$R1_NAME"
    r2="$sample_dir/$R2_NAME"
  fi

  # For a different layout, replace only this discovery block and add a test
  # using representative file names. The rest of the generator can stay the
  # same.

  ######################################################################
  # EDIT THIS SECTION: check that the expected input file(s) exist
  ######################################################################

  missing_message=""
  if [[ "$INPUT_MODE" == "single" ]] && [[ ! -f "$f" ]]; then
    missing_message="missing input: $f"
  elif [[ "$INPUT_MODE" == "paired-fixed" ]] \
    && { [[ ! -f "$r1" ]] || [[ ! -f "$r2" ]]; }; then
    missing_message="missing paired input: $r1 or $r2"
  fi

  if [[ -n "$missing_message" ]]; then
    echo "SKIP  $sample  $missing_message"
    rm -f "$job"
    n_missing=$((n_missing + 1))
    continue
  fi

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
    rm -f "$job"
    n_status_skipped=$((n_status_skipped + 1))
    continue
  fi

  # Values interpolated into the generated script must be shell-escaped.
  # Without this, characters such as $, quotes, and backticks in paths are
  # interpreted again when the generated job runs.
  printf -v step_command_q '%q' "$STEP_COMMAND"
  printf -v input_mode_q '%q' "$INPUT_MODE"
  printf -v sample_q '%q' "$sample"
  printf -v sample_dir_q '%q' "$sample_dir"
  printf -v out_dir_q '%q' "$out_dir"
  printf -v log_q '%q' "$log"
  printf -v done_q '%q' "$done"
  printf -v fail_q '%q' "$fail"
  printf -v f_q '%q' "$f"
  printf -v r1_q '%q' "$r1"
  printf -v r2_q '%q' "$r2"

  cat >"$job" <<EOF
#!/usr/bin/env bash
set -euo pipefail

STEP_COMMAND=$step_command_q
input_mode=$input_mode_q

sample=$sample_q
sample_dir=$sample_dir_q
out_dir=$out_dir_q
log=$log_q
done=$done_q
fail=$fail_q

mkdir -p "\$out_dir"
lock_dir="\$out_dir/.running"
if ! mkdir "\$lock_dir" 2>/dev/null; then
  echo "BUSY  \$sample  another run is already active" >&2
  exit 75
fi

job_complete=0
cleanup_job() {
  if [[ "\$job_complete" -ne 1 ]]; then
    : >"\$fail"
    rm -f "\$done"
  fi
  rmdir "\$lock_dir" 2>/dev/null || true
}
trap cleanup_job EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

rm -f "\$fail"
rm -f "\$done"

########################################################################
# Sample-specific input paths
########################################################################

f=$f_q
r1=$r1_q
r2=$r2_q

# Paired input paths are always defined. They are empty until the paired-input
# assignments in the generator section are enabled.

########################################################################
# Input validation
########################################################################

if [[ "\$input_mode" == "single" ]] && [[ ! -f "\$f" ]]; then
  echo "FAIL  \$sample  missing input: \$f"
  : > "\$fail"
  exit 1
fi

if [[ "\$input_mode" == "paired-fixed" ]] \
  && { [[ -z "\$r1" ]] || [[ -z "\$r2" ]] || [[ ! -f "\$r1" ]] || [[ ! -f "\$r2" ]]; }; then
  echo "FAIL  \$sample  missing or incomplete paired input"
  : > "\$fail"
  exit 1
fi

echo "START \$sample"

if {
  echo "=== \$sample ==="
  date
  echo "Sample dir: \$sample_dir"
  echo "Output dir: \$out_dir"
  echo

  ######################################################################
  # EDIT THIS SECTION: put the real command here
  ######################################################################

  # Keep tool-specific logic in a separate executable so it can be run and
  # tested independently. See examples/runnable-single and runnable-paired.
  if [[ -z "\${STEP_COMMAND:-}" ]]; then
    echo "No STEP_COMMAND configured. Set it to an executable for this workflow step." >&2
    exit 2
  elif [[ "\$input_mode" == "single" ]]; then
    "\$STEP_COMMAND" "\$out_dir" "\$f" "\$sample"
  else
    "\$STEP_COMMAND" "\$out_dir" "\$r1" "\$r2" "\$sample"
  fi

} >"\$log" 2>&1; then
  : > "\$done"
  rm -f "\$fail"
  job_complete=1
  echo "DONE  \$sample"
  exit 0
else
  : > "\$fail"
  job_complete=1
  echo "FAIL  \$sample  see \$log"
  exit 1
fi
EOF

  chmod +x "$job"
  echo "$job" >>"$LIST"
  n_jobs=$((n_jobs + 1))
  echo "ADD   $sample  $job"
done < <(find -L "$IN" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

echo
echo "Summary:"
echo "  Total samples: $n_total"
echo "  Jobs created:  $n_jobs"
echo "  Missing input: $n_missing"
echo "  Status skipped: $n_status_skipped"
echo "  Job dir:       $JOB_DIR"
echo "  Run list:      $LIST"

if [[ "$STRICT" -eq 1 ]] && [[ "$n_missing" -gt 0 ]]; then
  echo "Error: STRICT=1 and $n_missing sample(s) were missing input" >&2
  exit 1
fi
