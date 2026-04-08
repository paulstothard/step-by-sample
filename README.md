# step-by-sample

A Bash-first pattern for per-sample workflow steps where you always:

1. generate one job script per sample,
2. collect them in a run list,
3. execute that run list locally or on Slurm.

Each sample writes its own `run.log` and ends with either `.done` or `.failed` in its output folder. The design stays intentionally small: no workflow engine, no background controller, just generated scripts plus helper commands.

## Core Model

Every workflow step follows the same structure:

- one input directory,
- one output directory,
- one subdirectory per sample,
- one generated job script per sample,
- one run list file containing those job script paths.

This keeps reruns, debugging, and local-vs-Slurm execution consistent.

## Quickstart

1. Copy the template:

```bash
cp examples/build-jobs-template.sh build-my-step.sh
```

1. Edit the template:

- set `IN`, `OUT`, `JOB_DIR`, and `LIST`,
- define how to find the sample input files,
- replace the example command with the real tool invocation.

1. Generate jobs:

```bash
./build-my-step.sh
```

1. Execute the run list locally:

```bash
helpers/run-list-local.sh run-quast.txt 4
```

1. Or execute the same run list on Slurm:

```bash
helpers/run-list-slurm.sh run-quast.txt \
  --account my_account \
  --partition cpu \
  --time 08:00:00 \
  --mem 16G \
  --cpus 8 \
  --array-max 20
```

1. Check results:

```bash
helpers/summarize-status.sh quast_output
```

## Folder Convention

At a given step, input and output usually look like this:

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

## Workflow Template

The only workflow template is [examples/build-jobs-template.sh](examples/build-jobs-template.sh).

It generates:

- a job directory such as `jobs-quast/`,
- a run list such as `run-quast.txt`,
- one executable script per sample.

That gives you:

- inspection before execution,
- easy single-sample reruns,
- the same generated work unit for local and Slurm execution,
- selective rebuilds with `MODE=unfinished`, `MODE=failed`, or `MODE=all`,
- no hidden state beyond filesystem markers and logs.

### Template Workflow

Generate job scripts:

```bash
./build-my-step.sh
```

Inspect what was built:

```bash
cat run-quast.txt
ls jobs-quast/
```

Run one sample directly if needed:

```bash
bash jobs-quast/sample2.sh
```

## Execution Helpers

### Local execution

[helpers/run-list-local.sh](helpers/run-list-local.sh) executes a run list with configurable parallelism:

```bash
helpers/run-list-local.sh run-quast.txt 4
```

### Slurm execution

[helpers/run-list-slurm.sh](helpers/run-list-slurm.sh) submits the same run list as a Slurm array job:

```bash
helpers/run-list-slurm.sh run-quast.txt \
  --account my_account \
  --partition cpu \
  --time 08:00:00 \
  --mem 16G \
  --cpus 8 \
  --array-max 20
```

If your cluster needs environment setup before `module load`, use `--setup-file` and one or more `--module` options:

```bash
helpers/run-list-slurm.sh run-quast.txt \
  --account my_account \
  --partition cpu \
  --setup-file /etc/profile.d/modules.sh \
  --module quast/5.2.0 \
  --module python/3.11
```

## Utility Helpers

- [helpers/validate-step.sh](helpers/validate-step.sh): validate input directory structure before running.
- [helpers/summarize-status.sh](helpers/summarize-status.sh): report done/failed/other counts.
- [helpers/repair-failed.sh](helpers/repair-failed.sh): remove `.failed` markers and optionally clean partial outputs.
- [helpers/common.sh](helpers/common.sh): shared shell utilities for templates and custom scripts.

## Reruns and Recovery

Rerun one sample directly:

```bash
bash jobs-quast/sample2.sh
```

Rebuild the run list for failed samples only:

```bash
MODE="failed" ./build-my-step.sh
helpers/run-list-local.sh run-quast.txt 4
```

Rebuild for unfinished samples:

```bash
MODE="unfinished" ./build-my-step.sh
helpers/run-list-local.sh run-quast.txt 4
```

Clean up failed outputs before rebuilding:

```bash
helpers/repair-failed.sh quast_output --clean-outputs
MODE="unfinished" ./build-my-step.sh
helpers/run-list-local.sh run-quast.txt 4
```

Force a full rebuild of all sample jobs:

```bash
FORCE=1 ./build-my-step.sh
```

## Project Structure

```text
step-by-sample/
├── README.md
├── .gitignore
├── examples/
│   └── build-jobs-template.sh      # Workflow template
├── helpers/
│   ├── common.sh                   # Shared utility functions
│   ├── run-list-local.sh           # Local execution runner
│   ├── run-list-slurm.sh           # Slurm array submitter
│   ├── summarize-status.sh         # Status reporter
│   ├── validate-step.sh            # Input validation
│   └── repair-failed.sh            # Failed sample cleanup
└── tests/
    ├── run-all-tests.sh            # Main test runner
    ├── test-01-workflow.sh         # Core workflow template tests
    ├── test-02-helpers.sh          # Helper utility tests
    ├── test-03-edge-cases.sh       # Edge case tests
    ├── test-04-reruns.sh           # Rerun and recovery tests
    ├── lib/                        # Test helpers and mocks
    └── mock-slurm/                 # Mock Slurm for local testing
```

## Testing

Run the full suite:

```bash
cd tests
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

Run a specific file:

```bash
./run-all-tests.sh "test-01*"
```

Coverage includes:

- core workflow generation and execution,
- helper utilities,
- rerun and recovery behavior,
- edge cases such as spaces, symlinks, and large sample counts,
- local testing of Slurm submission behavior.

See [tests/README.md](tests/README.md) for the full testing guide.

## Best Practices

Before running:

1. Validate the input structure with `helpers/validate-step.sh INPUT_DIR`.
2. Generate the per-sample job scripts and inspect them before executing.
3. Test locally on a small subset before using Slurm.

During development:

1. Keep your edited template under version control.
2. Check `OUTPUT_DIR/sample_name/run.log` first when debugging.
3. Use `helpers/summarize-status.sh` frequently while iterating.

For production:

1. Set explicit Slurm resources instead of relying on defaults.
2. Use `--setup-file` and `--module` when your cluster environment requires it.
3. Keep rerun behavior explicit by rebuilding with `MODE=failed` or `MODE=unfinished`.

## Notes

- Scripts use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Generated run lists contain absolute job script paths so they can be executed from any working directory.
- The Slurm helper submits and exits; per-sample job scripts create the status markers.
- Docker examples in the template assume mounting `$(pwd)` to `/work`.
