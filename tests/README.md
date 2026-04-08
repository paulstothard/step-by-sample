# step-by-sample Testing Framework

Comprehensive tests for the single step-by-sample workflow template and its helper scripts.

## Design Philosophy

Tests exercise the real [examples/build-jobs-template.sh](../examples/build-jobs-template.sh) template and the real helper scripts. The goal is to validate the production workflow, not copies of it.

## Quick Start

Run the full suite:

```bash
./run-all-tests.sh
```

Run with verbose output:

```bash
./run-all-tests.sh --verbose
```

Run the quick subset:

```bash
./run-all-tests.sh --quick
```

Run just one test file:

```bash
./run-all-tests.sh "test-01*"
```

Run an individual test directly:

```bash
./test-01-workflow.sh
```

## Test Structure

```text
tests/
├── run-all-tests.sh          # Main test runner
├── lib/
│   ├── test-helpers.sh       # Assertions and utilities
│   └── mock-commands.sh      # Mock tool commands for tests
├── mock-slurm/
│   └── sbatch                # Mock Slurm for local testing
├── test-01-workflow.sh       # Core workflow template + helper execution
├── test-02-helpers.sh        # Helper utility tests
├── test-03-edge-cases.sh     # Edge cases and robustness
├── test-04-reruns.sh         # Rerun and recovery behavior
└── README.md                 # This file
```

## Coverage

### test-01-workflow.sh

Validates the primary workflow template and execution helpers:

- builds per-sample jobs,
- emits portable absolute run-list paths,
- executes generated jobs locally,
- rebuilds correctly with `MODE=unfinished` and `MODE=failed`,
- writes `.failed` markers on job failure,
- submits to mock Slurm,
- applies Slurm setup files and module loads.

### test-02-helpers.sh

Validates helper utilities:

- `validate-step.sh`,
- `summarize-status.sh`,
- `repair-failed.sh`,
- `common.sh` helper functions.

### test-03-edge-cases.sh

Covers robustness issues such as:

- spaces and special characters in sample names,
- many samples,
- empty sample directories,
- symlinks,
- comment and blank-line handling in run lists,
- repeated runs.

### test-04-reruns.sh

Covers recovery behavior:

- `MODE=failed`,
- `MODE=unfinished`,
- `FORCE=1`,
- `repair-failed.sh`,
- incremental rebuilds,
- repeated rerun cycles.

## Mock Commands

Tests use mock commands instead of real bioinformatics tools. The mock command signature is:

```text
mock_function OUT_DIR INPUT_FILE SAMPLE_NAME
```

Available mocks in [tests/lib/mock-commands.sh](lib/mock-commands.sh):

- `mock_success`
- `mock_fail`
- `mock_conditional_fail`
- `mock_slow`
- `mock_paired`

The workflow template honors `TEST_COMMAND` so tests can exercise the real generated job scripts without requiring real tools or datasets.

## Mock Slurm

[tests/mock-slurm/sbatch](mock-slurm/sbatch) simulates Slurm submission locally. It:

- accepts standard `sbatch` invocations,
- parses generated `#SBATCH` settings,
- creates realistic `.out` and `.err` files,
- runs array tasks locally so Slurm behavior can be tested without a cluster.

## Assertion Helpers

Available in [tests/lib/test-helpers.sh](lib/test-helpers.sh):

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

## Utility Helpers for Test Authors

```bash
setup_test_dir "test_name"
cleanup_test_dir

create_mock_samples in_dir COUNT file_type
create_mock_samples "$IN" 5 single

create_mock_samples in_dir file_type sample1 sample2 ...
create_mock_samples "$IN" single s1 s2 s3

count_done out_dir
count_failed out_dir
count_logs out_dir

start_test "test description"
pass_test
fail_test "reason"
print_test_summary script_name
```

## Writing New Tests

Use the real workflow template, not a copied script:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$SCRIPT_DIR/lib/mock-commands.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$PROJECT_ROOT/examples/build-jobs-template.sh"

setup_test_dir "my-feature"
trap cleanup_test_dir EXIT

IN="$TEST_DIR/test1_in"
OUT="$TEST_DIR/test1_out"
JOB_DIR="$TEST_DIR/test1_jobs"
LIST="$TEST_DIR/test1_list.txt"

create_mock_samples "$IN" 3 single

TEST_COMMAND="mock_success" \
  IN="$IN" \
  OUT="$OUT" \
  JOB_DIR="$JOB_DIR" \
  LIST="$LIST" \
  MODE="all" \
  bash "$TEMPLATE" >/dev/null 2>&1

bash "$PROJECT_ROOT/helpers/run-list-local.sh" "$LIST" 2 >/dev/null 2>&1

assert_count_equals "$(count_done "$OUT")" 3 "All samples should complete" && \
assert_file_exists "$OUT/sample_01/.done" && \
pass_test

print_test_summary "${BASH_SOURCE[0]}"
```

## CI/CD

The suite is CI-friendly:

```bash
cd tests
./run-all-tests.sh
```

Exit code `0` means success. Exit code `1` means one or more tests failed.

## Troubleshooting

If scripts are not executable:

```bash
chmod +x tests/*.sh tests/lib/*.sh tests/mock-slurm/*
```

If interrupted tests leave temp directories behind:

```bash
rm -rf /tmp/step-by-sample-test-*
```

For verbose debugging:

```bash
./run-all-tests.sh --verbose
VERBOSE=1 ./test-01-workflow.sh
```

## Contributing Tests

When adding features:

1. add matching tests,
2. keep tests self-contained,
3. update this README if behavior changes,
4. confirm the full suite still passes.

For overall project usage, see [README.md](../README.md).
