# step-by-sample

A small Python CLI for workflow steps that process one sample at a time.

```text
step-by-sample init       create a step configuration
step-by-sample validate   inspect sample inputs
step-by-sample generate   create one job per sample
step-by-sample run        execute jobs locally
step-by-sample submit     submit the same jobs to Slurm
step-by-sample status     summarize completion
step-by-sample reset      prepare failed samples for rerun
```

The interface is one discoverable executable with typed options, shell
completion, automatic color support, and clear errors. Each sample still gets
an independent job, `run.log`, and explicit `.done` or `.failed` marker. There
is no database or hidden controller: the generated jobs, run list, logs, and
markers are the complete workflow state.

## Requirements

- Python 3.10 or newer,
- Bash on execution nodes for the small generated job wrappers,
- `sbatch` only when submitting to Slurm.

The orchestration no longer depends on a particular Bash version or Unix
implementations of `find`, `sort`, `grep`, and `xargs`.

## Install

Install the command from a checkout with
[uv](https://docs.astral.sh/uv/guides/tools/):

```bash
uv tool install .
```

Or use pipx:

```bash
pipx install .
```

For development, create the locked environment and run the command through uv:

```bash
uv sync --extra dev
uv run step-by-sample --help
```

## Quickstart

Create a configuration:

```bash
step-by-sample init step.toml
```

Edit `step.toml` for one workflow step:

```toml
[step]
input_dir = "input-samples"
output_dir = "my-step-output"
job_dir = "jobs-my-step"
run_list = "run-my-step.txt"
command = "./process_sample.py"

input_mode = "single"
input_name = "input.dat"
mode = "unfinished"
strict = true
```

All relative paths are resolved from the configuration file, not the current
working directory. The command must be executable.

Validate, generate, and run up to four samples locally:

```bash
step-by-sample validate input-samples
step-by-sample generate step.toml
step-by-sample run run-my-step.txt --jobs 4
step-by-sample status my-step-output --input-dir input-samples
```

The run list contains absolute job paths, so it can be used from another
working directory.

## Input layouts

The built-in layouts use one directory per sample:

```text
input-samples/
  sample1/
    input.dat
  sample2/
    input.dat
```

Single fixed-name input:

```toml
input_mode = "single"
input_name = "input.dat"
```

Paired fixed-name input:

```toml
input_mode = "paired-fixed"
r1_name = "R1.fastq.gz"
r2_name = "R2.fastq.gz"
```

The configured executable receives stable positional arguments:

```text
single:       COMMAND OUT_DIR INPUT_FILE SAMPLE_NAME
paired-fixed: COMMAND OUT_DIR R1_FILE R2_FILE SAMPLE_NAME
```

Keeping the scientific command separate makes it easy to run and test directly
before generating hundreds of jobs. The command may be written in Python, R,
Bash, or any other executable language.

## Selecting samples

The configured `mode` controls which jobs are generated:

- `unfinished`: samples without `.done`, including new and previously failed samples;
- `failed`: only samples with `.failed`;
- `all`: every sample with the expected input.

Override it for one generation run:

```bash
step-by-sample generate step.toml --mode failed
step-by-sample generate step.toml --force
```

`strict = true` makes generation return nonzero when any expected input is
missing. Valid jobs and the run list are still written so the problem is easy
to inspect. Use `--no-strict` for a one-time override.

## Local execution

```bash
step-by-sample run run-my-step.txt --jobs 4
```

Blank lines and lines beginning with `#` are ignored. The command validates
every listed job before starting, displays progress in an interactive terminal,
and returns nonzero if any sample fails.

## Slurm arrays

Submit the same run list as one array:

```bash
step-by-sample submit run-my-step.txt \
  --account my_account \
  --partition cpu \
  --time 08:00:00 \
  --mem 16G \
  --cpus 8 \
  --array-max 20
```

`--array-max` limits concurrent tasks, not the total number submitted. Cluster
initialization and environment modules can be applied inside every task:

```bash
step-by-sample submit run-my-step.txt \
  --setup-file /etc/profile.d/modules.sh \
  --module my-tool/1.2.3 \
  --module python/3.11
```

Use `--keep-script array.sbatch` to retain the generated submission script at a
specific location for inspection.

## Status and recovery

Each successful sample has this shape:

```text
my-step-output/
  sample1/
    result.txt
    run.log
    .done
```

A failure has `.failed` instead. A transient `.running` directory prevents two
copies of the same sample job from running simultaneously.

Show failures, pending samples, conflicting markers, and unexpected outputs:

```bash
step-by-sample status my-step-output --input-dir input-samples
step-by-sample status my-step-output --input-dir input-samples --all
```

Generate failed jobs directly:

```bash
step-by-sample generate step.toml --mode failed
step-by-sample run run-my-step.txt --jobs 4
```

Or clear failed markers first so they are selected as unfinished:

```bash
step-by-sample reset my-step-output --dry-run
step-by-sample reset my-step-output --clean-outputs
step-by-sample generate step.toml --mode unfinished
```

Cleanup preserves `run.log`. It refuses to touch a sample with a `.running`
lock unless `--force-busy` is explicitly supplied.

## Runnable examples

- [examples/runnable-single](examples/runnable-single) converts two text samples
  to uppercase.
- [examples/runnable-paired](examples/runnable-paired) counts reads in tiny
  paired FASTQ fixtures.

Both use Python processing commands, require no bioinformatics software, and
are tested end to end in a path containing spaces.

## Terminal behavior

Rich formatting and color are enabled automatically when the output is a
compatible terminal. Redirected output remains plain. Set the standard
`NO_COLOR` environment variable to disable color explicitly:

```bash
NO_COLOR=1 step-by-sample status my-step-output
```

Install completion for the current shell with:

```bash
step-by-sample --install-completion
```

## Testing

```bash
uv sync --extra dev
uv run ruff check src tests examples
uv run pytest
```

The suite covers configuration validation, local and mock-Slurm execution,
failure recovery, paired inputs, rerun modes, shell metacharacters, concurrent
locks, generated-script ShellCheck, and both runnable examples. GitHub Actions
tests supported Python versions on Linux and macOS.

## Project structure

```text
step-by-sample/
├── pyproject.toml
├── uv.lock
├── src/step_by_sample/
│   ├── cli.py
│   ├── config.py
│   ├── core.py
│   └── models.py
├── examples/
│   ├── runnable-single/
│   └── runnable-paired/
└── tests/
```

## Why generated jobs still use Bash

Python now owns configuration, validation, paths, concurrency, state reporting,
cleanup, and submission. The generated job wrapper remains a short standalone
Bash file because Slurm can execute it without installing this package on every
compute node, and it naturally launches arbitrary scientific commands. Its
quoting and lifecycle behavior are generated centrally and tested rather than
copied and edited by users.

This project intentionally coordinates one independent workflow step. When a
workflow needs dependencies between several steps, provenance across a graph,
or automatic downstream scheduling, use a workflow engine such as Snakemake.

## Migrating from the Bash interface

The Python CLI replaces the previous public scripts:

| Previous script | Python command |
|---|---|
| `templates/generate-jobs-template.sh` | `step-by-sample init` + `generate` |
| `bin/run-jobs-local.sh` | `step-by-sample run` |
| `bin/submit-jobs-slurm.sh` | `step-by-sample submit` |
| `bin/show-step-status.sh` | `step-by-sample status` |
| `bin/reset-failed-samples.sh` | `step-by-sample reset` |
| `bin/validate-step-inputs.sh` | `step-by-sample validate` |

Existing output markers and run-list files remain conceptually compatible. A
TOML configuration replaces editing a generator script.
