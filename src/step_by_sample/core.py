from __future__ import annotations

import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
from collections import Counter
from collections.abc import Callable, Mapping
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from step_by_sample.models import (
    GenerationResult,
    InputMode,
    JobResult,
    ResetItem,
    ResetResult,
    SampleState,
    SampleStatus,
    SelectionMode,
    StepBySampleError,
    StepConfig,
    SubmissionResult,
    ValidationResult,
)

_JOB_TEMPLATE = r"""#!/usr/bin/env bash
set -euo pipefail

STEP_COMMAND=@@STEP_COMMAND@@
input_mode=@@INPUT_MODE@@

sample=@@SAMPLE@@
sample_dir=@@SAMPLE_DIR@@
out_dir=@@OUT_DIR@@
log=@@LOG@@
done_marker=@@DONE@@
fail_marker=@@FAILED@@
f=@@INPUT@@
r1=@@R1@@
r2=@@R2@@

mkdir -p "$out_dir"
lock_dir="$out_dir/.running"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "BUSY  $sample  another run is already active" >&2
  exit 75
fi

job_complete=0
cleanup_job() {
  if [[ "$job_complete" -ne 1 ]]; then
    : >"$fail_marker"
    rm -f "$done_marker"
  fi
  rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup_job EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

rm -f "$fail_marker" "$done_marker"

if [[ "$input_mode" == "single" ]] && [[ ! -f "$f" ]]; then
  echo "FAIL  $sample  missing input: $f"
  : >"$fail_marker"
  exit 1
fi

if [[ "$input_mode" == "paired-fixed" ]] \
  && { [[ -z "$r1" ]] || [[ -z "$r2" ]] || [[ ! -f "$r1" ]] || [[ ! -f "$r2" ]]; }; then
  echo "FAIL  $sample  missing or incomplete paired input"
  : >"$fail_marker"
  exit 1
fi

echo "START $sample"

if {
  echo "=== $sample ==="
  date
  echo "Sample dir: $sample_dir"
  echo "Output dir: $out_dir"
  echo

  if [[ "$input_mode" == "single" ]]; then
    "$STEP_COMMAND" "$out_dir" "$f" "$sample"
  else
    "$STEP_COMMAND" "$out_dir" "$r1" "$r2" "$sample"
  fi
} >"$log" 2>&1; then
  : >"$done_marker"
  rm -f "$fail_marker"
  job_complete=1
  echo "DONE  $sample"
  exit 0
else
  : >"$fail_marker"
  job_complete=1
  echo "FAIL  $sample  see $log"
  tail -n 20 "$log" >&2 || true
  exit 1
fi
"""

_SBATCH_TEMPLATE = r"""#!/usr/bin/env bash
#SBATCH --time=@@TIME@@
#SBATCH --mem=@@MEM@@
#SBATCH --cpus-per-task=@@CPUS@@
#SBATCH --array=1-@@COUNT@@%@@ARRAY_MAX@@
#SBATCH --output=@@LOG_DIR@@/%A_%a.out
#SBATCH --error=@@LOG_DIR@@/%A_%a.err
@@ACCOUNT_LINE@@
@@PARTITION_LINE@@

set -euo pipefail

cd @@SUBMIT_DIR@@

run_list=@@RUN_LIST@@
setup_file=@@SETUP_FILE@@
module_requested=@@MODULE_REQUESTED@@
script=$(grep -Ev '^[[:space:]]*($|#)' "$run_list" | sed -n "${SLURM_ARRAY_TASK_ID}p")

if [[ -z "$script" ]]; then
  echo "No script found for SLURM_ARRAY_TASK_ID=$SLURM_ARRAY_TASK_ID" >&2
  exit 1
fi

if [[ -n "$setup_file" ]]; then
  # shellcheck source=/dev/null
  source "$setup_file"
fi

if [[ "$module_requested" -eq 1 ]] && ! command -v module >/dev/null 2>&1; then
  for candidate in /etc/profile.d/modules.sh /usr/share/Modules/init/bash /etc/profile.d/lmod.sh; do
    if [[ -f "$candidate" ]]; then
      # shellcheck source=/dev/null
      source "$candidate"
      break
    fi
  done
fi

if [[ "$module_requested" -eq 1 ]] && ! command -v module >/dev/null 2>&1; then
  echo "Modules were requested, but the module command is unavailable." >&2
  echo "Use --setup-file to source the cluster environment first." >&2
  exit 1
fi

@@MODULE_LINES@@

echo "Task:   $SLURM_ARRAY_TASK_ID"
echo "Script: $script"
bash "$script"
"""

_TOKEN = re.compile(r"@@([A-Z0-9_]+)@@")


def _render_tokens(template: str, values: Mapping[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        try:
            return values[key]
        except KeyError as exc:  # pragma: no cover - developer error
            raise RuntimeError(f"missing template token: {key}") from exc

    return _TOKEN.sub(replace, template)


def _atomic_write(path: Path, text: str, *, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(handle, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
        if executable:
            temporary.chmod(
                stat.S_IRUSR
                | stat.S_IWUSR
                | stat.S_IXUSR
                | stat.S_IRGRP
                | stat.S_IXGRP
                | stat.S_IROTH
                | stat.S_IXOTH
            )
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _sample_directories(input_dir: Path) -> list[Path]:
    try:
        samples = sorted(
            (path for path in input_dir.iterdir() if path.is_dir()), key=lambda p: p.name
        )
    except OSError as exc:
        raise StepBySampleError(f"could not scan input directory {input_dir}: {exc}") from exc
    for sample in samples:
        if "\n" in sample.name or "\r" in sample.name:
            raise StepBySampleError(f"sample names cannot contain newlines: {sample.name!r}")
    return samples


def _job_script(config: StepConfig, sample_dir: Path) -> str:
    sample = sample_dir.name
    output_dir = config.output_dir / sample
    single_input = (
        sample_dir / config.input_name if config.input_mode is InputMode.single else Path("")
    )
    r1 = sample_dir / config.r1_name if config.input_mode is InputMode.paired_fixed else Path("")
    r2 = sample_dir / config.r2_name if config.input_mode is InputMode.paired_fixed else Path("")

    def quote(value: object) -> str:
        return shlex.quote(str(value))

    return _render_tokens(
        _JOB_TEMPLATE,
        {
            "STEP_COMMAND": quote(config.command),
            "INPUT_MODE": quote(config.input_mode.value),
            "SAMPLE": quote(sample),
            "SAMPLE_DIR": quote(sample_dir),
            "OUT_DIR": quote(output_dir),
            "LOG": quote(output_dir / "run.log"),
            "DONE": quote(output_dir / ".done"),
            "FAILED": quote(output_dir / ".failed"),
            "INPUT": quote(single_input) if str(single_input) != "." else "''",
            "R1": quote(r1) if str(r1) != "." else "''",
            "R2": quote(r2) if str(r2) != "." else "''",
        },
    )


def generate_jobs(config: StepConfig, *, force: bool = False) -> GenerationResult:
    if not config.input_dir.is_dir():
        raise StepBySampleError(f"input directory not found: {config.input_dir}")

    config.output_dir.mkdir(parents=True, exist_ok=True)
    config.job_dir.mkdir(parents=True, exist_ok=True)
    config.run_list.parent.mkdir(parents=True, exist_ok=True)

    samples = _sample_directories(config.input_dir)
    created: list[str] = []
    missing: list[str] = []
    skipped: list[str] = []
    run_entries: list[str] = []

    for sample_dir in samples:
        sample = sample_dir.name
        output_dir = config.output_dir / sample
        job = config.job_dir / f"{sample}.sh"
        if config.input_mode is InputMode.single:
            has_inputs = (sample_dir / config.input_name).is_file()
        else:
            has_inputs = (sample_dir / config.r1_name).is_file() and (
                sample_dir / config.r2_name
            ).is_file()

        if not has_inputs:
            missing.append(sample)
            job.unlink(missing_ok=True)
            continue

        should_run = force or config.mode is SelectionMode.all
        if not should_run and config.mode is SelectionMode.unfinished:
            should_run = not (output_dir / ".done").is_file()
        if not should_run and config.mode is SelectionMode.failed:
            should_run = (output_dir / ".failed").is_file()

        if not should_run:
            skipped.append(sample)
            job.unlink(missing_ok=True)
            continue

        _atomic_write(job, _job_script(config, sample_dir), executable=True)
        created.append(sample)
        run_entries.append(str(job.resolve()))

    run_list_text = "".join(f"{entry}\n" for entry in run_entries)
    _atomic_write(config.run_list, run_list_text)
    return GenerationResult(
        total=len(samples),
        created=tuple(created),
        missing=tuple(missing),
        skipped=tuple(skipped),
        job_dir=config.job_dir,
        run_list=config.run_list,
    )


def read_run_list(path: Path) -> tuple[Path, ...]:
    run_list = path.expanduser().resolve()
    if not run_list.is_file():
        raise StepBySampleError(f"run list not found: {run_list}")
    try:
        lines = run_list.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise StepBySampleError(f"could not read run list {run_list}: {exc}") from exc

    scripts: list[Path] = []
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        script = Path(line).expanduser()
        if not script.is_absolute():
            script = run_list.parent / script
        script = script.resolve()
        if not script.is_file():
            raise StepBySampleError(f"listed job script not found: {script}")
        scripts.append(script)
    if not scripts:
        raise StepBySampleError(f"no runnable entries found in: {run_list}")
    return tuple(scripts)


def _run_one(script: Path, environment: Mapping[str, str] | None = None) -> JobResult:
    completed = subprocess.run(
        ["bash", str(script)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=None if environment is None else dict(environment),
        check=False,
    )
    return JobResult(script, completed.returncode, completed.stdout, completed.stderr)


def run_jobs(
    run_list: Path,
    *,
    jobs: int = 1,
    on_complete: Callable[[JobResult], None] | None = None,
    environment: Mapping[str, str] | None = None,
) -> tuple[JobResult, ...]:
    if jobs < 1:
        raise StepBySampleError("jobs must be an integer greater than zero")
    scripts = read_run_list(run_list)
    results: list[JobResult] = []
    with ThreadPoolExecutor(max_workers=jobs, thread_name_prefix="step-by-sample") as executor:
        futures = {executor.submit(_run_one, script, environment): script for script in scripts}
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
            if on_complete is not None:
                on_complete(result)
    order = {script: index for index, script in enumerate(scripts)}
    return tuple(sorted(results, key=lambda result: order[result.script]))


def _directive_value(name: str, value: str) -> str:
    if "\n" in value or "\r" in value:
        raise StepBySampleError(f"{name} cannot contain newlines")
    return value


def submit_jobs(
    run_list: Path,
    *,
    account: str | None = None,
    partition: str | None = None,
    time: str = "04:00:00",
    memory: str = "8G",
    cpus: int = 4,
    array_max: int = 20,
    log_dir: Path = Path("slurm-logs"),
    setup_file: Path | None = None,
    modules: tuple[str, ...] = (),
    keep_script: Path | None = None,
) -> SubmissionResult:
    scripts = read_run_list(run_list)
    run_list = run_list.expanduser().resolve()
    if cpus < 1:
        raise StepBySampleError("cpus must be an integer greater than zero")
    if array_max < 1:
        raise StepBySampleError("array-max must be an integer greater than zero")

    account = _directive_value("account", account or "")
    partition = _directive_value("partition", partition or "")
    time = _directive_value("time", time)
    memory = _directive_value("memory", memory)
    for module in modules:
        _directive_value("module", module)

    log_dir = log_dir.expanduser().resolve()
    log_dir.mkdir(parents=True, exist_ok=True)
    if setup_file is not None:
        setup_file = setup_file.expanduser().resolve()
        if not setup_file.is_file():
            raise StepBySampleError(f"setup file not found: {setup_file}")

    if keep_script is None:
        handle, script_name = tempfile.mkstemp(prefix="step-by-sample-", suffix=".sbatch")
        os.close(handle)
        array_script = Path(script_name)
    else:
        array_script = keep_script.expanduser().resolve()

    module_lines = "\n".join(f"module load {shlex.quote(module)}" for module in modules)
    script_text = _render_tokens(
        _SBATCH_TEMPLATE,
        {
            "TIME": time,
            "MEM": memory,
            "CPUS": str(cpus),
            "COUNT": str(len(scripts)),
            "ARRAY_MAX": str(array_max),
            "LOG_DIR": str(log_dir),
            "ACCOUNT_LINE": f"#SBATCH --account={account}" if account else "",
            "PARTITION_LINE": f"#SBATCH --partition={partition}" if partition else "",
            "SUBMIT_DIR": shlex.quote(str(Path.cwd().resolve())),
            "RUN_LIST": shlex.quote(str(run_list)),
            "SETUP_FILE": shlex.quote(str(setup_file)) if setup_file else "''",
            "MODULE_REQUESTED": "1" if modules else "0",
            "MODULE_LINES": module_lines,
        },
    )
    _atomic_write(array_script, script_text, executable=True)

    sbatch = shutil.which("sbatch")
    if sbatch is None:
        raise StepBySampleError("sbatch was not found in PATH")
    completed = subprocess.run(
        [sbatch, str(array_script)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "unknown sbatch error"
        raise StepBySampleError(f"sbatch failed: {detail}")
    return SubmissionResult(len(scripts), array_script, completed.stdout.strip())


def inspect_status(output_dir: Path, *, input_dir: Path | None = None) -> tuple[SampleStatus, ...]:
    output_dir = output_dir.expanduser().resolve()
    if not output_dir.is_dir():
        raise StepBySampleError(f"output directory not found: {output_dir}")
    if input_dir is not None:
        input_dir = input_dir.expanduser().resolve()
        if not input_dir.is_dir():
            raise StepBySampleError(f"input directory not found: {input_dir}")
        scan_dir = input_dir
    else:
        scan_dir = output_dir

    statuses: list[SampleStatus] = []
    for sample_dir in _sample_directories(scan_dir):
        sample = sample_dir.name
        status_dir = output_dir / sample
        done = (status_dir / ".done").is_file()
        failed = (status_dir / ".failed").is_file()
        if done and failed:
            statuses.append(SampleStatus(sample, SampleState.conflict, "both markers exist"))
        elif done:
            statuses.append(SampleStatus(sample, SampleState.done))
        elif failed:
            statuses.append(SampleStatus(sample, SampleState.failed, str(status_dir / "run.log")))
        elif not status_dir.is_dir():
            statuses.append(SampleStatus(sample, SampleState.pending, "no output directory"))
        else:
            statuses.append(SampleStatus(sample, SampleState.other, "no status marker"))

    if input_dir is not None:
        input_names = {path.name for path in _sample_directories(input_dir)}
        for output in _sample_directories(output_dir):
            if output.name not in input_names:
                statuses.append(SampleStatus(output.name, SampleState.extra, "no matching input"))
    return tuple(statuses)


def status_counts(statuses: tuple[SampleStatus, ...]) -> Counter[SampleState]:
    return Counter(item.state for item in statuses)


def reset_failed(
    output_dir: Path,
    *,
    clean_outputs: bool = False,
    dry_run: bool = False,
    force_busy: bool = False,
) -> ResetResult:
    output_dir = output_dir.expanduser().resolve()
    if not output_dir.is_dir():
        raise StepBySampleError(f"output directory not found: {output_dir}")

    items: list[ResetItem] = []
    found = 0
    reset = 0
    busy = 0
    for sample_dir in _sample_directories(output_dir):
        failed = sample_dir / ".failed"
        if not failed.is_file():
            continue
        found += 1
        if (sample_dir / ".running").exists() and not force_busy:
            busy += 1
            items.append(ResetItem(sample_dir.name, "skipped: active lock"))
            continue

        action = "would clean outputs" if clean_outputs else "would clear markers"
        if not dry_run:
            if clean_outputs:
                for child in sample_dir.iterdir():
                    if child.name == "run.log":
                        continue
                    if child.is_dir() and not child.is_symlink():
                        shutil.rmtree(child)
                    else:
                        child.unlink(missing_ok=True)
                action = "cleaned outputs"
            else:
                failed.unlink(missing_ok=True)
                (sample_dir / ".done").unlink(missing_ok=True)
                action = "cleared markers"
            reset += 1
        items.append(ResetItem(sample_dir.name, action))
    return ResetResult(found, reset, busy, tuple(items))


def validate_inputs(input_dir: Path) -> ValidationResult:
    input_dir = input_dir.expanduser().resolve()
    if not input_dir.exists():
        raise StepBySampleError(f"input directory does not exist: {input_dir}")
    if not input_dir.is_dir():
        raise StepBySampleError(f"input path is not a directory: {input_dir}")
    if not os.access(input_dir, os.R_OK):
        raise StepBySampleError(f"input directory is not readable: {input_dir}")

    try:
        entries = sorted(input_dir.iterdir(), key=lambda path: path.name)
        sample_dirs = [path for path in entries if path.is_dir()]
        non_directories = [path.name for path in entries if not path.is_dir()]
        empty_samples = [path.name for path in sample_dirs if next(path.iterdir(), None) is None]
    except OSError as exc:
        raise StepBySampleError(f"could not inspect input directory {input_dir}: {exc}") from exc
    if not sample_dirs:
        raise StepBySampleError(f"no sample subdirectories found in: {input_dir}")

    return ValidationResult(
        input_dir=input_dir,
        samples=tuple(path.name for path in sample_dirs),
        non_directories=tuple(non_directories),
        empty_samples=tuple(empty_samples),
        hidden_samples=tuple(path.name for path in sample_dirs if path.name.startswith(".")),
    )
