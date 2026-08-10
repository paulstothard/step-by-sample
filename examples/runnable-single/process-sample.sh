#!/usr/bin/env bash
set -euo pipefail

out_dir="$1"
input_file="$2"
sample="$3"

{
  echo "sample=$sample"
  tr '[:lower:]' '[:upper:]' <"$input_file"
} >"$out_dir/result.txt"
