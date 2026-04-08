#!/usr/bin/env bash
# Main test runner for step-by-sample testing framework
# Runs all tests or specified subsets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"

usage() {
  cat <<'EOF'
Usage:
  run-all-tests.sh [OPTIONS] [TEST_PATTERN]

Description:
  Run all tests or a subset matching a pattern.

Options:
  --quick       Run only quick/essential tests (skip slower workflow stress tests)
  --verbose     Show detailed output for each test
  --help, -h    Show this help

Arguments:
  TEST_PATTERN  Optional glob pattern to match test files (e.g., "test-01*")
                Default: runs all test-*.sh files

Examples:
  run-all-tests.sh                    # Run all tests
  run-all-tests.sh --verbose          # Run with verbose output
  run-all-tests.sh --quick            # Run quick subset
  run-all-tests.sh "test-01*"         # Run only test-01 files
  run-all-tests.sh "test-02*"         # Run only helper tests

Exit Code:
  0   All tests passed
  1   One or more tests failed
EOF
}

# Parse arguments
QUICK_MODE=0
export VERBOSE=0
TEST_PATTERN="test-*.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      QUICK_MODE=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      TEST_PATTERN="$1"
      shift
      ;;
  esac
done

# Find test scripts
mapfile -t test_scripts < <(find "$SCRIPT_DIR" -maxdepth 1 -name "$TEST_PATTERN" -type f | sort)

if [[ "$QUICK_MODE" -eq 1 ]]; then
  filtered_test_scripts=()
  for test_script in "${test_scripts[@]}"; do
    case "$(basename "$test_script")" in
      test-03-* | test-04-*) ;;
      *)
        filtered_test_scripts+=("$test_script")
        ;;
    esac
  done
  test_scripts=("${filtered_test_scripts[@]}")
fi

if [[ ${#test_scripts[@]} -eq 0 ]]; then
  echo "Error: no test files found matching pattern: $TEST_PATTERN" >&2
  exit 1
fi

# Print header
echo
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${BLUE}║  step-by-sample Test Suite                          ║${RESET}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
echo

# Track overall results
TOTAL_TEST_FILES=0
PASSED_TEST_FILES=0
FAILED_TEST_FILES=0

START_TIME=$(date +%s)

if [[ "$QUICK_MODE" -eq 1 ]]; then
  echo "Quick mode: skipping slower test files (test-03, test-04)"
  echo
fi

# Run each test file
for test_script in "${test_scripts[@]}"; do
  TOTAL_TEST_FILES=$((TOTAL_TEST_FILES + 1))
  test_name="$(basename "$test_script")"

  echo -e "${BOLD}Running: $test_name${RESET}"
  echo

  # Run the test and capture output
  if [[ "$VERBOSE" -eq 1 ]]; then
    # Verbose mode - show all output
    if bash "$test_script"; then
      PASSED_TEST_FILES=$((PASSED_TEST_FILES + 1))
      echo
    else
      FAILED_TEST_FILES=$((FAILED_TEST_FILES + 1))
      echo
    fi
  else
    # Quiet mode - capture output and show summary
    test_output=$(mktemp)
    if bash "$test_script" >"$test_output" 2>&1; then
      PASSED_TEST_FILES=$((PASSED_TEST_FILES + 1))

      # Extract and show summary
      if grep -q "Test Summary:" "$test_output"; then
        grep -A 10 "Test Summary:" "$test_output"
      else
        cat "$test_output"
      fi
      echo
    else
      FAILED_TEST_FILES=$((FAILED_TEST_FILES + 1))

      # Show full output on failure
      cat "$test_output"
      echo
    fi
    rm -f "$test_output"
  fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Print final summary
echo
echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}Final Summary${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo
echo "Test Files:"
echo "  Total:   $TOTAL_TEST_FILES"
echo -e "  ${GREEN}Passed:  $PASSED_TEST_FILES${RESET}"
if [[ "$FAILED_TEST_FILES" -gt 0 ]]; then
  echo -e "  ${RED}Failed:  $FAILED_TEST_FILES${RESET}"
fi
echo

if command -v format_time >/dev/null 2>&1; then
  echo "Time: $(format_time $ELAPSED)"
else
  echo "Time: ${ELAPSED}s"
fi
echo

# Exit with appropriate code
if [[ "$FAILED_TEST_FILES" -eq 0 ]]; then
  echo -e "${BOLD}${GREEN}✓ All tests passed!${RESET}"
  echo
  exit 0
else
  echo -e "${BOLD}${RED}✗ Some tests failed${RESET}"
  echo

  # List failed tests
  echo "Failed test files:"
  for test_script in "${test_scripts[@]}"; do
    test_output=$(mktemp)
    if ! bash "$test_script" >"$test_output" 2>&1; then
      echo -e "  ${RED}✗${RESET} $(basename "$test_script")"
    fi
    rm -f "$test_output"
  done
  echo
  exit 1
fi
