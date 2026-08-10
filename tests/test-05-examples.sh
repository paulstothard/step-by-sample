#!/usr/bin/env bash
# Verify that the documented runnable examples work end to end.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib/test-helpers.sh"

PROJECT_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)"

print_header "Testing Runnable Examples"

setup_test_dir "examples"
trap cleanup_test_dir EXIT

# Copy the documented example tree into a path containing spaces. This lets the
# tests run the README commands exactly while keeping generated work out of the
# source checkout.
DOC_ROOT="$TEST_DIR/repository with spaces"
mkdir -p "$DOC_ROOT"
cp -R "$PROJECT_ROOT/examples" "$DOC_ROOT/examples"
cp -R "$PROJECT_ROOT/bin" "$DOC_ROOT/bin"
cp -R "$PROJECT_ROOT/lib" "$DOC_ROOT/lib"
cp -R "$PROJECT_ROOT/templates" "$DOC_ROOT/templates"

#############################################################################
start_test "Single-input example runs end to end"

SINGLE="$DOC_ROOT/examples/runnable-single"
(
  cd "$SINGLE"
  ./generate-jobs.sh >/dev/null
  ../../bin/run-jobs-local.sh work/run.txt 2 >/dev/null 2>&1
  ../../bin/show-step-status.sh work/output --input-dir input-samples >work/status.txt
)
WORK="$SINGLE/work"

assert_file_exists "$WORK/output/alpha/.done" \
  && assert_log_contains "$WORK/output/alpha/result.txt" "ALPHA EXAMPLE" \
  && assert_log_contains "$WORK/status.txt" "Done:    2" \
  && assert_count_equals "$(count_done "$WORK/output")" 2 \
  && pass_test

#############################################################################
start_test "Paired-input example runs end to end"

PAIRED="$DOC_ROOT/examples/runnable-paired"
(
  cd "$PAIRED"
  ./generate-jobs.sh >/dev/null
  ../../bin/run-jobs-local.sh work/run.txt 2 >/dev/null 2>&1
  ../../bin/show-step-status.sh work/output --input-dir input-samples >work/status.txt
)
WORK="$PAIRED/work"

assert_file_exists "$WORK/output/beta/.done" \
  && assert_log_contains "$WORK/output/beta/pair-summary.txt" "r1_reads=2" \
  && assert_log_contains "$WORK/output/beta/pair-summary.txt" "r2_reads=2" \
  && assert_log_contains "$WORK/status.txt" "Done:    2" \
  && assert_count_equals "$(count_done "$WORK/output")" 2 \
  && pass_test

print_test_summary "${BASH_SOURCE[0]}"
