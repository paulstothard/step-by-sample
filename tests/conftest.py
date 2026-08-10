from __future__ import annotations

import stat
from collections.abc import Callable
from pathlib import Path

import pytest


def make_executable(path: Path, text: str) -> Path:
    path.write_text(text, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return path


@pytest.fixture
def processor_factory(tmp_path: Path) -> Callable[..., Path]:
    def create(*, fail_prefix: str = "", delay: float = 0) -> Path:
        return make_executable(
            tmp_path / f"processor-{len(list(tmp_path.glob('processor-*')))}.py",
            f"""#!/usr/bin/env python3
import pathlib
import sys
import time

out_dir = pathlib.Path(sys.argv[1])
inputs = sys.argv[2:-1]
sample = sys.argv[-1]
time.sleep({delay!r})
if {fail_prefix!r} and sample.startswith({fail_prefix!r}):
    print(f\"intentional failure: {{sample}}\", file=sys.stderr)
    raise SystemExit(9)
text = \"|\".join(pathlib.Path(item).read_text(encoding=\"utf-8\").strip() for item in inputs)
(out_dir / \"result.txt\").write_text(f\"{{sample}}:{{text}}\\n\", encoding=\"utf-8\")
""",
        )

    return create


@pytest.fixture
def sample_factory() -> Callable[..., Path]:
    def create(
        root: Path,
        names: tuple[str, ...],
        *,
        input_name: str = "input.dat",
        paired: bool = False,
    ) -> Path:
        root.mkdir(parents=True, exist_ok=True)
        for name in names:
            sample = root / name
            sample.mkdir()
            if paired:
                (sample / "R1.fastq").write_text("r1\n", encoding="utf-8")
                (sample / "R2.fastq").write_text("r2\n", encoding="utf-8")
            else:
                (sample / input_name).write_text(f"data for {name}\n", encoding="utf-8")
        return root

    return create


@pytest.fixture
def config_writer() -> Callable[..., Path]:
    def write(
        root: Path,
        command: Path,
        *,
        input_mode: str = "single",
        input_name: str = "input.dat",
        mode: str = "unfinished",
        strict: bool = True,
    ) -> Path:
        config = root / "step.toml"
        config.write_text(
            f"""[step]
input_dir = "input"
output_dir = "output"
job_dir = "jobs"
run_list = "run.txt"
command = {str(command)!r}
input_mode = {input_mode!r}
input_name = {input_name!r}
r1_name = "R1.fastq"
r2_name = "R2.fastq"
mode = {mode!r}
strict = {str(strict).lower()}
""",
            encoding="utf-8",
        )
        return config

    return write
