from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from step_by_sample.config import load_config
from step_by_sample.core import generate_jobs, inspect_status, run_jobs
from step_by_sample.models import SampleState

PROJECT_ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize(
    ("example", "sample", "result_file", "expected"),
    [
        ("runnable-single", "alpha", "result.txt", "ALPHA EXAMPLE"),
        ("runnable-paired", "beta", "pair-summary.txt", "r1_reads=2"),
    ],
)
def test_documented_example_runs_end_to_end(
    tmp_path: Path, example: str, sample: str, result_file: str, expected: str
) -> None:
    target = tmp_path / "repository with spaces" / example
    shutil.copytree(PROJECT_ROOT / "examples" / example, target)
    settings = load_config(target / "step.toml")
    generated = generate_jobs(settings)
    assert generated.created == ("alpha", "beta")
    assert all(result.succeeded for result in run_jobs(settings.run_list, jobs=2))
    assert expected in (settings.output_dir / sample / result_file).read_text()
    statuses = inspect_status(settings.output_dir, input_dir=settings.input_dir)
    assert all(item.state is SampleState.done for item in statuses)
    assert not generate_jobs(settings).created
