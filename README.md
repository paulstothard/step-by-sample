# step-by-sample

A Bash-first pattern for workflow steps that process one sample at a time:

1. generate one job script per sample,
2. collect those scripts in a run list,
3. execute the same run list locally or as a Slurm array.

Each sample writes `run.log` and ends with `.done` or `.failed` in its output
directory. A transient `.running` lock prevents two copies of the same sample
job from running at once. There is no workflow engine or background controller;
the generated scripts, run list, logs, and markers are the complete state.

## Requirements

- Bash 4 or newer,
- standard Unix utilities including `find`, `sort`, `grep`, and `xargs`,
- `sbatch` only when using Slurm.

On macOS, `/bin/bash` is normally Bash 3.2. Install a newer Bash and ensure it
appears before `/bin` in `PATH`. The entry-point scripts report a clear version
error when started with an older Bash.

## Quickstart

Copy and edit the template:

```bash
cp templates/generate-jobs-template.sh generate-my-step-jobs.sh
```

Set `IN`, `OUT`, `JOB_DIR`, and `LIST`, configure the input layout, and set
`STEP_COMMAND` to a tested executable for the step. Generate jobs:

```bash
./generate-my-step-jobs.sh
```

Every generation run rewrites the run list from the current inputs and selection
mode.
Inspect it before execution:

```bash
cat run-my-step.txt
ls jobs-my-step/
```

Run up to four samples locally:

```bash
bin/run-jobs-local.sh run-my-step.txt 4
```

Or submit the same list to Slurm:

```bash
bin/submit-jobs-slurm.sh run-my-step.txt \
  --account my_account \
  --partition cpu \
  --time 08:00:00 \
  --mem 16G \
  --cpus 8 \
  --array-max 20
```

Compare outputs with the expected input samples:

```bash
bin/show-step-status.sh my-step-output --input-dir input-samples
```

## Folder convention

```text
input-samples/
  sample1/
    input.dat
  sample2/
    input.dat

my-step-output/
  sample1/
    result.txt
    run.log
    .done
  sample2/
    result.txt
    run.log
    .failed
```

The run list contains absolute paths to the generated jobs, so it can be used
from any working directory.

## Configuring the template

The main template is
[templates/generate-jobs-template.sh](templates/generate-jobs-template.sh). Its common
settings are:

```bash
IN=input-samples
OUT=my-step-output
JOB_DIR=jobs-my-step
LIST=run-my-step.txt

MODE=unfinished  # unfinished, failed, or all
FORCE=0          # 1 overrides MODE and selects every sample
STRICT=0         # 1 fails generation if any expected input is missing
```

`MODE=unfinished` selects anything without `.done`, including never-run and
previously failed samples. `MODE=failed` selects only samples that currently
have `.failed`. `FORCE=1` selects everything.

### Fixed-name inputs

The template directly supports single and paired fixed-name layouts:

```bash
# sample1/input.dat
INPUT_MODE=single
INPUT_NAME=input.dat

# sample1/R1.fastq.gz and sample1/R2.fastq.gz
INPUT_MODE=paired-fixed
R1_NAME=R1.fastq.gz
R2_NAME=R2.fastq.gz
```

The clearly marked input-discovery block can be edited for variable file names
or other layouts.

### External step commands

`STEP_COMMAND` can point to an executable instead of putting a long tool command
inside the template. Generated jobs invoke it as:

```text
single:       STEP_COMMAND OUT_DIR INPUT_FILE SAMPLE_NAME
paired-fixed: STEP_COMMAND OUT_DIR R1_FILE R2_FILE SAMPLE_NAME
```

Paths containing `/` are validated and converted to absolute paths during job
generation, so the generated jobs still work from another directory.

Values embedded in generated jobs are shell-escaped. Sample names may contain
spaces and shell metacharacters; newlines are rejected because the run-list
format is intentionally one path per line.

## Runnable examples

- [examples/runnable-single](examples/runnable-single) converts two text
  samples to uppercase.
- [examples/runnable-paired](examples/runnable-paired) counts reads in tiny
  paired FASTQ fixtures.

Both examples run without third-party bioinformatics tools and are tested end
to end. Each README shows the generation, execution, status, and output inspection
commands.

## Execution commands

### Local

```bash
bin/run-jobs-local.sh RUN_LIST [JOBS]
```

Blank lines and lines beginning with `#` are ignored. The command validates every
listed script before starting work and returns nonzero if any sample job fails.

### Slurm

```bash
bin/submit-jobs-slurm.sh RUN_LIST [options]
```

Useful options include `--account`, `--partition`, `--time`, `--mem`, `--cpus`,
`--array-max`, and `--log-dir`. Cluster initialization can be applied inside
every array task:

```bash
bin/submit-jobs-slurm.sh run-my-step.txt \
  --setup-file /etc/profile.d/modules.sh \
  --module my-tool/1.2.3 \
  --module python/3.11
```

`--array-max` limits concurrent tasks, not the total number submitted.

## Status and recovery

Summarize output directories alone:

```bash
bin/show-step-status.sh my-step-output
```

Supplying the input directory also reveals samples that never produced an
output directory and stale outputs with no corresponding input:

```bash
bin/show-step-status.sh my-step-output --input-dir input-samples
```

The summary reports done, failed, other, conflicting markers, and extra outputs.

Rerun samples that still have `.failed`:

```bash
MODE=failed ./generate-my-step-jobs.sh
bin/run-jobs-local.sh run-my-step.txt 4
```

Optionally clean failed outputs first:

```bash
bin/reset-failed-samples.sh my-step-output --clean-outputs
MODE=unfinished ./generate-my-step-jobs.sh
bin/run-jobs-local.sh run-my-step.txt 4
```

Repair removes `.failed`, so repaired samples must be selected with
`MODE=unfinished`, not `MODE=failed`. `run.log` is preserved during cleanup for
inspection, though the next run replaces it.

## Utility commands

- `bin/validate-step-inputs.sh`: validate input-directory structure before generation.
- `bin/show-step-status.sh`: report status, missing outputs, and conflicts.
- `bin/reset-failed-samples.sh`: clear failed markers and optionally partial outputs.
- `lib/common.sh`: internal functions sourced by templates and tests.

## Testing

Run everything:

```bash
tests/run-all-tests.sh
```

Other useful forms:

```bash
tests/run-all-tests.sh --verbose
tests/run-all-tests.sh --quick
tests/run-all-tests.sh 'test-03*'
```

The suite exercises the real template and commands, including:

- local and mock-Slurm execution,
- failed, unfinished, forced, repaired, and incremental reruns,
- spaces and shell metacharacters in sample names,
- relative paths with a noisy `CDPATH`,
- symlinked inputs, missing inputs, and large sample counts,
- concurrent starts of the same generated job,
- both runnable examples.

GitHub Actions runs the suite and ShellCheck on Linux and macOS. See
[tests/README.md](tests/README.md) for test-author documentation.

## Project structure

```text
step-by-sample/
├── README.md
├── templates/
│   └── generate-jobs-template.sh
├── bin/
│   ├── reset-failed-samples.sh
│   ├── run-jobs-local.sh
│   ├── show-step-status.sh
│   ├── submit-jobs-slurm.sh
│   └── validate-step-inputs.sh
├── lib/
│   └── common.sh
├── examples/
│   ├── runnable-single/
│   └── runnable-paired/
└── tests/
    ├── run-all-tests.sh
    ├── test-01-workflow.sh
    ├── test-02-commands.sh
    ├── test-03-edge-cases.sh
    ├── test-04-reruns.sh
    ├── test-05-examples.sh
    ├── lib/
    └── mock-slurm/
```

## Operational notes

- Missing inputs are counted during generation; use `STRICT=1` when they should
  make generation fail.
- Generated jobs mark unexpected exits and handled signals as failed and remove
  their lock on exit. `SIGKILL` cannot be trapped and may leave `.running`; after
  confirming no process is active, remove that stale directory before rerunning.
- Generated job directories and run lists are refreshed on every generation
  run; stale jobs for samples skipped by the current mode are removed.
