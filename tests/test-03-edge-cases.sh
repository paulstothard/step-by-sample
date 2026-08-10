#!/usr/bin/env bash
# Exercise edge cases against the real workflow template and helper scripts.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/mock-commands.sh"

PROJECT_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)"
TEMPLATE="$PROJECT_ROOT/examples/build-jobs-template.sh"

print_header "Testing Edge Cases and Robustness"

setup_test_dir "edge-cases"
trap cleanup_test_dir EXIT

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

run_template() {
  local test_command="$1"
  local in_dir="$2"
  local out_dir="$3"
  local job_dir="$4"
  local list="$5"
  local mode="${6:-all}"
  local force="${7:-0}"
  local strict="${8:-0}"

  PATH="$MOCK_BIN:$PATH" \
    TEST_COMMAND="$test_command" \
    IN="$in_dir" \
    OUT="$out_dir" \
    JOB_DIR="$job_dir" \
    LIST="$list" \
    MODE="$mode" \
    FORCE="$force" \
    STRICT="$strict" \
    bash "$TEMPLATE"
}

#############################################################################
start_test "Relative paths work with a noisy CDPATH"

WORK="$TEST_DIR/test1_work"
mkdir -p "$WORK/input/sample1"
echo "data" >"$WORK/input/sample1/data.txt"

if (
  cd "$WORK"
  CDPATH=".:$TEST_DIR" \
    PATH="$MOCK_BIN:$PATH" \
    TEST_COMMAND=mock_success \
    IN=input OUT=output JOB_DIR=jobs LIST=run.txt MODE=all \
    bash "$TEMPLATE" >/dev/null 2>&1
); then
  assert_file_exists "$WORK/run.txt" \
    && assert_file_exists "$WORK/jobs/sample1.sh" \
    && pass_test
else
  fail_test "Template failed with relative paths and CDPATH"
fi

#############################################################################
start_test "Generated jobs preserve shell metacharacters in sample names"

IN="$TEST_DIR/test2_in"
OUT="$TEST_DIR/test2_out"
JOB_DIR="$TEST_DIR/test2_jobs"
LIST="$TEST_DIR/test2_list.txt"
special_names=('sample one' 'sample$HOME' 'sample"quote' 'sample`tick')

create_mock_samples "$IN" single "${special_names[@]}"
run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" all >/dev/null

syntax_ok=1
while IFS= read -r job; do
  bash -n "$job" || syntax_ok=0
done <"$LIST"

if [[ "$syntax_ok" -eq 1 ]] \
  && bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2 >/dev/null 2>&1; then
  checks_ok=1
  for sample in "${special_names[@]}"; do
    [[ -f "$OUT/$sample/.done" ]] || checks_ok=0
  done
  assert_equals "$checks_ok" 1 "Every exact sample name should complete" \
    && pass_test
else
  fail_test "A generated job was invalid or failed to run"
fi

#############################################################################
start_test "Real template handles fifty samples"

IN="$TEST_DIR/test3_in"
OUT="$TEST_DIR/test3_out"
JOB_DIR="$TEST_DIR/test3_jobs"
LIST="$TEST_DIR/test3_list.txt"
create_mock_samples "$IN" 50 single

run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" all >/dev/null
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 8 >/dev/null 2>&1

assert_count_equals "$(count_done "$OUT")" 50 "All fifty samples should complete" \
  && pass_test

#############################################################################
start_test "STRICT mode rejects missing sample inputs"

IN="$TEST_DIR/test4_in"
OUT="$TEST_DIR/test4_out"
JOB_DIR="$TEST_DIR/test4_jobs"
LIST="$TEST_DIR/test4_list.txt"
create_mock_samples "$IN" single good
create_mock_samples "$IN" empty missing

if output=$(run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" all 0 1 2>&1); then
  fail_test "STRICT=1 should fail when an input is missing"
else
  if grep -q "Missing input: 1" <<<"$output" \
    && grep -q "STRICT=1" <<<"$output" \
    && [[ $(wc -l <"$LIST" | tr -d ' ') -eq 1 ]]; then
    pass_test
  else
    fail_test "Strict-mode output did not identify the missing sample"
  fi
fi

#############################################################################
start_test "Symlinked sample directories are processed"

IN="$TEST_DIR/test5_in"
OUT="$TEST_DIR/test5_out"
JOB_DIR="$TEST_DIR/test5_jobs"
LIST="$TEST_DIR/test5_list.txt"
REAL="$TEST_DIR/test5_real/sample-link"
mkdir -p "$REAL" "$IN"
echo "data" >"$REAL/data.txt"
ln -s "$REAL" "$IN/sample-link"

run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" all >/dev/null
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 1 >/dev/null 2>&1

assert_file_exists "$OUT/sample-link/.done" \
  && pass_test

#############################################################################
start_test "Run lists ignore comments and blank lines"

IN="$TEST_DIR/test6_in"
OUT="$TEST_DIR/test6_out"
JOB_DIR="$TEST_DIR/test6_jobs"
LIST="$TEST_DIR/test6_list.txt"
DECORATED_LIST="$TEST_DIR/test6_decorated.txt"
create_mock_samples "$IN" single s1 s2
run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" all >/dev/null

{
  echo "# generated jobs"
  echo
  sed '1a\
# second job follows' "$LIST"
} >"$DECORATED_LIST"

bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$DECORATED_LIST" 2 >/dev/null 2>&1
assert_count_equals "$(count_done "$OUT")" 2 "Only runnable entries should execute" \
  && pass_test

#############################################################################
start_test "A per-sample lock prevents concurrent execution"

IN="$TEST_DIR/test7_in"
OUT="$TEST_DIR/test7_out"
JOB_DIR="$TEST_DIR/test7_jobs"
LIST="$TEST_DIR/test7_list.txt"
create_mock_samples "$IN" single sample1
run_template mock_slow "$IN" "$OUT" "$JOB_DIR" "$LIST" all >/dev/null
job="$JOB_DIR/sample1.sh"

MOCK_SLOW_DURATION=1 bash "$job" >/dev/null 2>&1 &
first_pid=$!

for _ in $(seq 1 50); do
  [[ -d "$OUT/sample1/.running" ]] && break
  sleep 0.02
done

set +e
second_output=$(bash "$job" 2>&1)
second_status=$?
set -e
wait "$first_pid"

if [[ "$second_status" -eq 75 ]] \
  && grep -q "BUSY" <<<"$second_output" \
  && [[ -f "$OUT/sample1/.done" ]] \
  && [[ ! -e "$OUT/sample1/.running" ]]; then
  pass_test
else
  fail_test "Concurrent execution was not rejected cleanly"
fi

#############################################################################
start_test "Completed samples produce an empty unfinished run list"

IN="$TEST_DIR/test8_in"
OUT="$TEST_DIR/test8_out"
JOB_DIR="$TEST_DIR/test8_jobs"
LIST="$TEST_DIR/test8_list.txt"
create_mock_samples "$IN" single sample1
run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" all >/dev/null
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 1 >/dev/null 2>&1
run_template mock_success "$IN" "$OUT" "$JOB_DIR" "$LIST" unfinished >/dev/null

assert_count_equals "$(wc -l <"$LIST" | tr -d ' ')" 0 "No completed sample should be listed" \
  && assert_file_not_exists "$JOB_DIR/sample1.sh" "Stale job should be removed" \
  && pass_test

#############################################################################
start_test "Invalid FORCE and STRICT values are rejected"

IN="$TEST_DIR/test9_in"
create_mock_samples "$IN" single sample1

if run_template mock_success "$IN" "$TEST_DIR/test9_out" "$TEST_DIR/test9_jobs" "$TEST_DIR/test9_list" all yes 0 >/dev/null 2>&1; then
  fail_test "Invalid FORCE value was accepted"
elif run_template mock_success "$IN" "$TEST_DIR/test9_out" "$TEST_DIR/test9_jobs" "$TEST_DIR/test9_list" all 0 yes >/dev/null 2>&1; then
  fail_test "Invalid STRICT value was accepted"
else
  pass_test
fi

#############################################################################
start_test "Status comparison reports samples without outputs"

IN="$TEST_DIR/test10_in"
OUT="$TEST_DIR/test10_out"
mkdir -p "$IN/done" "$IN/pending" "$OUT/done"
touch "$OUT/done/.done"

output=$(bash "$PROJECT_ROOT/helpers/summarize-status.sh" "$OUT" --input-dir "$IN")
if grep -q "PENDING pending" <<<"$output" \
  && grep -q "Done:    1" <<<"$output" \
  && grep -q "Other:   1" <<<"$output"; then
  pass_test
else
  fail_test "Input-aware status summary missed the pending sample"
fi

print_test_summary "${BASH_SOURCE[0]}"
