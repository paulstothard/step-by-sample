from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest

from step_by_sample.config import load_config
from step_by_sample.core import generate_jobs, run_jobs
from step_by_sample.models import SelectionMode


def test_generate_and_run_single_inputs(
    tmp_path: Path, processor_factory, sample_factory, config_writer
) -> None:
    processor = processor_factory()
    sample_factory(tmp_path / "input", ("alpha", "beta"))
    settings = load_config(config_writer(tmp_path, processor, mode="all"))

    generated = generate_jobs(settings)
    assert generated.created == ("alpha", "beta")
    assert all(Path(line).is_absolute() for line in settings.run_list.read_text().splitlines())
    results = run_jobs(settings.run_list, jobs=2)
    assert all(result.succeeded for result in results)
    assert (settings.output_dir / "alpha" / ".done").is_file()
    assert "alpha:data for alpha" in (settings.output_dir / "alpha" / "result.txt").read_text()


def test_unfinished_and_failed_selection(
    tmp_path: Path, processor_factory, sample_factory, config_writer
) -> None:
    processor = processor_factory(fail_prefix="fail")
    sample_factory(tmp_path / "input", ("done", "fail-one", "new"))
    config = config_writer(tmp_path, processor, mode="all")
    settings = load_config(config)
    results = run_jobs(settings.run_list, jobs=1) if settings.run_list.exists() else ()
    assert not results
    generate_jobs(settings)
    results = run_jobs(settings.run_list, jobs=3)
    assert sum(result.succeeded for result in results) == 2

    failed = settings.with_runtime_options(mode=SelectionMode.failed)
    generated = generate_jobs(failed)
    assert generated.created == ("fail-one",)

    unfinished = settings.with_runtime_options(mode=SelectionMode.unfinished)
    generated = generate_jobs(unfinished)
    assert generated.created == ("fail-one",)
    assert set(generated.skipped) == {"done", "new"}


def test_force_selects_completed_samples(
    tmp_path: Path, processor_factory, sample_factory, config_writer
) -> None:
    processor = processor_factory()
    sample_factory(tmp_path / "input", ("sample",))
    settings = load_config(config_writer(tmp_path, processor, mode="unfinished"))
    generate_jobs(settings)
    run_jobs(settings.run_list)
    assert not generate_jobs(settings).created
    assert generate_jobs(settings, force=True).created == ("sample",)


def test_missing_inputs_are_reported_and_good_jobs_remain(
    tmp_path: Path, processor_factory, sample_factory, config_writer
) -> None:
    processor = processor_factory()
    sample_factory(tmp_path / "input", ("good",))
    (tmp_path / "input" / "missing").mkdir()
    settings = load_config(config_writer(tmp_path, processor, mode="all"))
    result = generate_jobs(settings)
    assert result.created == ("good",)
    assert result.missing == ("missing",)
    assert len(settings.run_list.read_text().splitlines()) == 1


def test_paired_inputs(tmp_path: Path, processor_factory, sample_factory, config_writer) -> None:
    processor = processor_factory()
    sample_factory(tmp_path / "input", ("pair",), paired=True)
    settings = load_config(
        config_writer(tmp_path, processor, input_mode="paired-fixed", mode="all")
    )
    generate_jobs(settings)
    assert run_jobs(settings.run_list)[0].succeeded
    assert "pair:r1|r2" in (settings.output_dir / "pair" / "result.txt").read_text()


def test_shell_metacharacters_are_preserved(
    tmp_path: Path, processor_factory, sample_factory, config_writer
) -> None:
    processor = processor_factory()
    names = ("sample one", "sample$HOME", 'sample"quote', "sample`tick")
    sample_factory(tmp_path / "input", names)
    settings = load_config(config_writer(tmp_path, processor, mode="all"))
    generate_jobs(settings)
    results = run_jobs(settings.run_list, jobs=4)
    assert all(result.succeeded for result in results)
    assert all((settings.output_dir / name / ".done").is_file() for name in names)


def test_generated_job_lock_rejects_concurrent_run(
    tmp_path: Path, processor_factory, sample_factory, config_writer
) -> None:
    processor = processor_factory(delay=0.5)
    sample_factory(tmp_path / "input", ("sample",))
    settings = load_config(config_writer(tmp_path, processor, mode="all"))
    generate_jobs(settings)
    job = settings.job_dir / "sample.sh"

    first = subprocess.Popen(["bash", str(job)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lock = settings.output_dir / "sample" / ".running"
    for _ in range(100):
        if lock.is_dir():
            break
        time.sleep(0.01)
    second = subprocess.run(["bash", str(job)], capture_output=True, text=True, check=False)
    assert first.wait(timeout=3) == 0
    assert second.returncode == 75
    assert "BUSY" in second.stderr
    assert not lock.exists()


@pytest.mark.skipif(shutil.which("shellcheck") is None, reason="ShellCheck is not installed")
def test_generated_jobs_pass_shellcheck(
    tmp_path: Path, processor_factory, sample_factory, config_writer
) -> None:
    processor = processor_factory()
    sample_factory(tmp_path / "input", ("sample",))
    settings = load_config(config_writer(tmp_path, processor, mode="all"))
    generate_jobs(settings)
    env = os.environ.copy()
    completed = subprocess.run(
        ["shellcheck", "-S", "warning", str(settings.job_dir / "sample.sh")],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
