#!/usr/bin/env bash
set -euo pipefail

out_dir="$1"
r1="$2"
r2="$3"
sample="$4"

r1_reads=$(awk 'END { print NR / 4 }' "$r1")
r2_reads=$(awk 'END { print NR / 4 }' "$r2")

{
  echo "sample=$sample"
  echo "r1_reads=$r1_reads"
  echo "r2_reads=$r2_reads"
} >"$out_dir/pair-summary.txt"
