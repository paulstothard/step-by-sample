#!/usr/bin/env bash
# Test Approach 2: build-jobs + execution
# Tests the ACTUAL build-jobs-template.sh, not a copy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/mock-commands.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$PROJECT_ROOT/examples/build-jobs-template.sh"

print_header "Testing Approach 2: Build Jobs + Execution (Real Template)"

# Setup
setup_test_dir "approach2"
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
run_build_template() {
  local test_command="$1"
  local in_dir="$2"
  local out_dir="$3"
  local job_dir="$4"
  local list="$5"
  local mode="${6:-unfinished}"
  local force="${7:-0}"

  # Add mock commands to PATH and run the ACTUAL build template
  PATH="$MOCK_BIN:$PATH" \
    TEST_COMMAND="$test_command" \
    IN="$in_dir" \
    OUT="$out_dir" \
    JOB_DIR="$job_dir" \
    LIST="$list" \
    MODE="$mode" \
    FORCE="$force" \
    bash "$TEMPLATE"
}

#############################################################################
# Test 1: Build jobs with MODE=all
#############################################################################
start_test "Build jobs for all samples"

IN="$TEST_DIR/test1_in"
OUT="$TEST_DIR/test1_out"
JOB_DIR="$TEST_DIR/test1_jobs"
LIST="$TEST_DIR/test1_list.txt"

create_mock_samples "$IN" 3 single

run_build_template "mock_success" "$IN" "$OUT" "$JOB_DIR" "$LIST" "all" 0 >/dev/null 2>&1

TEST1_OUT="$OUT"
TEST1_JOB_DIR="$JOB_DIR"
TEST1_LIST="$LIST"

assert_file_exists "$LIST" \
  && assert_count_equals "$(wc -l <"$LIST" | tr -d ' ')" 3 "Should create 3 job scripts" \
  && assert_file_exists "$JOB_DIR/sample_01.sh" \
  && assert_file_exists "$JOB_DIR/sample_02.sh" \
  && assert_file_exists "$JOB_DIR/sample_03.sh" \
  && pass_test

#############################################################################
# Test 2: Execute jobs with run-list-local.sh
#############################################################################
start_test "Execute jobs locally with run-list-local.sh"

# Use jobs from previous test
if bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$TEST1_LIST" 2 >/dev/null 2>&1; then
  assert_count_equals "$(count_done "$TEST1_OUT")" 3 "All 3 samples should complete" \
    && assert_count_equals "$(count_failed "$TEST1_OUT")" 0 "No failures expected" \
    && assert_file_exists "$TEST1_OUT/sample_01/.done" \
    && assert_file_exists "$TEST1_OUT/sample_02/run.log" \
    && pass_test
else
  fail_test "run-list-local.sh execution failed"
fi

#############################################################################
# Test 3: MODE=unfinished only builds incomplete jobs
#############################################################################
start_test "MODE=unfinished skips completed samples"

IN="$TEST_DIR/test3_in"
OUT="$TEST_DIR/test3_out"
JOB_DIR="$TEST_DIR/test3_jobs"
LIST="$TEST_DIR/test3_list.txt"

create_mock_samples "$IN" 3 single

# Pre-mark some as done
mkdir -p "$OUT/sample_01" "$OUT/sample_03"
touch "$OUT/sample_01/.done"
touch "$OUT/sample_03/.done"

run_build_template "mock_success" "$IN" "$OUT" "$JOB_DIR" "$LIST" "unfinished" 0 >/dev/null 2>&1

n_jobs=$(wc -l <"$LIST" | tr -d ' ')
assert_count_equals "$n_jobs" 1 "Only 1 unfinished sample should get a job" \
  && assert_file_exists "$JOB_DIR/sample_02.sh" \
  && assert_file_not_exists "$JOB_DIR/sample_01.sh" "Should not create job for completed sample" \
  && pass_test

#############################################################################
# Test 4: MODE=failed only builds failed jobs
#############################################################################
start_test "MODE=failed only builds jobs for failed samples"

IN="$TEST_DIR/test4_in"
OUT="$TEST_DIR/test4_out"
JOB_DIR="$TEST_DIR/test4_jobs"
LIST="$TEST_DIR/test4_list.txt"

create_mock_samples "$IN" 4 single

# Pre-mark with different statuses
mkdir -p "$OUT/sample_01" "$OUT/sample_02" "$OUT/sample_03" "$OUT/sample_04"
touch "$OUT/sample_01/.done"
touch "$OUT/sample_02/.failed"
touch "$OUT/sample_03/.done"
touch "$OUT/sample_04/.failed"

run_build_template "mock_success" "$IN" "$OUT" "$JOB_DIR" "$LIST" "failed" 0 >/dev/null 2>&1

n_jobs=$(wc -l <"$LIST" | tr -d ' ')
assert_count_equals "$n_jobs" 2 "Only 2 failed samples should get jobs" \
  && assert_file_exists "$JOB_DIR/sample_02.sh" \
  && assert_file_exists "$JOB_DIR/sample_04.sh" \
  && assert_file_not_exists "$JOB_DIR/sample_01.sh" \
  && pass_test

#############################################################################
# Test 5: Run single job script directly
#############################################################################
start_test "Execute individual job script directly"

# Use job from test 1
if bash "$TEST1_JOB_DIR/sample_01.sh" >/dev/null 2>&1; then
  assert_file_exists "$TEST1_OUT/sample_01/.done" \
    && assert_file_exists "$TEST1_OUT/sample_01/run.log" \
    && assert_log_contains "$TEST1_OUT/sample_01/run.log" "sample_01" \
    && pass_test
else
  fail_test "Direct job execution failed"
fi

#############################################################################
# Test 6: Mock Slurm submission
#############################################################################
start_test "Submit jobs via mock sbatch"

IN="$TEST_DIR/test6_in"
OUT="$TEST_DIR/test6_out"
JOB_DIR="$TEST_DIR/test6_jobs"
LIST="$TEST_DIR/test6_list.txt"

create_mock_samples "$IN" 2 single

run_build_template "mock_success" "$IN" "$OUT" "$JOB_DIR" "$LIST" "all" 0 >/dev/null 2>&1

# Add mock sbatch to PATH temporarily
export PATH="$SCRIPT_DIR/mock-slurm:$PATH"

# Submit via run-list-slurm.sh
output=$(bash "$PROJECT_ROOT/helpers/run-list-slurm.sh" "$LIST" \
  --account test \
  --partition cpu \
  --log-dir "$TEST_DIR/slurm-logs" 2>&1)

# Check submission message
if echo "$output" | grep -q "Submitted batch job"; then
  print_info "✓ Slurm submission succeeded"

  # Wait for mock jobs to complete
  sleep 2

  assert_count_equals "$(count_done "$OUT")" 2 "Both samples should complete via Slurm" \
    && pass_test
else
  fail_test "Slurm submission failed"
fi

# Print summary
print_test_summary "${BASH_SOURCE[0]}"
