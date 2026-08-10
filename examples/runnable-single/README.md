# Runnable single-input example

This example processes two sample directories without external software. Each
`input.txt` is converted to uppercase by `process-sample.sh`.

From this directory:

```bash
./generate-jobs.sh
../../bin/run-jobs-local.sh work/run.txt 2
../../bin/show-step-status.sh work/output --input-dir input-samples
```

Inspect `work/output/alpha/result.txt`, the per-sample `run.log`, and the
`.done` markers. To see rerun selection, run `./generate-jobs.sh` again: the new
`work/run.txt` will be empty because both samples are complete.

The wrapper demonstrates the `STEP_COMMAND` interface for a single input:

```text
STEP_COMMAND OUT_DIR INPUT_FILE SAMPLE_NAME
```
