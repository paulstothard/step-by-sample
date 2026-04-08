# step-by-sample

A lightweight Bash-first pattern for bioinformatics workflow steps where:

- one step reads from one input folder
- one step writes to one output folder
- each sample is a subfolder
- each sample gets its own `run.log`
- each sample gets either `.done` or `.failed`

This is not a workflow engine. It is a small, transparent system built around:

- a single self-contained local execution pattern
- an optional "build job scripts + run list" pattern
- stable helper scripts for local execution, Slurm array execution, and summaries

The goal is readability, editability, restartability, and easy reruns of failed jobs.

---

## Quickstart

1. **Choose your approach:**

   - **Approach 1 (Simple):** Copy `examples/single-local-template.sh` for immediate local execution
   - **Approach 2 (Flexible):** Copy `examples/build-jobs-template.sh` for job generation + flexible execution

2. **Edit the template:**

   - Set `IN` and `OUT` directories
   - Customize the "EDIT THIS SECTION" blocks for your input files and command

3. **Run:**

   - **Approach 1:** `./your-script.sh` (executes immediately)
   - **Approach 2:** Generate jobs → execute with `helpers/run-list-local.sh` or `helpers/run-list-slurm.sh`

4. **Check results:**
   - Use `helpers/summarize-status.sh OUT_DIR` to see done/failed counts
   - Rerun failed samples by setting `MODE="failed"` (Approach 2) or `FORCE=1` (Approach 1)

---

## Folder convention

At a given step, the input and output folders look like this:

```text
IN/
  sample1/
    ...
  sample2/
    ...

OUT/
  sample1/
    run.log
    .done or .failed
    ...
  sample2/
    run.log
    .done or .failed
    ...
```

This keeps filenames simple inside each sample folder and avoids collisions across steps.

---

## Approach 1: single self-contained local script

This is the simplest pattern for immediate local execution. It supports:

- one input folder and one output folder
- sample subfolders with per-sample logs
- `.done` and `.failed` markers
- `FORCE` to rerun completed samples
- `DRY` for dry runs
- local parallelism with `xargs`
- clear edit sections for inputs, validation, and commands
- examples for single files, paired-end reads, plain and Docker commands

**Template file:** `examples/single-local-template.sh`

**Key features:**

- Self-contained: everything in one script
- Immediate execution: no separate build step
- Simple: good for quick workflows or testing

**Usage:**

```bash
# Copy and customize the template
cp examples/single-local-template.sh my-workflow-step.sh
# Edit IN, OUT, and command sections
# Run it
./my-workflow-step.sh
```

---

## Approach 2: build per-sample job scripts and use helper scripts

This is the more flexible approach. Instead of executing immediately, you first generate:

- a step-specific jobs folder such as `jobs-quast/`
- a run list such as `run-quast.txt`

Each line in the run list is just the path to one per-sample job script.

**Template file:** `examples/build-jobs-template.sh`

**This approach gives you:**

- Built-in dry run: inspect generated job scripts before execution
- Easy single-sample rerun: `bash jobs-quast/sample2.sh`
- Flexible execution: same run list works locally or on Slurm
- Selective reruns: build lists for `MODE=unfinished`, `MODE=failed`, or `MODE=all`
- No persistent controller: all state in filesystem (`.done`, `.failed`, logs)

### Workflow

**1. Generate job scripts:**

```bash
# Copy and customize the template
cp examples/build-jobs-template.sh build-my-step.sh
# Edit IN, OUT, and command sections
# Generate jobs
./build-my-step.sh
```

**2. Execute locally:**

```bash
helpers/run-list-local.sh run-quast.txt 4
```

**3. Or submit to Slurm:**

```bash
helpers/run-list-slurm.sh run-quast.txt \
  --account my_account \
  --partition cpu \
  --time 08:00:00 \
  --mem 16G \
  --cpus 8 \
  --array-max 20
```

**4. Check results:**

```bash
helpers/summarize-status.sh quast_output
```

---

## Helper Scripts

### Core helpers (for Approach 2)

- **`helpers/run-list-local.sh`** - Execute a run list locally with parallelism
- **`helpers/run-list-slurm.sh`** - Submit a run list as a Slurm array job
- **`helpers/summarize-status.sh`** - Scan output directory and report done/failed/other

### Utility helpers (for both approaches)

- **`helpers/validate-step.sh`** - Validate input directory structure before running

  ```bash
  helpers/validate-step.sh shovill_output
  ```

- **`helpers/repair-failed.sh`** - Clean up failed samples for rerun

  ```bash
  helpers/repair-failed.sh quast_output           # Remove .failed markers
  helpers/repair-failed.sh quast_output --clean-outputs  # Also remove partial outputs
  ```

- **`helpers/common.sh`** - Shared utility functions (sourced by templates)
  - `validate_sample_input()` - Check single file exists
  - `validate_paired_input()` - Check paired-end files exist
  - `find_paired_reads()` - Find R1/R2 files safely
  - `format_time()` - Human-readable elapsed time
  - `count_samples()` - Count samples in directory

All helper scripts support `--help` for detailed usage information.

---

## Reruns

### Approach 1: Single local script

**Rerun all failed samples:**

```bash
FORCE=1 ./my-workflow-step.sh
```

**Dry run to see what would run:**

```bash
DRY=1 ./my-workflow-step.sh
```

### Approach 2: Job scripts

**1. Rerun one specific sample:**

```bash
bash jobs-quast/sample2.sh
```

**2. Rebuild run list for failed samples only:**

```bash
# Edit your build script to set MODE="failed"
MODE="failed" ./build-my-step.sh
# Then execute the new list
helpers/run-list-local.sh run-quast.txt 4
```

**3. Rebuild for unfinished samples:**

```bash
MODE="unfinished" ./build-my-step.sh
helpers/run-list-local.sh run-quast.txt 4
```

**4. Clean up and rebuild:**

```bash
# Remove .failed markers and partial outputs
helpers/repair-failed.sh quast_output --clean-outputs
# Rebuild run list
MODE="unfinished" ./build-my-step.sh
# Execute
helpers/run-list-local.sh run-quast.txt 4
```

---

## Project structure

```text
step-by-sample/
├── README.md
├── .gitignore
├── examples/
│   ├── single-local-template.sh    # Approach 1: self-contained local
│   └── build-jobs-template.sh      # Approach 2: job generation
├── helpers/
│   ├── common.sh                   # Shared utility functions
│   ├── run-list-local.sh           # Local execution runner
│   ├── run-list-slurm.sh           # Slurm array job submitter
│   ├── summarize-status.sh         # Status reporter
│   ├── validate-step.sh            # Input validation
│   └── repair-failed.sh            # Failed sample cleanup
└── tests/
    ├── run-all-tests.sh            # Main test runner
    ├── test-01-approach1.sh        # Test Approach 1
    ├── test-02-approach2.sh        # Test Approach 2
    ├── test-03-helpers.sh          # Test utilities
    ├── test-04-edge-cases.sh       # Test edge cases
    ├── test-05-reruns.sh           # Test rerun workflows
    ├── lib/                        # Test helpers and mocks
    └── mock-slurm/                 # Mock Slurm for local testing
```

---

## Testing

A comprehensive test suite is included to validate templates and helpers:

```bash
# Run all tests
cd tests
./run-all-tests.sh

# Run with verbose output
./run-all-tests.sh --verbose

# Run specific test
./run-all-tests.sh "test-01*"
```

**Test coverage:**

- ✓ Both workflow approaches (single-local and build-jobs)
- ✓ All helper utilities (validate, summarize, repair)
- ✓ Edge cases (spaces in names, special chars, large sample counts)
- ✓ Rerun scenarios and failure recovery
- ✓ Mock Slurm submission for local testing

See [tests/README.md](tests/README.md) for detailed test documentation.

**Run time:** Complete suite runs in ~30-50 seconds

---

## Notes

- All scripts use modern Bash conventions:
  - `#!/usr/bin/env bash`
  - `set -euo pipefail`
  - `[[ ]]` for conditionals
  - Explicit argument checking
  - `--help` support
- Templates handle spaces in filenames safely using null-delimited streams
- Paired-end file validation checks both existence and non-empty patterns
- Input/output paths are converted to absolute paths for safety
- The Slurm helper submits and exits; jobs create their own status markers
- Docker examples assume mounting `$(pwd)` to `/work` in containers
- All templates include timing information and sample counts
- Helper scripts are version-stamped for tracking changes

---

## Best Practices

**Before running:**

1. Validate your input structure: `helpers/validate-step.sh INPUT_DIR`
2. Test with a dry run: `DRY=1 ./my-script.sh` (Approach 1)
3. Inspect generated job scripts before execution (Approach 2)

**During development:**

1. Test on a small subset of samples first
2. Check logs in `OUTPUT_DIR/sample_name/run.log`
3. Use `helpers/summarize-status.sh` frequently

**For reruns:**

1. Use `helpers/repair-failed.sh` to clean up failed samples
2. Rebuild with `MODE="failed"` or `MODE="unfinished"`
3. Consider `--clean-outputs` if partial outputs cause issues

**For production:**

1. Keep templates under version control with your project
2. Document customizations in comments
3. Test locally before submitting to Slurm
4. Use appropriate resource requests for Slurm jobs
