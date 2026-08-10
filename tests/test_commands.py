from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest
from conftest import make_executable
from typer.testing import CliRunner

from step_by_sample.cli import app
from step_by_sample.config import load_config
from step_by_sample.core import (
    generate_jobs,
    inspect_status,
    reset_failed,
    status_counts,
    submit_jobs,
    validate_inputs,
)
from step_by_sample.models import SampleState, StepBySampleError

runner = CliRunner()


def test_generate_cli_strict_mode_exits_nonzero(
    tmp_path: Path, processor_factory, sample_factory, config_writer
) -> None:
    processor = processor_factory()
    sample_factory(tmp_path / "input", ("good",))
    (tmp_path / "input" / "missing").mkdir()
    config = config_writer(tmp_path, processor, mode="all", strict=True)
    result = runner.invoke(app, ["generate", str(config)])
    assert result.exit_code == 1
    assert "MISSING" in result.stdout
    assert "strict mode" in result.stdout + result.stderr
    assert (tmp_path / "run.txt").is_file()


def test_run_cli_reports_failures(
    tmp_path: Path, processor_factory, sample_factory, config_writer
) -> None:
    processor = processor_factory(fail_prefix="bad")
    sample_factory(tmp_path / "input", ("good", "bad-one"))
    settings = load_config(config_writer(tmp_path, processor, mode="all"))
    generate_jobs(settings)
    result = runner.invoke(app, ["run", str(settings.run_list), "--jobs", "2"])
    assert result.exit_code == 1
    assert "FAILED" in result.stdout
    assert "intentional failure" in result.stdout


def test_status_detects_pending_failed_conflict_and_extra(tmp_path: Path) -> None:
    input_dir = tmp_path / "input"
    output_dir = tmp_path / "output"
    for name in ("done", "failed", "pending", "conflict"):
        (input_dir / name).mkdir(parents=True)
    for name in ("done", "failed", "conflict", "extra"):
        (output_dir / name).mkdir(parents=True)
    (output_dir / "done" / ".done").touch()
    (output_dir / "failed" / ".failed").touch()
    (output_dir / "conflict" / ".done").touch()
    (output_dir / "conflict" / ".failed").touch()

    statuses = inspect_status(output_dir, input_dir=input_dir)
    counts = status_counts(statuses)
    assert counts[SampleState.done] == 1
    assert counts[SampleState.failed] == 1
    assert counts[SampleState.pending] == 1
    assert counts[SampleState.conflict] == 1
    assert counts[SampleState.extra] == 1

    result = runner.invoke(
        app,
        ["status", str(output_dir), "--input-dir", str(input_dir), "--fail-on-problems"],
    )
    assert result.exit_code == 1
    assert "PENDING" in result.stdout
    assert "CONFLICT" in result.stdout


def test_reset_clean_outputs_preserves_log(tmp_path: Path) -> None:
    sample = tmp_path / "output" / "failed"
    (sample / "nested").mkdir(parents=True)
    (sample / ".failed").touch()
    (sample / "run.log").write_text("diagnostic\n", encoding="utf-8")
    (sample / "partial.txt").write_text("partial\n", encoding="utf-8")
    (sample / "nested" / "result").write_text("partial\n", encoding="utf-8")

    result = reset_failed(tmp_path / "output", clean_outputs=True)
    assert result.reset == 1
    assert (sample / "run.log").read_text() == "diagnostic\n"
    assert not (sample / ".failed").exists()
    assert not (sample / "partial.txt").exists()
    assert not (sample / "nested").exists()


def test_reset_refuses_active_sample_without_force(tmp_path: Path) -> None:
    sample = tmp_path / "output" / "active"
    (sample / ".running").mkdir(parents=True)
    (sample / ".failed").touch()
    result = reset_failed(tmp_path / "output", clean_outputs=True)
    assert result.busy == 1
    assert result.reset == 0
    assert (sample / ".failed").exists()


def test_validate_reports_warnings(tmp_path: Path) -> None:
    input_dir = tmp_path / "input"
    (input_dir / "good").mkdir(parents=True)
    (input_dir / "good" / "data").touch()
    (input_dir / "empty").mkdir()
    (input_dir / ".hidden").mkdir()
    (input_dir / "README.txt").write_text("ignored", encoding="utf-8")
    result = validate_inputs(input_dir)
    assert result.samples == (".hidden", "empty", "good")
    assert result.non_directories == ("README.txt",)
    assert result.empty_samples == (".hidden", "empty")
    assert result.hidden_samples == (".hidden",)


def test_validate_rejects_empty_input_directory(tmp_path: Path) -> None:
    input_dir = tmp_path / "input"
    input_dir.mkdir()
    with pytest.raises(StepBySampleError, match="no sample subdirectories"):
        validate_inputs(input_dir)


def test_submit_creates_and_sends_slurm_array(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    job = make_executable(tmp_path / "job.sh", "#!/usr/bin/env bash\nexit 0\n")
    run_list = tmp_path / "run.txt"
    run_list.write_text(f"# jobs\n\n{job}\n", encoding="utf-8")
    capture = tmp_path / "captured.sbatch"
    mock_bin = tmp_path / "bin"
    mock_bin.mkdir()
    make_executable(
        mock_bin / "sbatch",
        """#!/usr/bin/env python3
import os
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
pathlib.Path(os.environ["SBATCH_CAPTURE"]).write_text(source.read_text())
print("Submitted batch job 12345")
""",
    )
    monkeypatch.setenv("PATH", f"{mock_bin}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("SBATCH_CAPTURE", str(capture))
    kept = tmp_path / "array.sbatch"

    result = submit_jobs(
        run_list,
        account="account",
        partition="cpu",
        cpus=8,
        array_max=3,
        modules=("python/3.11",),
        keep_script=kept,
        log_dir=tmp_path / "logs",
    )
    assert result.output == "Submitted batch job 12345"
    text = capture.read_text()
    assert "#SBATCH --array=1-1%3" in text
    assert "#SBATCH --cpus-per-task=8" in text
    assert "module load python/3.11" in text
    if shutil.which("shellcheck") is not None:
        checked = subprocess.run(
            ["shellcheck", "-S", "warning", str(kept)],
            capture_output=True,
            text=True,
            check=False,
        )
        assert checked.returncode == 0, checked.stdout + checked.stderr


def test_submit_rejects_empty_run_list(tmp_path: Path) -> None:
    run_list = tmp_path / "run.txt"
    run_list.write_text("# no jobs\n", encoding="utf-8")
    with pytest.raises(StepBySampleError, match="no runnable entries"):
        submit_jobs(run_list)
