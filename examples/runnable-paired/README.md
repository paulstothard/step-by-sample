# Runnable paired-input example

This example uses tiny paired FASTQ fixtures and requires no bioinformatics
software. `process-pair.sh` counts the reads in each mate file.

From this directory:

```bash
./build-jobs.sh
../../helpers/run-list-local.sh work/run.txt 2
../../helpers/summarize-status.sh work/output --input-dir input-samples
```

Inspect `work/output/beta/pair-summary.txt`, which reports two R1 reads and two
R2 reads. The wrapper demonstrates the paired `STEP_COMMAND` interface:

```text
STEP_COMMAND OUT_DIR R1_FILE R2_FILE SAMPLE_NAME
```

To adapt it for `fastp`, replace `process-pair.sh` with a separately testable
script that accepts the same four arguments and invokes `fastp`. Keeping the
tool command outside the generator makes it possible to test directly before
generating hundreds of jobs.
