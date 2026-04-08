#!/usr/bin/env bash
# Test Approach 1: single-local-template.sh
# Tests the ACTUAL template file, not a copy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/mock-commands.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$PROJECT_ROOT/examples/single-local-template.sh"

print_header "Testing Approach 1: Single Local Template (Real Template)"

# Setup
setup_test_dir "approach1"
trap cleanup_test_dir EXIT

# Create executable mock commands in test directory
MOCK_BIN="$TEST_DIR/mock-bin"
mkdir -p "$MOCK_BIN"

for mock_func in mock_success mock_fail mock_conditional_fail mock_slow; do
  cat >"$MOCK_BIN/$mock_func" <<MOCK_EOF
#!/usr/bin/env bash
source "$SCRIPT_DIR/lib/mock-commands.sh"
$mock_func "\$@"
MOCK_EOF
  chmod +x "$MOCK_BIN/$mock_func"
done

# Helper to run the actual template with test parameters
run_template() {
  local test_command="$1"
  local in_dir="$2"
  local out_dir="$3"
  local jobs="${4:-2}"
  local force="${5:-0}"
  local dry="${6:-0}"

  # Add mock commands to PATH and run the ACTUAL template
  PATH="$MOCK_BIN:$PATH" \
    TEST_COMMAND="$test_command" \
    IN="$in_dir" \
    OUT="$out_dir" \
    JOBS="$jobs" \
    FORCE="$force" \
    DRY="$dry" \
    bash "$TEMPLATE"
}

#############################################################################
# Test 1: Basic successful execution
#############################################################################
start_test "Basic execution - all samples succeed"

IN="$TEST_DIR/test1_in"
OUT="$TEST_DIR/test1_out"

create_mock_samples "$IN" 3 single

if run_template "mock_success" "$IN" "$OUT" 2 0 0 >/dev/null 2>&1; then
  assert_count_equals 3 "$(count_done "$OUT")" "All 3 samples should be done" \
    && assert_count_equals 0 "$(count_failed "$OUT")" "No samples should fail" \
    && assert_file_exists "$OUT/sample_01/.done" \
    && assert_file_exists "$OUT/sample_02/run.log" \
    && pass_test
else
  fail_test "Template execution failed"
fi

#############################################################################
# Test 2: Partial failures
#############################################################################
start_test "Partial failures - some samples fail"

IN="$TEST_DIR/test2_in"
OUT="$TEST_DIR/test2_out"

# Create samples with one named to trigger failure
create_mock_samples "$IN" single sample_ok sample_fail sample_good

run_template "mock_conditional_fail" "$IN" "$OUT" 2 0 0 >/dev/null 2>&1 || true

assert_count_equals 2 "$(count_done "$OUT")" "2 samples should succeed" \
  && assert_count_equals 1 "$(count_failed "$OUT")" "1 sample should fail" \
  && assert_file_exists "$OUT/sample_ok/.done" \
  && assert_file_exists "$OUT/sample_fail/.failed" \
  && assert_file_exists "$OUT/sample_good/.done" \
  && pass_test

#############################################################################
# Test 3: FORCE rerun
#############################################################################
start_test "FORCE=1 reruns completed samples"

IN="$TEST_DIR/test3_in"
OUT="$TEST_DIR/test3_out"

create_mock_samples "$IN" 1 single

# First run
run_template "mock_success" "$IN" "$OUT" 2 0 0 >/dev/null 2>&1
first_result=$(cat "$OUT/sample_01/result.txt")

# Second run without FORCE - should skip
run_template "mock_success" "$IN" "$OUT" 2 0 0 >/dev/null 2>&1
second_result=$(cat "$OUT/sample_01/result.txt")

if [[ "$first_result" == "$second_result" ]]; then
  print_info "✓ Sample skipped without FORCE"
else
  fail_test "Sample was rerun when it shouldn't be"
  exit 1
fi

# Third run with FORCE=1 - should rerun
sleep 0.1
run_template "mock_success" "$IN" "$OUT" 2 1 0 >/dev/null 2>&1
third_result=$(cat "$OUT/sample_01/result.txt")

if [[ "$first_result" != "$third_result" ]]; then
  print_info "✓ Sample rerun with FORCE=1"
  pass_test
else
  fail_test "Sample was not rerun with FORCE=1"
fi

#############################################################################
# Test 4: DRY run
#############################################################################
start_test "DRY=1 doesn't execute commands"

IN="$TEST_DIR/test4_in"
OUT="$TEST_DIR/test4_out"

create_mock_samples "$IN" 1 single

run_template "mock_success" "$IN" "$OUT" 2 0 1 >/dev/null 2>&1

assert_dir_exists "$OUT/sample_01" \
  && assert_file_not_exists "$OUT/sample_01/.done" \
  && assert_file_not_exists "$OUT/sample_01/.failed" \
  && assert_file_not_exists "$OUT/sample_01/result.txt" \
  && pass_test

#############################################################################
# Test 5: Parallel execution
#############################################################################
start_test "Parallel execution with JOBS parameter"

IN="$TEST_DIR/test5_in"
OUT="$TEST_DIR/test5_out"

create_mock_samples "$IN" 4 single

# Measure time - mock_slow sleeps 1s by default
start=$(date +%s)
MOCK_SLOW_DURATION=0.5 run_template "mock_slow" "$IN" "$OUT" 4 0 0 >/dev/null 2>&1
end=$(date +%s)
elapsed=$((end - start))

# With 4 samples sleeping 0.5s each, parallel should take ~1s, sequential ~2s
assert_count_equals 4 "$(count_done "$OUT")" "All 4 samples should complete" \
  && print_info "Parallel execution took ${elapsed}s (should be < 2s)" \
  && pass_test

#############################################################################
# Test 6: Missing input handling
#############################################################################
start_test "Missing input files are handled correctly"

IN="$TEST_DIR/test6_in"
OUT="$TEST_DIR/test6_out"

# Create sample dir but no data file (data.txt is required by template)
mkdir -p "$IN/sample_nofile"

run_template "mock_success" "$IN" "$OUT" 2 0 0 >/dev/null 2>&1 || true

assert_count_equals 0 "$(count_done "$OUT")" "No samples should succeed" \
  && assert_count_equals 1 "$(count_failed "$OUT")" "Sample with missing input should fail" \
  && assert_file_exists "$OUT/sample_nofile/.failed" \
  && pass_test

# Print summary
print_test_summary "${BASH_SOURCE[0]}"
