# Test suite

The project uses pytest for behavior and end-to-end tests and Ruff for static
checks and formatting.

```bash
uv sync --extra dev
uv run pytest
uv run ruff check src tests examples
```

Run one area or one test:

```bash
uv run pytest tests/test_workflow.py
uv run pytest tests/test_commands.py::test_submit_creates_and_sends_slurm_array
```

## Coverage

- `test_config.py`: unified help, starter configuration, path resolution, and
  invalid settings.
- `test_workflow.py`: generation, local execution, rerun selection, strict
  inputs, paired inputs, special sample names, locks, and generated ShellCheck.
- `test_commands.py`: CLI failures, status, guarded reset, validation, and mock
  Slurm submission.
- `test_examples.py`: both documented examples copied into and run from a path
  containing spaces.

Tests use real generated job scripts and real marker transitions. The Slurm
test replaces only `sbatch`, capturing and inspecting the generated array
script without contacting a scheduler.
