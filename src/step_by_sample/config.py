from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - exercised on Python 3.10
    import tomli as tomllib

from step_by_sample.models import InputMode, SelectionMode, StepBySampleError, StepConfig

CONFIG_TEMPLATE = """\
# Paths are resolved relative to this file.
[step]
input_dir = "input-samples"
output_dir = "my-step-output"
job_dir = "jobs-my-step"
run_list = "run-my-step.txt"

# The executable receives:
#   single:       OUT_DIR INPUT_FILE SAMPLE_NAME
#   paired-fixed: OUT_DIR R1_FILE R2_FILE SAMPLE_NAME
command = "./process_sample.py"

input_mode = "single"          # single or paired-fixed
input_name = "input.dat"       # used for single
r1_name = "R1.fastq.gz"        # used for paired-fixed
r2_name = "R2.fastq.gz"        # used for paired-fixed

mode = "unfinished"            # unfinished, failed, or all
strict = true                   # fail generation when an input is missing
"""

_ALLOWED_KEYS = {
    "input_dir",
    "output_dir",
    "job_dir",
    "run_list",
    "command",
    "input_mode",
    "input_name",
    "r1_name",
    "r2_name",
    "mode",
    "strict",
}
_REQUIRED_KEYS = {"input_dir", "output_dir", "job_dir", "run_list", "command"}


def write_starter_config(path: Path, *, force: bool = False) -> Path:
    path = path.expanduser().resolve()
    if path.exists() and not force:
        raise StepBySampleError(f"configuration already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(CONFIG_TEMPLATE, encoding="utf-8")
    return path


def _required_string(data: dict[str, Any], key: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise StepBySampleError(f"[step].{key} must be a non-empty string")
    if "\n" in value or "\r" in value:
        raise StepBySampleError(f"[step].{key} cannot contain newlines")
    return value


def _optional_string(data: dict[str, Any], key: str, default: str) -> str:
    value = data.get(key, default)
    if not isinstance(value, str) or not value:
        raise StepBySampleError(f"[step].{key} must be a non-empty string")
    if "/" in value or "\\" in value or "\n" in value or "\r" in value:
        raise StepBySampleError(f"[step].{key} must be a plain file name")
    return value


def _resolve_path(root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    return path.resolve()


def _resolve_command(root: Path, value: str) -> Path:
    candidate = Path(value).expanduser()
    if candidate.is_absolute() or candidate.parent != Path(".") or (root / candidate).exists():
        command = _resolve_path(root, value)
    else:
        found = shutil.which(value)
        if found is None:
            raise StepBySampleError(f"command is not executable or was not found in PATH: {value}")
        command = Path(found).resolve()

    if not command.is_file():
        raise StepBySampleError(f"command file not found: {command}")
    if not os.access(command, os.X_OK):
        raise StepBySampleError(f"command is not executable: {command}")
    return command


def load_config(path: Path) -> StepConfig:
    source = path.expanduser().resolve()
    if not source.is_file():
        raise StepBySampleError(f"configuration not found: {source}")

    try:
        document = tomllib.loads(source.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError) as exc:
        raise StepBySampleError(f"could not read configuration {source}: {exc}") from exc

    data = document.get("step")
    if not isinstance(data, dict):
        raise StepBySampleError(f"configuration must contain a [step] table: {source}")

    unknown = sorted(set(data) - _ALLOWED_KEYS)
    if unknown:
        raise StepBySampleError(f"unknown [step] setting(s): {', '.join(unknown)}")
    missing = sorted(_REQUIRED_KEYS - set(data))
    if missing:
        raise StepBySampleError(f"missing [step] setting(s): {', '.join(missing)}")

    root = source.parent
    input_mode_value = data.get("input_mode", InputMode.single.value)
    mode_value = data.get("mode", SelectionMode.unfinished.value)
    strict = data.get("strict", False)

    try:
        input_mode = InputMode(input_mode_value)
    except (TypeError, ValueError) as exc:
        choices = ", ".join(mode.value for mode in InputMode)
        raise StepBySampleError(f"[step].input_mode must be one of: {choices}") from exc
    try:
        mode = SelectionMode(mode_value)
    except (TypeError, ValueError) as exc:
        choices = ", ".join(item.value for item in SelectionMode)
        raise StepBySampleError(f"[step].mode must be one of: {choices}") from exc
    if not isinstance(strict, bool):
        raise StepBySampleError("[step].strict must be true or false")

    return StepConfig(
        source=source,
        input_dir=_resolve_path(root, _required_string(data, "input_dir")),
        output_dir=_resolve_path(root, _required_string(data, "output_dir")),
        job_dir=_resolve_path(root, _required_string(data, "job_dir")),
        run_list=_resolve_path(root, _required_string(data, "run_list")),
        command=_resolve_command(root, _required_string(data, "command")),
        input_mode=input_mode,
        input_name=_optional_string(data, "input_name", "input.dat"),
        r1_name=_optional_string(data, "r1_name", "R1.fastq.gz"),
        r2_name=_optional_string(data, "r2_name", "R2.fastq.gz"),
        mode=mode,
        strict=strict,
    )
