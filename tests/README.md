# step-by-sample Testing Framework

Comprehensive test suite for validating the step-by-sample workflow templates and helper scripts.

## Design Philosophy

**Tests use the actual template files, not copies.**

This framework tests the real `examples/single-local-template.sh` and `examples/build-jobs-template.sh` files to ensure:

- ✅ Changes to templates are automatically validated
- ✅ No duplication between templates and tests
- ✅ Tests verify production code, not copies
- ✅ Template behavior is tested end-to-end

### How It Works: TEST_COMMAND

Both templates support an optional `TEST_COMMAND` environment variable for testing:

```bash
# In production (normal use):
./single-local-template.sh  # Runs real commands (quast, fastp, etc.)

# In tests:
TEST_COMMAND="mock_success" ./single-local-template.sh  # Uses mock instead
```

The templates check for `TEST_COMMAND` and use it if set, otherwise execute the real bioinformatics command. This allows tests to exercise all template logic (validation, error handling, FORCE/DRY modes, etc.) without requiring real tools or data.

**For production users:** You can ignore TEST_COMMAND - it's only used by the test suite.

## Quick Start

```bash
# Run all tests
./run-all-tests.sh

# Run with verbose output
./run-all-tests.sh --verbose

# Run the quick subset (currently test-01 through test-03)
./run-all-tests.sh --quick

# Run specific test file
./run-all-tests.sh "test-01*"

# Run individual test directly
./test-01-approach1.sh
```

## Test Structure

```text
tests/
├── run-all-tests.sh          # Main test runner
├── lib/
│   ├── test-helpers.sh       # Assertion and utility functions
│   └── mock-commands.sh      # Mock bioinformatics commands
├── mock-slurm/
│   └── sbatch                # Mock Slurm for local testing
├── test-01-approach1.sh      # Single-local template tests
├── test-02-approach2.sh      # Build-jobs + execution tests
├── test-03-helpers.sh        # Helper utility tests
├── test-04-edge-cases.sh     # Edge cases and robustness
├── test-05-reruns.sh         # Rerun scenarios and recovery
└── README.md                 # This file
```

## Test Coverage

### test-01-approach1.sh

Tests the single self-contained local execution template:

- ✓ Basic successful execution
- ✓ Partial failures (some succeed, some fail)
- ✓ FORCE=1 reruns completed samples
- ✓ DRY=1 doesn't execute commands
- ✓ Parallel execution with JOBS parameter
- ✓ Missing input handling

**Run time:** ~5-10 seconds

### test-02-approach2.sh

Tests the build-jobs + execution workflow:

- ✓ Build jobs with MODE=all
- ✓ Execute jobs with run-list-local.sh
- ✓ MODE=unfinished skips completed samples
- ✓ MODE=failed only builds failed jobs
- ✓ Execute individual job script directly
- ✓ Mock Slurm submission

**Run time:** ~5-10 seconds

### test-03-helpers.sh

Tests helper utility scripts:

- ✓ validate-step.sh succeeds with valid input
- ✓ validate-step.sh catches missing/empty directories
- ✓ summarize-status.sh reports correct counts
- ✓ repair-failed.sh removes failure markers
- ✓ repair-failed.sh --clean-outputs removes files
- ✓ repair-failed.sh --dry-run doesn't modify
- ✓ common.sh functions work correctly
- ✓ common.sh find_paired_reads works
- ✓ common.sh validate_paired_input catches problems

**Run time:** ~3-5 seconds

### test-04-edge-cases.sh

Tests robustness and edge cases:

- ✓ Spaces in sample directory names
- ✓ Special characters in sample names
- ✓ Large number of samples (50 samples)
- ✓ Empty sample directories
- ✓ Mixed success and failure
- ✓ Nested directories within samples
- ✓ Symlinked sample directories
- ✓ Run-list with comments and blank lines
- ✓ Very long sample names
- ✓ Multiple runs handle markers correctly

**Run time:** ~8-12 seconds

### test-05-reruns.sh

Tests rerun scenarios and recovery workflows:

- ✓ Initial run with mix of success/failures
- ✓ MODE=failed rebuilds only failed samples
- ✓ MODE=unfinished skips done, includes failed
- ✓ repair-failed.sh prepares for rerun
- ✓ Complete recovery workflow
- ✓ FORCE=1 rebuilds all samples
- ✓ Incremental reruns - adding new samples
- ✓ repair-failed.sh --clean-outputs for complete reset
- ✓ Multiple rerun cycles converge to completion

**Run time:** ~8-12 seconds

## Test Features

### Mock Commands

The test suite uses mock commands that simulate bioinformatics tools without actually running them. All mock commands follow the signature: `mock_function OUT_DIR INPUT_FILE SAMPLE_NAME`

- **mock_success**: Always succeeds, creates result.txt
- **mock_fail**: Always fails with error message
- **mock_conditional_fail**: Fails for samples with "fail" in name
- **mock_slow**: Simulates slow commands (testing parallelism), duration controlled by MOCK_SLOW_DURATION
- **mock_paired**: Simulates paired-end processing (for future use)

These are used via the TEST_COMMAND mechanism:

```bash
# Example: run template with mock
TEST_COMMAND="mock_success" IN="input/" OUT="output/" ./single-local-template.sh

# Example: conditional failure test
TEST_COMMAND="mock_conditional_fail" IN="input/" OUT="output/" ./single-local-template.sh
```

### Mock Slurm

The `mock-slurm/sbatch` script simulates Slurm batch submission:

- Accepts standard sbatch arguments
- Returns realistic job IDs
- Executes array jobs sequentially (locally)
- Creates standard .out/.err files
- Reads `#SBATCH` settings from the generated array script so test submissions match helper behavior
- Allows testing Slurm workflows without a cluster

### Assertion Functions

Available in `lib/test-helpers.sh`:

```bash
assert_file_exists file [description]
assert_file_not_exists file [description]
assert_dir_exists directory [description]
assert_marker_exists out_dir sample marker [description]
assert_log_contains log_file pattern [description]
assert_count_equals actual expected [description]
assert_command_success "command" [description]
assert_command_fails "command" [description]
assert_equals actual expected [description]
```

### Utility Functions

```bash
# Setup and teardown
setup_test_dir "test_name"
cleanup_test_dir

# Create mock data (two syntaxes):
# Syntax 1: count-based (generates sample_01, sample_02, ...)
create_mock_samples in_dir COUNT file_type
create_mock_samples "$IN" 5 single           # Creates sample_01 through sample_05
create_mock_samples "$IN" 3 paired           # Creates 3 paired-end samples

# Syntax 2: named samples
create_mock_samples in_dir file_type sample1 sample2 ...
create_mock_samples "$IN" single s1 s2 s3    # Creates s1, s2, s3
create_mock_samples "$IN" paired test_fail   # Creates test_fail (paired)

# file_type: single, paired, paired-fixed, empty

# Count markers
count_done out_dir
count_failed out_dir
count_logs out_dir

# Test lifecycle
start_test "test description"
pass_test
fail_test "reason"
print_test_summary script_name
```

## Writing New Tests

### Template for New Test Script

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/mock-commands.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$PROJECT_ROOT/examples/single-local-template.sh"

print_header "Testing My Feature"

setup_test_dir "my-feature"
trap cleanup_test_dir EXIT

#############################################################################
# Test 1: Description
#############################################################################
start_test "Test description"

IN="$TEST_DIR/test1_in"
OUT="$TEST_DIR/test1_out"

create_mock_samples "$IN" 3 single  # Creates sample_01, sample_02, sample_03

# Run the ACTUAL template with mock command
TEST_COMMAND="mock_success" \
  IN="$IN" \
  OUT="$OUT" \
  JOBS=2 \
  bash "$TEMPLATE" >/dev/null 2>&1

# Verify results
assert_count_equals "$(count_done "$OUT")" 3 "All samples should complete" && \
assert_file_exists "$OUT/sample_01/.done" && \
pass_test

# Print summary
print_test_summary "${BASH_SOURCE[0]}"
```

### Testing Approach 2 (Build Jobs)

```bash
TEMPLATE="$PROJECT_ROOT/examples/build-jobs-template.sh"

# Run build template
TEST_COMMAND="mock_success" \
  IN="$IN" \
  OUT="$OUT" \
  JOB_DIR="$JOB_DIR" \
  LIST="$LIST" \
  MODE="all" \
  bash "$TEMPLATE" >/dev/null 2>&1

# Execute generated jobs
bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2
```

### Best Practices

1. **Test actual templates** - always use real template files, not copies
2. **Each test should be independent** - setup its own data
3. **Use descriptive test names** - makes failures easy to diagnose
4. **Clean up after tests** - use `trap cleanup_test_dir EXIT`
5. **Use assertions** - chain them with `&&` for logical grouping
6. **Test both success and failure paths** - use mock_conditional_fail
7. **Use mock data** - fast and sufficient for framework testing
8. **Test parameters via environment** - IN, OUT, JOBS, FORCE, DRY, MODE

## Running Tests in CI/CD

The test suite is designed for CI/CD integration:

```bash
# In your CI script
cd tests
./run-all-tests.sh

# Exit code 0 = all tests passed
# Exit code 1 = one or more tests failed
```

### GitHub Actions Example

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: |
          cd tests
          chmod +x *.sh lib/*.sh mock-slurm/*
          ./run-all-tests.sh
```

## Troubleshooting

### Tests fail with "permission denied"

```bash
chmod +x tests/*.sh tests/lib/*.sh tests/mock-slurm/*
```

### Tests leave temp directories

Tests clean up automatically on EXIT, but if interrupted:

```bash
rm -rf /tmp/step-by-sample-test-*
```

### Verbose output for debugging

```bash
./run-all-tests.sh --verbose
# or
VERBOSE=1 ./test-01-approach1.sh
```

### Run single assertion

```bash
# Edit test file to comment out other tests
# Run just the test you're debugging
./test-01-approach1.sh
```

## Test Data

Tests use minimal mock data:

- Small text files for single-file workflows
- Tiny "FASTQ" files for paired-end workflows
- No actual bioinformatics computation
- Fast: complete suite runs in ~30-50 seconds

## Future Test Additions

Potential areas for expansion:

- Performance benchmarks
- Memory usage tests
- Very large sample counts (1000+)
- Network file system scenarios
- Concurrent execution safety
- More paired-end edge cases

## Contributing Tests

When adding features to step-by-sample:

1. Add corresponding tests
2. Ensure tests are self-contained
3. Update this README with test descriptions
4. Verify all existing tests still pass

## Questions?

See the main project [README.md](../README.md) for step-by-sample usage documentation.
