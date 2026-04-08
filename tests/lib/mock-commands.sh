#!/usr/bin/env bash
# Mock command implementations for testing
# These simulate bioinformatics tools without actually running them
#
# Standard signature for TEST_COMMAND mocks:
#   mock_function OUT_DIR INPUT_FILE SAMPLE_NAME
# Where:
#   OUT_DIR    - output directory for this sample
#   INPUT_FILE - primary input file path
#   SAMPLE_NAME - sample basename

# Mock successful command - always succeeds
# Writes timestamp to result.txt so reruns can be detected
mock_success() {
  local out_dir="$1"
  local input_file="$2"
  local sample="$3"

  echo "Mock SUCCESS: processing $sample"
  echo "Input: $input_file"
  echo "Output: $out_dir"
  echo "MOCK_SUCCESS-$(date +%s%N)" >"$out_dir/result.txt"
  return 0
}

# Mock failing command - always fails
mock_fail() {
  local out_dir="$1"
  local input_file="$2"
  local sample="$3"

  echo "Mock FAIL: processing $sample"
  echo "ERROR: Intentional failure" >&2
  return 1
}

# Mock conditional failure - fails if sample name contains "fail"
mock_conditional_fail() {
  local out_dir="$1"
  local input_file="$2"
  local sample="$3"

  echo "Mock CONDITIONAL: processing $sample"

  if [[ "$sample" == *"fail"* ]]; then
    echo "ERROR: Sample name contains 'fail' - triggering failure" >&2
    return 1
  fi

  echo "MOCK_SUCCESS" >"$out_dir/result.txt"
  return 0
}

# Mock slow command - for testing parallelism
mock_slow() {
  local out_dir="$1"
  local input_file="$2"
  local sample="$3"
  local duration="${MOCK_SLOW_DURATION:-1}"

  echo "Mock SLOW: sleeping ${duration}s for $sample"
  sleep "$duration"
  echo "MOCK_SLOW_SUCCESS" >"$out_dir/result.txt"
  return 0
}

# Mock paired-end processing (for future use with multiple inputs)
# Note: This is harder to use with TEST_COMMAND since it expects multiple inputs
# Use mock_success for single-file tests
mock_paired() {
  local out_dir="$1"
  local r1="$2"
  local r2="$3"

  if [[ ! -f "$r1" ]] || [[ ! -f "$r2" ]]; then
    echo "ERROR: Missing paired input files" >&2
    return 1
  fi

  echo "Mock PAIRED: processing paired reads"
  echo "R1: $r1"
  echo "R2: $r2"
  cat "$r1" "$r2" >"$out_dir/merged.txt"
  return 0
}

# Export functions so they work in subshells and generated job scripts
export -f mock_success
export -f mock_fail
export -f mock_conditional_fail
export -f mock_slow
export -f mock_paired
