#!/usr/bin/env bash
# Test helper functions for step-by-sample testing framework
# Source this in test scripts

# Colors for output
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  BOLD=''
  RESET=''
fi

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

# Test output directory (set by each test script)
TEST_DIR=""

# Verbose flag (set by test runner)
VERBOSE=${VERBOSE:-0}

# Print functions
print_header() {
  echo -e "${BOLD}${BLUE}=== $1 ===${RESET}"
}

print_success() {
  echo -e "${GREEN}✓${RESET} $1"
}

print_failure() {
  echo -e "${RED}✗${RESET} $1"
}

print_warning() {
  echo -e "${YELLOW}⚠${RESET} $1"
}

print_info() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo -e "${BLUE}ℹ${RESET} $1"
  fi
  return 0
}

# Test lifecycle
start_test() {
  CURRENT_TEST="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  print_info "Starting: $CURRENT_TEST"
}

pass_test() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  print_success "$CURRENT_TEST"
}

fail_test() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  print_failure "$CURRENT_TEST: $1"
}

# Setup and teardown
setup_test_dir() {
  local _name="$1"
  TEST_DIR="/tmp/step-by-sample-test-$$-$RANDOM"
  mkdir -p "$TEST_DIR"
  print_info "Test directory: $TEST_DIR"
}

cleanup_test_dir() {
  if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
    print_info "Cleaned up: $TEST_DIR"
  fi
}

# Create mock input data
create_mock_samples() {
  local in_dir="$1"
  local arg2="$2"
  local file_type="single"
  local samples=()

  # Check if arg2 is a number (for count-based creation)
  if [[ "$arg2" =~ ^[0-9]+$ ]]; then
    local count="$arg2"
    file_type="${3:-single}"
    # Generate sample names: sample_01, sample_02, etc.
    for ((i = 1; i <= count; i++)); do
      samples+=("$(printf "sample_%02d" "$i")")
    done
  else
    # Original syntax: file_type followed by sample names
    file_type="$arg2"
    shift 2
    samples=("$@")
  fi

  mkdir -p "$in_dir"

  for sample in "${samples[@]}"; do
    local sample_dir="$in_dir/$sample"
    mkdir -p "$sample_dir"

    case "$file_type" in
      single)
        echo "mock data for $sample" >"$sample_dir/data.txt"
        ;;
      paired)
        echo "R1 data for $sample" >"$sample_dir/${sample}_R1.fastq.gz"
        echo "R2 data for $sample" >"$sample_dir/${sample}_R2.fastq.gz"
        ;;
      paired-fixed)
        echo "R1 data for $sample" >"$sample_dir/R1.fastq.gz"
        echo "R2 data for $sample" >"$sample_dir/R2.fastq.gz"
        ;;
      empty)
        # Just create the directory, no files
        ;;
      *)
        echo "Unknown file type: $file_type" >&2
        return 1
        ;;
    esac
  done
}

# Assertion functions
assert_file_exists() {
  local file="$1"
  local desc="${2:-File should exist: $file}"

  if [[ -f "$file" ]]; then
    print_info "✓ $desc"
    return 0
  else
    fail_test "$desc (file not found: $file)"
    return 1
  fi
}

assert_file_not_exists() {
  local file="$1"
  local desc="${2:-File should not exist: $file}"

  if [[ ! -f "$file" ]]; then
    print_info "✓ $desc"
    return 0
  else
    fail_test "$desc (file exists: $file)"
    return 1
  fi
}

assert_dir_exists() {
  local dir="$1"
  local desc="${2:-Directory should exist: $dir}"

  if [[ -d "$dir" ]]; then
    print_info "✓ $desc"
    return 0
  else
    fail_test "$desc (directory not found: $dir)"
    return 1
  fi
}

assert_marker_exists() {
  local out_dir="$1"
  local sample="$2"
  local marker="$3" # .done or .failed
  local desc="${4:-Sample $sample should have $marker marker}"

  local marker_file="$out_dir/$sample/$marker"

  if [[ -f "$marker_file" ]]; then
    print_info "✓ $desc"
    return 0
  else
    fail_test "$desc (marker not found: $marker_file)"
    return 1
  fi
}

assert_log_contains() {
  local log_file="$1"
  local pattern="$2"
  local desc="${3:-Log should contain: $pattern}"

  if [[ ! -f "$log_file" ]]; then
    fail_test "$desc (log file not found: $log_file)"
    return 1
  fi

  if grep -q "$pattern" "$log_file"; then
    print_info "✓ $desc"
    return 0
  else
    fail_test "$desc (pattern not found in log)"
    [[ "$VERBOSE" -eq 1 ]] && echo "Log contents:" && cat "$log_file"
    return 1
  fi
}

assert_count_equals() {
  local actual="$1"
  local expected="$2"
  local desc="${3:-Count should equal $expected}"

  if [[ "$actual" -eq "$expected" ]]; then
    print_info "✓ $desc (got $actual)"
    return 0
  else
    fail_test "$desc (expected $expected, got $actual)"
    return 1
  fi
}

assert_command_success() {
  local cmd="$1"
  local desc="${2:-Command should succeed: $cmd}"

  if eval "$cmd" >/dev/null 2>&1; then
    print_info "✓ $desc"
    return 0
  else
    fail_test "$desc (command failed with exit code $?)"
    return 1
  fi
}

assert_command_fails() {
  local cmd="$1"
  local desc="${2:-Command should fail: $cmd}"

  if eval "$cmd" >/dev/null 2>&1; then
    fail_test "$desc (command succeeded but should have failed)"
    return 1
  else
    print_info "✓ $desc"
    return 0
  fi
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  local desc="${3:-Values should be equal}"

  if [[ "$actual" == "$expected" ]]; then
    print_info "✓ $desc"
    return 0
  else
    fail_test "$desc (expected '$expected', got '$actual')"
    return 1
  fi
}

# Count markers in output directory
count_done() {
  local out_dir="$1"
  find "$out_dir" -mindepth 2 -maxdepth 2 -name ".done" 2>/dev/null | wc -l | tr -d ' '
}

count_failed() {
  local out_dir="$1"
  find "$out_dir" -mindepth 2 -maxdepth 2 -name ".failed" 2>/dev/null | wc -l | tr -d ' '
}

count_logs() {
  local out_dir="$1"
  find "$out_dir" -mindepth 2 -maxdepth 2 -name "run.log" 2>/dev/null | wc -l | tr -d ' '
}

# Test summary
print_test_summary() {
  local test_file="$1"
  echo
  echo -e "${BOLD}Test Summary: $(basename "$test_file")${RESET}"
  echo "  Total:  $TESTS_RUN"
  echo -e "  ${GREEN}Passed: $TESTS_PASSED${RESET}"

  if [[ "$TESTS_FAILED" -gt 0 ]]; then
    echo -e "  ${RED}Failed: $TESTS_FAILED${RESET}"
    return 1
  else
    echo -e "  ${GREEN}All tests passed!${RESET}"
    return 0
  fi
}

# Wait for background processes to finish (useful for parallel tests)
wait_for_completion() {
  local max_wait="${1:-60}" # seconds
  local check_interval=1
  local waited=0

  while [[ $(jobs -r | wc -l) -gt 0 ]] && [[ $waited -lt $max_wait ]]; do
    sleep $check_interval
    waited=$((waited + check_interval))
  done

  if [[ $(jobs -r | wc -l) -gt 0 ]]; then
    print_warning "Timeout waiting for background jobs"
    return 1
  fi

  return 0
}
