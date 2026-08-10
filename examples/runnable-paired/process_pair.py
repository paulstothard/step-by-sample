#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


def count_fastq_reads(path: Path) -> int:
    line_count = sum(1 for _line in path.open(encoding="utf-8"))
    if line_count % 4:
        raise ValueError(f"FASTQ line count is not divisible by four: {path}")
    return line_count // 4


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: process_pair.py OUT_DIR R1_FILE R2_FILE SAMPLE_NAME", file=sys.stderr)
        return 2
    output_dir = Path(sys.argv[1])
    r1 = Path(sys.argv[2])
    r2 = Path(sys.argv[3])
    sample = sys.argv[4]
    (output_dir / "pair-summary.txt").write_text(
        "\n".join(
            (
                f"sample={sample}",
                f"r1_reads={count_fastq_reads(r1)}",
                f"r2_reads={count_fastq_reads(r2)}",
                "",
            )
        ),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
