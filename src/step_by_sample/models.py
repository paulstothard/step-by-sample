from __future__ import annotations

from dataclasses import dataclass, replace
from enum import Enum
from pathlib import Path


class StepBySampleError(Exception):
    """An expected, user-facing workflow error."""


class InputMode(str, Enum):
    single = "single"
    paired_fixed = "paired-fixed"


class SelectionMode(str, Enum):
    unfinished = "unfinished"
    failed = "failed"
    all = "all"


class SampleState(str, Enum):
    done = "done"
    failed = "failed"
    pending = "pending"
    other = "other"
    conflict = "conflict"
    extra = "extra"


@dataclass(frozen=True)
class StepConfig:
    source: Path
    input_dir: Path
    output_dir: Path
    job_dir: Path
    run_list: Path
    command: Path
    input_mode: InputMode = InputMode.single
    input_name: str = "input.dat"
    r1_name: str = "R1.fastq.gz"
    r2_name: str = "R2.fastq.gz"
    mode: SelectionMode = SelectionMode.unfinished
    strict: bool = False

    def with_runtime_options(
        self,
        *,
        mode: SelectionMode | None = None,
        strict: bool | None = None,
    ) -> StepConfig:
        return replace(
            self,
            mode=self.mode if mode is None else mode,
            strict=self.strict if strict is None else strict,
        )


@dataclass(frozen=True)
class GenerationResult:
    total: int
    created: tuple[str, ...]
    missing: tuple[str, ...]
    skipped: tuple[str, ...]
    job_dir: Path
    run_list: Path


@dataclass(frozen=True)
class JobResult:
    script: Path
    returncode: int
    stdout: str
    stderr: str

    @property
    def succeeded(self) -> bool:
        return self.returncode == 0


@dataclass(frozen=True)
class SubmissionResult:
    entries: int
    array_script: Path
    output: str


@dataclass(frozen=True)
class SampleStatus:
    sample: str
    state: SampleState
    detail: str = ""


@dataclass(frozen=True)
class ResetItem:
    sample: str
    action: str


@dataclass(frozen=True)
class ResetResult:
    found: int
    reset: int
    busy: int
    items: tuple[ResetItem, ...]


@dataclass(frozen=True)
class ValidationResult:
    input_dir: Path
    samples: tuple[str, ...]
    non_directories: tuple[str, ...]
    empty_samples: tuple[str, ...]
    hidden_samples: tuple[str, ...]
