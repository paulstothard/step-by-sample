from __future__ import annotations

import re
from pathlib import Path

import pytest
from typer.testing import CliRunner

from step_by_sample.cli import app
from step_by_sample.config import load_config
from step_by_sample.models import InputMode, StepBySampleError

runner = CliRunner()


def test_main_help_lists_unified_commands() -> None:
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    for command in ("init", "generate", "run", "submit", "status", "reset", "validate"):
        assert command in result.stdout


def test_version() -> None:
    result = runner.invoke(app, ["--version"])
    assert result.exit_code == 0
    assert result.stdout.startswith("step-by-sample ")


def test_init_creates_documented_config(tmp_path: Path) -> None:
    config = tmp_path / "nested" / "step.toml"
    result = runner.invoke(app, ["init", str(config)])
    assert result.exit_code == 0
    assert config.is_file()
    assert "[step]" in config.read_text(encoding="utf-8")
    duplicate = runner.invoke(app, ["init", str(config)])
    assert duplicate.exit_code == 1
    assert "already exists" in duplicate.stdout + duplicate.stderr


def test_config_paths_are_relative_to_config(
    tmp_path: Path, processor_factory, config_writer
) -> None:
    root = tmp_path / "project"
    root.mkdir()
    command = processor_factory()
    config = config_writer(root, command)
    settings = load_config(config)
    assert settings.input_dir == root / "input"
    assert settings.output_dir == root / "output"
    assert settings.input_mode is InputMode.single
    assert settings.command == command.resolve()


@pytest.mark.parametrize(
    ("extra", "message"),
    [
        ("surprise = true\n", "unknown [step] setting"),
        ('strict = "yes"\n', "strict must be true or false"),
        ('input_mode = "mystery"\n', "input_mode must be one of"),
    ],
)
def test_config_rejects_invalid_settings(
    tmp_path: Path, processor_factory, extra: str, message: str
) -> None:
    command = processor_factory()
    config = tmp_path / "bad.toml"
    config.write_text(
        f"""[step]
input_dir = "input"
output_dir = "output"
job_dir = "jobs"
run_list = "run.txt"
command = {str(command)!r}
{extra}""",
        encoding="utf-8",
    )
    with pytest.raises(StepBySampleError, match=re.escape(message)):
        load_config(config)
