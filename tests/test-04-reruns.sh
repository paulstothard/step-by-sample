#!/usr/bin/env bash
# Exercise rerun and recovery behavior against the real workflow template.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/mock-commands.sh"

PROJECT_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEMPLATE="$PROJECT_ROOT/templates/generate-jobs-template.sh"

print_header "Testing Rerun Scenarios and Recovery"

setup_test_dir "reruns"
trap cleanup_test_dir EXIT

MOCK_BIN="$TEST_DIR/mock-bin"
mkdir -p "$MOCK_BIN"

for mock_func in mock_success mock_fail mock_conditional_fail; do
  cat >"$MOCK_BIN/$mock_func" <<MOCK_EOF
#!/usr/bin/env bash
source "$SCRIPT_DIR/lib/mock-commands.sh"
$mock_func "\$@"
MOCK_EOF
  chmod +x "$MOCK_BIN/$mock_func"
done

run_template() {
  local test_command="$1"
  local in_dir="$2"
  local out_dir="$3"
  local job_dir="$4"
  local list="$5"
  local mode="${6:-unfinished}"
  local force="${7:-0}"

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
start_test "Initial real workflow records mixed success and failure"

IN="$TEST_DIR/test1_in"
OUT="$TEST_DIR/test1_out"
JOB_DIR="$TEST_DIR/test1_jobs"
LIST="$TEST_DIR/test1_list.txt"
create_mock_samples "$IN" single ok1 fail1 ok2 fail2 ok3

run_template mock_conditional_fail "$IN" "$OUT" "$JOB_DIR" "$LIST" all >/dev/null
bash "$PROJECT_ROOT/bin/run-jobs-local.sh" "$LIST" 3 >/dev/null 2>&1 || true

assert_count_equals "$(count_done "$OUT")" 3 "Three samples should succeed" \
  && assert_count_equals "$(count_failed "$OUT")" 2 "Two samples should fail" \
  && pass_test

#############################################################################
start_test "MODE=failed rebuilds only failed real jobs"

run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" failed >/dev/null

assert_count_equals "$(wc -l <"$LIST" | tr -d ' ')" 2 "Only failed jobs should be listed" \
  && assert_file_exists "$JOB_DIR/fail1.sh" \
  && assert_file_exists "$JOB_DIR/fail2.sh" \
  && assert_file_not_exists "$JOB_DIR/ok1.sh" "Stale completed job should be removed" \
  && pass_test

#############################################################################
start_test "Failed jobs recover without repairing markers first"

bash "$PROJECT_ROOT/bin/run-jobs-local.sh" "$LIST" 2 >/dev/null 2>&1

assert_count_equals "$(count_done "$OUT")" 5 "All samples should now be done" \
  && assert_count_equals "$(count_failed "$OUT")" 0 "Failure markers should be cleared" \
  && pass_test

#############################################################################
start_test "reset-failed-samples requires MODE=unfinished afterward"

IN="$TEST_DIR/test4_in"
OUT="$TEST_DIR/test4_out"
JOB_DIR="$TEST_DIR/test4_jobs"
LIST="$TEST_DIR/test4_list.txt"
create_mock_samples "$IN" single sample1 sample2
mkdir -p "$OUT/sample1" "$OUT/sample2"
touch "$OUT/sample1/.failed" "$OUT/sample2/.failed"

bash "$PROJECT_ROOT/bin/reset-failed-samples.sh" "$OUT" >/dev/null
run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" failed >/dev/null
failed_mode_count=$(wc -l <"$LIST" | tr -d ' ')
run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" unfinished >/dev/null
unfinished_count=$(wc -l <"$LIST" | tr -d ' ')

assert_count_equals "$failed_mode_count" 0 "Repaired samples no longer match MODE=failed" \
  && assert_count_equals "$unfinished_count" 2 "Repaired samples match MODE=unfinished" \
  && pass_test

#############################################################################
start_test "Complete repair and rerun workflow converges"

bash "$PROJECT_ROOT/bin/run-jobs-local.sh" "$LIST" 2 >/dev/null 2>&1

assert_count_equals "$(count_done "$OUT")" 2 "Both repaired samples should complete" \
  && pass_test

#############################################################################
start_test "FORCE=1 rebuilds completed samples"

run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" unfinished 1 >/dev/null

assert_count_equals "$(wc -l <"$LIST" | tr -d ' ')" 2 "FORCE should list all samples" \
  && pass_test

#############################################################################
start_test "New samples are selected by MODE=unfinished"

bash "$PROJECT_ROOT/bin/run-jobs-local.sh" "$LIST" 2 >/dev/null 2>&1
create_mock_samples "$IN" single sample3 sample4
run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" unfinished >/dev/null

assert_count_equals "$(wc -l <"$LIST" | tr -d ' ')" 2 "Only new samples should be listed" \
  && assert_file_exists "$JOB_DIR/sample3.sh" \
  && assert_file_exists "$JOB_DIR/sample4.sh" \
  && assert_file_not_exists "$JOB_DIR/sample1.sh" "Completed job should not remain stale" \
  && pass_test

#############################################################################
start_test "repair --clean-outputs removes partial work but keeps the log"

OUT="$TEST_DIR/test8_out"
mkdir -p "$OUT/failed/subdir"
touch "$OUT/failed/.failed"
echo "log" >"$OUT/failed/run.log"
echo "partial" >"$OUT/failed/partial.txt"
echo "nested" >"$OUT/failed/subdir/nested.txt"

bash "$PROJECT_ROOT/bin/reset-failed-samples.sh" "$OUT" --clean-outputs >/dev/null

assert_file_not_exists "$OUT/failed/.failed" \
  && assert_file_not_exists "$OUT/failed/partial.txt" \
  && assert_file_exists "$OUT/failed/run.log" "Previous log should be preserved" \
  && pass_test

#############################################################################
start_test "Multiple real rerun cycles converge to completion"

IN="$TEST_DIR/test9_in"
OUT="$TEST_DIR/test9_out"
JOB_DIR="$TEST_DIR/test9_jobs"
LIST="$TEST_DIR/test9_list.txt"
create_mock_samples "$IN" single ok fail-once

run_template mock_conditional_fail "$IN" "$OUT" "$JOB_DIR" "$LIST" all >/dev/null
bash "$PROJECT_ROOT/bin/run-jobs-local.sh" "$LIST" 2 >/dev/null 2>&1 || true
run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" failed >/dev/null
bash "$PROJECT_ROOT/bin/run-jobs-local.sh" "$LIST" 1 >/dev/null 2>&1
run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" unfinished >/dev/null

assert_count_equals "$(count_done "$OUT")" 2 "Both samples should eventually complete" \
  && assert_count_equals "$(wc -l <"$LIST" | tr -d ' ')" 0 "No unfinished jobs should remain" \
  && pass_test

print_test_summary "${BASH_SOURCE[0]}"
