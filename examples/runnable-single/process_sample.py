#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: process_sample.py OUT_DIR INPUT_FILE SAMPLE_NAME", file=sys.stderr)
        return 2
    output_dir = Path(sys.argv[1])
    input_file = Path(sys.argv[2])
    sample = sys.argv[3]
    text = input_file.read_text(encoding="utf-8")
    (output_dir / "result.txt").write_text(
        f"sample={sample}\n{text.upper()}",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
