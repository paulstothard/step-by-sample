#!/usr/bin/env bash
set -euo pipefail

EXAMPLE_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(CDPATH='' cd -- "$EXAMPLE_DIR/../.." && pwd -P)"
WORK_DIR="${WORK_DIR:-$EXAMPLE_DIR/work}"

IN="${IN:-$EXAMPLE_DIR/input-samples}" \
OUT="${OUT:-$WORK_DIR/output}" \
JOB_DIR="${JOB_DIR:-$WORK_DIR/jobs}" \
LIST="${LIST:-$WORK_DIR/run.txt}" \
MODE="${MODE:-unfinished}" \
FORCE="${FORCE:-0}" \
STRICT="${STRICT:-1}" \
INPUT_MODE=paired-fixed \
R1_NAME=R1.fastq \
R2_NAME=R2.fastq \
STEP_COMMAND="$EXAMPLE_DIR/process-pair.sh" \
bash "$PROJECT_ROOT/examples/build-jobs-template.sh"
