# Runnable single-input example

This example processes two sample directories without external software. Each
`input.txt` is converted to uppercase by `process_sample.py`.

From this directory:

```bash
step-by-sample generate step.toml
step-by-sample run work/run.txt --jobs 2
step-by-sample status work/output --input-dir input-samples
```

Inspect `work/output/alpha/result.txt`, the per-sample `run.log`, and the
`.done` markers. To see rerun selection, run the `generate` command again: the
new `work/run.txt` will be empty because both samples are complete.

The configuration demonstrates the command interface for a single input:

```text
COMMAND OUT_DIR INPUT_FILE SAMPLE_NAME
```
