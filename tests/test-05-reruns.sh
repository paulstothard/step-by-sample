#!/usr/bin/env bash
# Test rerun scenarios and recovery workflows
# Tests MODE switches, repair-failed, FORCE behavior, etc.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_header "Testing Rerun Scenarios and Recovery"

# Setup
setup_test_dir "reruns"
trap cleanup_test_dir EXIT

# Helper to create a simple build script
create_rerun_build_script() {
  local script_path="$1"
  local in_dir="$2"
  local out_dir="$3"
  local job_dir="$4"
  local list="$5"

  cat >"$script_path" <<'BUILD_EOF'
#!/usr/bin/env bash
set -euo pipefail

IN="INPUT_DIR"
OUT="OUTPUT_DIR"
JOB_DIR="JOB_DIR_PATH"
LIST="RUN_LIST_PATH"
MODE="${MODE:-unfinished}"
FORCE="${FORCE:-0}"

mkdir -p "$OUT" "$JOB_DIR"
: > "$LIST"

while IFS= read -r -d '' sample_dir; do
  sample="$(basename "$sample_dir")"
  out_dir="$OUT/$sample"
  done="$out_dir/.done"
  fail="$out_dir/.failed"
  job="$JOB_DIR/$sample.sh"

  f="$sample_dir/data.txt"
  [[ ! -f "$f" ]] && continue

  should_run=0

  if [[ "$FORCE" -eq 1 ]]; then
    should_run=1
  elif [[ "$MODE" = "all" ]]; then
    should_run=1
  elif [[ "$MODE" = "unfinished" ]]; then
    [[ ! -f "$done" ]] && should_run=1
  elif [[ "$MODE" = "failed" ]]; then
    [[ -f "$fail" ]] && should_run=1
  fi

  [[ "$should_run" -eq 0 ]] && continue

  cat > "$job" <<'JOB_EOF'
#!/usr/bin/env bash
set -euo pipefail
sample="SAMPLE"
out_dir="OUT_SAMPLE"
mkdir -p "$out_dir"
rm -f "$out_dir/.failed" "$out_dir/.done"

if {
  echo "Processing $sample"
  if [[ "$sample" == *"fail"* ]]; then
    echo "Intentional failure for $sample" >&2
    false
  else
    echo "SUCCESS" > "$out_dir/result.txt"
  fi
} > "$out_dir/run.log" 2>&1; then
  touch "$out_dir/.done"
  exit 0
else
  touch "$out_dir/.failed"
  exit 1
fi
JOB_EOF

  sed -i.bak "s|OUT_SAMPLE|$out_dir|g" "$job"
  sed -i.bak "s|SAMPLE|$sample|g" "$job"
  rm -f "$job.bak"
  chmod +x "$job"
  echo "$job" >> "$LIST"
done < <(find "$IN" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
BUILD_EOF

  sed -i.bak "s|INPUT_DIR|$in_dir|g" "$script_path"
  sed -i.bak "s|OUTPUT_DIR|$out_dir|g" "$script_path"
  sed -i.bak "s|JOB_DIR_PATH|$job_dir|g" "$script_path"
  sed -i.bak "s|RUN_LIST_PATH|$list|g" "$script_path"
  rm -f "$script_path.bak"
  chmod +x "$script_path"
}

#############################################################################
# Test 1: Complete workflow - initial run with failures
#############################################################################
start_test "Initial run - mix of success and failures"

IN="$TEST_DIR/test1_in"
OUT="$TEST_DIR/test1_out"
JOB_DIR="$TEST_DIR/test1_jobs"
LIST="$TEST_DIR/test1_list.txt"
BUILDER="$TEST_DIR/test1_build.sh"

create_mock_samples "$IN" "single" "ok1" "fail1" "ok2" "fail2" "ok3"
create_rerun_build_script "$BUILDER" "$IN" "$OUT" "$JOB_DIR" "$LIST"

MODE="all" bash "$BUILDER" >/dev/null 2>&1
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2 >/dev/null 2>&1 || true

assert_count_equals "$(count_done "$OUT")" 3 "3 samples should succeed" \
  && assert_count_equals "$(count_failed "$OUT")" 2 "2 samples should fail" \
  && pass_test

#############################################################################
# Test 2: MODE=failed rebuilds only failed samples
#############################################################################
start_test "MODE=failed rebuilds only failed samples"

# Continue from test 1
MODE="failed" bash "$BUILDER" >/dev/null 2>&1

n_jobs=$(wc -l <"$LIST" | tr -d ' ')
assert_count_equals "$n_jobs" 2 "Should create jobs for 2 failed samples" \
  && assert_file_exists "$JOB_DIR/fail1.sh" \
  && assert_file_exists "$JOB_DIR/fail2.sh" \
  && pass_test

#############################################################################
# Test 3: MODE=unfinished rebuilds incomplete samples
#############################################################################
start_test "MODE=unfinished skips done, includes failed"

IN="$TEST_DIR/test3_in"
OUT="$TEST_DIR/test3_out"
JOB_DIR="$TEST_DIR/test3_jobs"
LIST="$TEST_DIR/test3_list.txt"
BUILDER="$TEST_DIR/test3_build.sh"

create_mock_samples "$IN" "single" "done1" "notdone1" "failed1" "done2"
create_rerun_build_script "$BUILDER" "$IN" "$OUT" "$JOB_DIR" "$LIST"

# Pre-populate with statuses
mkdir -p "$OUT/done1" "$OUT/failed1" "$OUT/done2"
touch "$OUT/done1/.done"
touch "$OUT/failed1/.failed"
touch "$OUT/done2/.done"

MODE="unfinished" bash "$BUILDER" >/dev/null 2>&1

n_jobs=$(wc -l <"$LIST" | tr -d ' ')
# Should include notdone1 and failed1, but not done1 or done2
assert_count_equals "$n_jobs" 2 "Should create 2 jobs (notdone + failed)" \
  && assert_file_exists "$JOB_DIR/notdone1.sh" \
  && assert_file_exists "$JOB_DIR/failed1.sh" \
  && assert_file_not_exists "$JOB_DIR/done1.sh" \
  && pass_test

#############################################################################
# Test 4: repair-failed.sh prepares for rerun
#############################################################################
start_test "repair-failed.sh removes failure markers"

IN="$TEST_DIR/test4_in"
OUT="$TEST_DIR/test4_out"
JOB_DIR="$TEST_DIR/test4_jobs"
LIST="$TEST_DIR/test4_list.txt"
BUILDER="$TEST_DIR/test4_build.sh"

create_mock_samples "$IN" "single" "sample1" "sample2"
create_rerun_build_script "$BUILDER" "$IN" "$OUT" "$JOB_DIR" "$LIST"

# Set up failed samples
mkdir -p "$OUT/sample1" "$OUT/sample2"
touch "$OUT/sample1/.failed"
touch "$OUT/sample2/.failed"

# Repair
bash "$PROJECT_ROOT/helpers/repair-failed.sh" "$OUT" >/dev/null 2>&1

assert_file_not_exists "$OUT/sample1/.failed" \
  && assert_file_not_exists "$OUT/sample2/.failed" \
  && print_info "✓ Failure markers removed"

# Now rebuild with MODE=unfinished should include them
MODE="unfinished" bash "$BUILDER" >/dev/null 2>&1
n_jobs=$(wc -l <"$LIST" | tr -d ' ')

assert_count_equals "$n_jobs" 2 "After repair, both should be unfinished" \
  && pass_test

#############################################################################
# Test 5: Complete recovery workflow
#############################################################################
start_test "Complete recovery workflow: fail → repair → rerun"

IN="$TEST_DIR/test5_in"
OUT="$TEST_DIR/test5_out"
JOB_DIR="$TEST_DIR/test5_jobs"
LIST="$TEST_DIR/test5_list.txt"
BUILDER="$TEST_DIR/test5_build.sh"

# Create samples - some will "fail" on first attempt
create_mock_samples "$IN" "single" "ok" "fail1" "fail2"
create_rerun_build_script "$BUILDER" "$IN" "$OUT" "$JOB_DIR" "$LIST"

# Initial run
MODE="all" bash "$BUILDER" >/dev/null 2>&1
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2 >/dev/null 2>&1 || true

initial_done=$(count_done "$OUT")
initial_failed=$(count_failed "$OUT")

print_info "Initial: $initial_done done, $initial_failed failed"

# Repair failed samples
bash "$PROJECT_ROOT/helpers/repair-failed.sh" "$OUT" >/dev/null 2>&1

# Change the sample names so they won't fail this time
# (In real life, you'd fix the data or code)
mv "$IN/fail1" "$IN/recovered1" 2>/dev/null || true
mv "$IN/fail2" "$IN/recovered2" 2>/dev/null || true

create_mock_samples "$IN" "single" "recovered1" "recovered2"

# Rebuild for unfinished
MODE="unfinished" bash "$BUILDER" >/dev/null 2>&1
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2 >/dev/null 2>&1

final_done=$(count_done "$OUT")
assert_count_equals "$final_done" 3 "After recovery, all should be done" \
  && pass_test

#############################################################################
# Test 6: FORCE in Approach 2
#############################################################################
start_test "FORCE=1 rebuilds all samples regardless of status"

IN="$TEST_DIR/test6_in"
OUT="$TEST_DIR/test6_out"
JOB_DIR="$TEST_DIR/test6_jobs"
LIST="$TEST_DIR/test6_list.txt"
BUILDER="$TEST_DIR/test6_build.sh"

create_mock_samples "$IN" "single" "s1" "s2" "s3"
create_rerun_build_script "$BUILDER" "$IN" "$OUT" "$JOB_DIR" "$LIST"

# Mark all as done
mkdir -p "$OUT/s1" "$OUT/s2" "$OUT/s3"
touch "$OUT/s1/.done"
touch "$OUT/s2/.done"
touch "$OUT/s3/.done"

# Build with FORCE=1
FORCE=1 bash "$BUILDER" >/dev/null 2>&1

n_jobs=$(wc -l <"$LIST" | tr -d ' ')
assert_count_equals "$n_jobs" 3 "FORCE=1 should create jobs for all samples" \
  && pass_test

#############################################################################
# Test 7: Incremental reruns - adding new samples
#############################################################################
start_test "Adding new samples and using MODE=unfinished"

IN="$TEST_DIR/test7_in"
OUT="$TEST_DIR/test7_out"
JOB_DIR="$TEST_DIR/test7_jobs"
LIST="$TEST_DIR/test7_list.txt"
BUILDER="$TEST_DIR/test7_build.sh"

# Initial samples
create_mock_samples "$IN" "single" "s1" "s2"
create_rerun_build_script "$BUILDER" "$IN" "$OUT" "$JOB_DIR" "$LIST"

MODE="all" bash "$BUILDER" >/dev/null 2>&1
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2 >/dev/null 2>&1

assert_count_equals "$(count_done "$OUT")" 2 \
  && print_info "✓ Initial 2 samples completed"

# Add new samples
create_mock_samples "$IN" "single" "s3" "s4"

# Rebuild with MODE=unfinished
MODE="unfinished" bash "$BUILDER" >/dev/null 2>&1

n_jobs=$(wc -l <"$LIST" | tr -d ' ')
assert_count_equals "$n_jobs" 2 "Should create jobs for 2 new samples only" \
  && assert_file_exists "$JOB_DIR/s3.sh" \
  && assert_file_exists "$JOB_DIR/s4.sh" \
  && pass_test

#############################################################################
# Test 8: repair-failed.sh --clean-outputs for complete reset
#############################################################################
start_test "repair-failed.sh --clean-outputs removes partial work"

OUT="$TEST_DIR/test8_out"

mkdir -p "$OUT/failed"
touch "$OUT/failed/.failed"
echo "log" >"$OUT/failed/run.log"
echo "partial" >"$OUT/failed/partial_output.txt"
mkdir -p "$OUT/failed/subdir"
echo "data" >"$OUT/failed/subdir/data.txt"

bash "$PROJECT_ROOT/helpers/repair-failed.sh" "$OUT" --clean-outputs >/dev/null 2>&1

assert_file_not_exists "$OUT/failed/.failed" \
  && assert_file_not_exists "$OUT/failed/partial_output.txt" \
  && assert_dir_exists "$OUT/failed" "Directory should still exist" \
  && assert_file_exists "$OUT/failed/run.log" "Log should be preserved" \
  && pass_test

#############################################################################
# Test 9: Multiple rerun cycles
#############################################################################
start_test "Multiple rerun cycles converge to completion"

IN="$TEST_DIR/test9_in"
OUT="$TEST_DIR/test9_out"
JOB_DIR="$TEST_DIR/test9_jobs"
LIST="$TEST_DIR/test9_list.txt"
BUILDER="$TEST_DIR/test9_build.sh"

create_mock_samples "$IN" "single" "ok1" "fail1" "ok2"
create_rerun_build_script "$BUILDER" "$IN" "$OUT" "$JOB_DIR" "$LIST"

# Run 1
MODE="all" bash "$BUILDER" >/dev/null 2>&1
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2 >/dev/null 2>&1 || true
run1_done=$(count_done "$OUT")

print_info "Run 1: $run1_done done"

# Repair and "fix" the failing sample
bash "$PROJECT_ROOT/helpers/repair-failed.sh" "$OUT" >/dev/null 2>&1
mv "$IN/fail1" "$IN/ok_fixed" 2>/dev/null || true
create_mock_samples "$IN" "single" "ok_fixed"

# Run 2 - only unfinished
MODE="unfinished" bash "$BUILDER" >/dev/null 2>&1
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2 >/dev/null 2>&1 || true
run2_done=$(count_done "$OUT")

print_info "Run 2: $run2_done done"

assert_count_equals "$run2_done" 3 "Eventually all samples complete" \
  && pass_test

# Print summary
print_test_summary "${BASH_SOURCE[0]}"
