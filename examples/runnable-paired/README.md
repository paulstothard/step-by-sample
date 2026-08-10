# Runnable paired-input example

This example uses tiny paired FASTQ fixtures and requires no bioinformatics
software. `process_pair.py` counts the reads in each mate file.

From this directory:

```bash
step-by-sample generate step.toml
step-by-sample run work/run.txt --jobs 2
step-by-sample status work/output --input-dir input-samples
```

Inspect `work/output/beta/pair-summary.txt`, which reports two R1 reads and two
R2 reads. The configuration demonstrates the paired command interface:

```text
COMMAND OUT_DIR R1_FILE R2_FILE SAMPLE_NAME
```

To adapt it for `fastp`, replace `process_pair.py` with a separately testable
script that accepts the same four arguments and invokes `fastp`. Keeping the
tool command outside the generator makes it possible to test directly before
generating hundreds of jobs.
