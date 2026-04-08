#!/usr/bin/env bash
# Test helper utility scripts
# Tests validate-step.sh, summarize-status.sh, repair-failed.sh, common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_header "Testing Helper Utilities"

# Setup
setup_test_dir "helpers"
trap cleanup_test_dir EXIT

#############################################################################
# Test 1: validate-step.sh with valid input
#############################################################################
start_test "validate-step.sh succeeds with valid input"

IN="$TEST_DIR/test1_in"
create_mock_samples "$IN" "single" "s1" "s2" "s3"

if bash "$PROJECT_ROOT/helpers/validate-step.sh" "$IN" >/dev/null 2>&1; then
  pass_test
else
  fail_test "Validation failed on valid input"
fi

#############################################################################
# Test 2: validate-step.sh catches missing directory
#############################################################################
start_test "validate-step.sh catches missing directory"

if bash "$PROJECT_ROOT/helpers/validate-step.sh" "$TEST_DIR/nonexistent" >/dev/null 2>&1; then
  fail_test "Should have failed on missing directory"
else
  print_info "✓ Correctly rejected missing directory"
  pass_test
fi

#############################################################################
# Test 3: validate-step.sh catches empty directory
#############################################################################
start_test "validate-step.sh catches empty directory"

mkdir -p "$TEST_DIR/test3_empty"

if bash "$PROJECT_ROOT/helpers/validate-step.sh" "$TEST_DIR/test3_empty" >/dev/null 2>&1; then
  fail_test "Should have failed on empty directory"
else
  print_info "✓ Correctly rejected empty directory"
  pass_test
fi

#############################################################################
# Test 4: summarize-status.sh reports counts correctly
#############################################################################
start_test "summarize-status.sh reports correct counts"

OUT="$TEST_DIR/test4_out"
mkdir -p "$OUT/s1" "$OUT/s2" "$OUT/s3" "$OUT/s4"
touch "$OUT/s1/.done"
touch "$OUT/s2/.done"
touch "$OUT/s3/.failed"
# s4 has neither (other)

output=$(bash "$PROJECT_ROOT/helpers/summarize-status.sh" "$OUT" 2>&1)

if echo "$output" | grep -q "Done:    2" \
  && echo "$output" | grep -q "Failed:  1" \
  && echo "$output" | grep -q "Other:   1"; then
  print_info "✓ Correctly counted: 2 done, 1 failed, 1 other"
  pass_test
else
  fail_test "Incorrect status counts"
fi

#############################################################################
# Test 5: repair-failed.sh removes failure markers
#############################################################################
start_test "repair-failed.sh removes .failed markers"

OUT="$TEST_DIR/test5_out"
mkdir -p "$OUT/ok" "$OUT/failed1" "$OUT/failed2"
touch "$OUT/ok/.done"
touch "$OUT/failed1/.failed"
touch "$OUT/failed2/.failed"
echo "test log" >"$OUT/failed1/run.log"

if bash "$PROJECT_ROOT/helpers/repair-failed.sh" "$OUT" >/dev/null 2>&1; then
  assert_file_exists "$OUT/ok/.done" "Done marker should remain" \
    && assert_file_not_exists "$OUT/failed1/.failed" "Failed marker should be removed" \
    && assert_file_not_exists "$OUT/failed2/.failed" "Failed marker should be removed" \
    && assert_file_exists "$OUT/failed1/run.log" "Log should be preserved" \
    && pass_test
else
  fail_test "repair-failed.sh execution failed"
fi

#############################################################################
# Test 6: repair-failed.sh --clean-outputs removes files
#############################################################################
start_test "repair-failed.sh --clean-outputs removes output files"

OUT="$TEST_DIR/test6_out"
mkdir -p "$OUT/failed"
touch "$OUT/failed/.failed"
touch "$OUT/failed/output1.txt"
touch "$OUT/failed/output2.txt"
echo "test log" >"$OUT/failed/run.log"

if bash "$PROJECT_ROOT/helpers/repair-failed.sh" "$OUT" --clean-outputs >/dev/null 2>&1; then
  assert_file_not_exists "$OUT/failed/.failed" "Failed marker should be removed" \
    && assert_file_not_exists "$OUT/failed/output1.txt" "Output files should be removed" \
    && assert_file_not_exists "$OUT/failed/output2.txt" "Output files should be removed" \
    && assert_file_exists "$OUT/failed/run.log" "Log should be preserved" \
    && pass_test
else
  fail_test "repair-failed.sh --clean-outputs failed"
fi

#############################################################################
# Test 7: repair-failed.sh --dry-run doesn't modify files
#############################################################################
start_test "repair-failed.sh --dry-run doesn't modify files"

OUT="$TEST_DIR/test7_out"
mkdir -p "$OUT/failed"
touch "$OUT/failed/.failed"

bash "$PROJECT_ROOT/helpers/repair-failed.sh" "$OUT" --dry-run >/dev/null 2>&1

assert_file_exists "$OUT/failed/.failed" "Failed marker should still exist after dry run" \
  && pass_test

#############################################################################
# Test 8: common.sh functions are sourced correctly
#############################################################################
start_test "common.sh functions work correctly"

source "$PROJECT_ROOT/helpers/common.sh"

# Test validate_jobs
if validate_jobs 4; then
  print_info "✓ validate_jobs accepts valid number"
else
  fail_test "validate_jobs rejected valid number"
  exit 1
fi

if validate_jobs "abc" 2>/dev/null; then
  fail_test "validate_jobs should reject non-numeric"
  exit 1
else
  print_info "✓ validate_jobs rejects non-numeric"
fi

# Test count_samples
IN="$TEST_DIR/test8_in"
create_mock_samples "$IN" "single" "a" "b" "c"
count=$(count_samples "$IN")
assert_equals "$count" 3 "count_samples should return 3" \
  && pass_test

#############################################################################
# Test 9: common.sh find_paired_reads function
#############################################################################
start_test "common.sh find_paired_reads works correctly"

source "$PROJECT_ROOT/helpers/common.sh"

IN="$TEST_DIR/test9_in"
create_mock_samples "$IN" "paired" "sample1"

mapfile -t reads < <(find_paired_reads "$IN/sample1" "*_R1.fastq.gz" "*_R2.fastq.gz")
r1="${reads[0]:-}"
r2="${reads[1]:-}"

if [[ -n "$r1" ]] && [[ -n "$r2" ]] && [[ -f "$r1" ]] && [[ -f "$r2" ]]; then
  print_info "✓ Found paired reads: $(basename "$r1"), $(basename "$r2")"
  pass_test
else
  fail_test "find_paired_reads failed to locate files"
fi

#############################################################################
# Test 10: common.sh validate_paired_input function
#############################################################################
start_test "common.sh validate_paired_input catches problems"

source "$PROJECT_ROOT/helpers/common.sh"

OUT="$TEST_DIR/test10_out"
mkdir -p "$OUT/test"
fail_marker="$OUT/test/.failed"

# Test with missing files
if validate_paired_input "" "" "test" "$fail_marker" 2>/dev/null; then
  fail_test "Should have failed on empty paths"
else
  print_info "✓ Correctly rejected empty paths"
fi

# Test with valid files
IN="$TEST_DIR/test10_in"
create_mock_samples "$IN" "paired-fixed" "sample1"
r1="$IN/sample1/R1.fastq.gz"
r2="$IN/sample1/R2.fastq.gz"

if validate_paired_input "$r1" "$r2" "sample1" "$fail_marker" 2>/dev/null; then
  print_info "✓ Correctly accepted valid paired files"
  pass_test
else
  fail_test "Should have accepted valid paired files"
fi

# Print summary
print_test_summary "${BASH_SOURCE[0]}"
