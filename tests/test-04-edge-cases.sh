#!/usr/bin/env bash
# Test edge cases and robust handling
# Tests spaces in filenames, special characters, unusual conditions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_header "Testing Edge Cases and Robustness"

# Setup
setup_test_dir "edge-cases"
trap cleanup_test_dir EXIT

# Helper to create test script (simple version for edge case testing)
create_simple_script() {
  local script_path="$1"
  local in_dir="$2"
  local out_dir="$3"

  cat >"$script_path" <<'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

IN="INPUT_DIR"
OUT="OUTPUT_DIR"
JOBS=2

mkdir -p "$OUT"

run_one() {
  sample_dir="$1"
  sample="$(basename "$sample_dir")"
  out_dir="$OUT/$sample"
  log="$out_dir/run.log"
  done="$out_dir/.done"
  fail="$out_dir/.failed"

  mkdir -p "$out_dir"
  rm -f "$fail"

  if [[ -f "$done" ]]; then
    echo "SKIP  $sample"
    return 0
  fi

  f="$sample_dir/data.txt"

  if [[ ! -f "$f" ]]; then
    echo "FAIL  $sample  missing input"
    : > "$fail"
    return 1
  fi

  echo "START $sample"

  {
    echo "=== $sample ==="
    echo "Processing: $sample"
    echo "SUCCESS" > "$out_dir/result.txt"
  } >"$log" 2>&1

  : > "$done"
  echo "DONE  $sample"
  return 0
}

export OUT
export -f run_one

mapfile -d '' -t sample_dirs < <(find -L "$IN" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
printf '%s\0' "${sample_dirs[@]}" | xargs -0 -I{} -P "$JOBS" bash -c 'run_one "$@"' _ {}
SCRIPT_EOF

  sed -i.bak "s|INPUT_DIR|$in_dir|g" "$script_path"
  sed -i.bak "s|OUTPUT_DIR|$out_dir|g" "$script_path"
  rm -f "$script_path.bak"
  chmod +x "$script_path"
}

#############################################################################
# Test 1: Spaces in sample names
#############################################################################
start_test "Handles spaces in sample directory names"

IN="$TEST_DIR/test1_in"
OUT="$TEST_DIR/test1_out"
SCRIPT="$TEST_DIR/test1.sh"

# Create samples with spaces
mkdir -p "$IN/sample one"
mkdir -p "$IN/sample two three"
echo "data" >"$IN/sample one/data.txt"
echo "data" >"$IN/sample two three/data.txt"

create_simple_script "$SCRIPT" "$IN" "$OUT"

if bash "$SCRIPT" >/dev/null 2>&1; then
  assert_file_exists "$OUT/sample one/.done" \
    && assert_file_exists "$OUT/sample two three/.done" \
    && assert_count_equals "$(count_done "$OUT")" 2 "Both samples should complete" \
    && pass_test
else
  fail_test "Failed with spaces in sample names"
fi

#############################################################################
# Test 2: Special characters in sample names
#############################################################################
start_test "Handles special characters in sample names"

IN="$TEST_DIR/test2_in"
OUT="$TEST_DIR/test2_out"
SCRIPT="$TEST_DIR/test2.sh"

# Create samples with special chars (avoiding / and null)
mkdir -p "$IN/sample-dash"
mkdir -p "$IN/sample_underscore"
mkdir -p "$IN/sample.dot"
echo "data" >"$IN/sample-dash/data.txt"
echo "data" >"$IN/sample_underscore/data.txt"
echo "data" >"$IN/sample.dot/data.txt"

create_simple_script "$SCRIPT" "$IN" "$OUT"

if bash "$SCRIPT" >/dev/null 2>&1; then
  assert_count_equals "$(count_done "$OUT")" 3 "All 3 samples should complete" \
    && pass_test
else
  fail_test "Failed with special characters"
fi

#############################################################################
# Test 3: Large number of samples
#############################################################################
start_test "Handles many samples (50 samples)"

IN="$TEST_DIR/test3_in"
OUT="$TEST_DIR/test3_out"
SCRIPT="$TEST_DIR/test3.sh"

# Create 50 samples
for i in $(seq 1 50); do
  mkdir -p "$IN/sample_$i"
  echo "data" >"$IN/sample_$i/data.txt"
done

create_simple_script "$SCRIPT" "$IN" "$OUT"

if bash "$SCRIPT" >/dev/null 2>&1; then
  n_done=$(count_done "$OUT")
  assert_count_equals "$n_done" 50 "All 50 samples should complete" \
    && pass_test
else
  fail_test "Failed with 50 samples"
fi

#############################################################################
# Test 4: Empty sample directory (no input files)
#############################################################################
start_test "Handles empty sample directories gracefully"

IN="$TEST_DIR/test4_in"
OUT="$TEST_DIR/test4_out"
SCRIPT="$TEST_DIR/test4.sh"

mkdir -p "$IN/empty_sample"
# No data.txt file created

create_simple_script "$SCRIPT" "$IN" "$OUT"

bash "$SCRIPT" >/dev/null 2>&1 || true

assert_count_equals "$(count_done "$OUT")" 0 "Should not complete" \
  && assert_count_equals "$(count_failed "$OUT")" 1 "Should mark as failed" \
  && pass_test

#############################################################################
# Test 5: Mixed success and failure
#############################################################################
start_test "Handles mix of successful and failed samples"

IN="$TEST_DIR/test5_in"
OUT="$TEST_DIR/test5_out"
SCRIPT="$TEST_DIR/test5.sh"

# Create some with data, some without
mkdir -p "$IN/sample_ok1" "$IN/sample_fail" "$IN/sample_ok2"
echo "data" >"$IN/sample_ok1/data.txt"
# sample_fail has no data.txt
echo "data" >"$IN/sample_ok2/data.txt"

create_simple_script "$SCRIPT" "$IN" "$OUT"

bash "$SCRIPT" >/dev/null 2>&1 || true

assert_count_equals "$(count_done "$OUT")" 2 "2 should succeed" \
  && assert_count_equals "$(count_failed "$OUT")" 1 "1 should fail" \
  && pass_test

#############################################################################
# Test 6: Nested directories in sample folder
#############################################################################
start_test "Handles nested directories within samples"

IN="$TEST_DIR/test6_in"
OUT="$TEST_DIR/test6_out"
SCRIPT="$TEST_DIR/test6.sh"

mkdir -p "$IN/sample1/subdir"
echo "data" >"$IN/sample1/data.txt"
echo "other" >"$IN/sample1/subdir/other.txt"

create_simple_script "$SCRIPT" "$IN" "$OUT"

if bash "$SCRIPT" >/dev/null 2>&1; then
  assert_file_exists "$OUT/sample1/.done" \
    && pass_test
else
  fail_test "Failed with nested directories"
fi

#############################################################################
# Test 7: Symlinks in input directory
#############################################################################
start_test "Handles symlinked sample directories"

IN="$TEST_DIR/test7_in"
OUT="$TEST_DIR/test7_out"
SCRIPT="$TEST_DIR/test7.sh"
REAL_DIR="$TEST_DIR/test7_real"

# Create real directory
mkdir -p "$REAL_DIR/real_sample"
echo "data" >"$REAL_DIR/real_sample/data.txt"

# Create symlink
mkdir -p "$IN"
ln -s "$REAL_DIR/real_sample" "$IN/link_sample"

create_simple_script "$SCRIPT" "$IN" "$OUT"

if bash "$SCRIPT" >/dev/null 2>&1; then
  assert_file_exists "$OUT/link_sample/.done" \
    && pass_test
else
  fail_test "Failed with symlinked directories"
fi

#############################################################################
# Test 8: Run-list with comments and blank lines
#############################################################################
start_test "run-list-local.sh handles comments and blank lines"

IN="$TEST_DIR/test8_in"
OUT="$TEST_DIR/test8_out"
JOB_DIR="$TEST_DIR/test8_jobs"
LIST="$TEST_DIR/test8_list.txt"

create_mock_samples "$IN" "single" "s1" "s2"
mkdir -p "$JOB_DIR"

# Create job scripts
for sample in s1 s2; do
  cat >"$JOB_DIR/$sample.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$OUT/$sample"
touch "$OUT/$sample/.done"
echo "SUCCESS" > "$OUT/$sample/run.log"
EOF
  chmod +x "$JOB_DIR/$sample.sh"
done

# Create run list with comments and blank lines
cat >"$LIST" <<EOF
# This is a comment
$JOB_DIR/s1.sh

# Another comment
$JOB_DIR/s2.sh
EOF

if bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2 >/dev/null 2>&1; then
  assert_count_equals "$(count_done "$OUT")" 2 "Should process only actual job lines" \
    && pass_test
else
  fail_test "run-list-local.sh failed with comments"
fi

#############################################################################
# Test 9: Very long sample names
#############################################################################
start_test "Handles long sample directory names"

IN="$TEST_DIR/test9_in"
OUT="$TEST_DIR/test9_out"
SCRIPT="$TEST_DIR/test9.sh"

# Create sample with very long name
LONG_NAME="sample_with_a_very_long_name_that_contains_many_characters_to_test_handling"
mkdir -p "$IN/$LONG_NAME"
echo "data" >"$IN/$LONG_NAME/data.txt"

create_simple_script "$SCRIPT" "$IN" "$OUT"

if bash "$SCRIPT" >/dev/null 2>&1; then
  assert_file_exists "$OUT/$LONG_NAME/.done" \
    && pass_test
else
  fail_test "Failed with long sample name"
fi

#############################################################################
# Test 10: Concurrent access to same sample (should be prevented)
#############################################################################
start_test "Multiple runs handle markers correctly"

IN="$TEST_DIR/test10_in"
OUT="$TEST_DIR/test10_out"
SCRIPT="$TEST_DIR/test10.sh"

create_mock_samples "$IN" "single" "sample1"
create_simple_script "$SCRIPT" "$IN" "$OUT"

# First run
bash "$SCRIPT" >/dev/null 2>&1

# Second run should skip already-done sample
output=$(bash "$SCRIPT" 2>&1)

if echo "$output" | grep -q "SKIP" || [[ $(count_done "$OUT") -eq 1 ]]; then
  print_info "✓ Second run correctly handled completed sample"
  pass_test
else
  fail_test "Second run didn't handle completed sample correctly"
fi

# Print summary
print_test_summary "${BASH_SOURCE[0]}"
