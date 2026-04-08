#!/usr/bin/env bash
# Common functions for step-by-sample workflows
# Source this file in your templates to use shared validation and utilities

VERSION="1.0.0"

# Validate that a single input file exists
# Usage: validate_sample_input "$file_path" "$sample_name" "$fail_marker_path"
# Returns: 0 if valid, 1 if invalid
validate_sample_input() {
  local f="$1"
  local sample="$2"
  local fail_marker="$3"

  if [[ ! -f "$f" ]]; then
    echo "FAIL  $sample  missing input: $f" >&2
    : >"$fail_marker"
    return 1
  fi
  return 0
}

# Validate that paired-end input files exist
# Usage: validate_paired_input "$r1_path" "$r2_path" "$sample_name" "$fail_marker_path"
# Returns: 0 if valid, 1 if invalid
validate_paired_input() {
  local r1="$1"
  local r2="$2"
  local sample="$3"
  local fail_marker="$4"

  if [[ -z "$r1" ]] || [[ -z "$r2" ]]; then
    echo "FAIL  $sample  paired-end pattern matched no files" >&2
    : >"$fail_marker"
    return 1
  fi

  if [[ ! -f "$r1" ]] || [[ ! -f "$r2" ]]; then
    echo "FAIL  $sample  missing paired input files" >&2
    : >"$fail_marker"
    return 1
  fi

  return 0
}

# Find paired-end read files safely using a pattern
# Usage: mapfile -t reads < <(find_paired_reads "$sample_dir" "*_R1.fastq.gz" "*_R2.fastq.gz")
#        r1="${reads[0]:-}"
#        r2="${reads[1]:-}"
# Returns: outputs r1 path on line 1, r2 path on line 2 if found; returns 1 if not found
find_paired_reads() {
  local sample_dir="$1"
  local pattern1="${2:-*_R1.fastq.gz}"
  local pattern2="${3:-*_R2.fastq.gz}"

  local r1 r2
  r1="$(find "$sample_dir" -maxdepth 1 -type f -name "$pattern1" | head -n 1)"
  r2="$(find "$sample_dir" -maxdepth 1 -type f -name "$pattern2" | head -n 1)"

  if [[ -z "$r1" ]] || [[ -z "$r2" ]]; then
    return 1
  fi

  echo "$r1"
  echo "$r2"
  return 0
}

# Convert relative path to absolute path
# Usage: abs_path="$(to_absolute_path "$relative_path")"
to_absolute_path() {
  local path="$1"

  if [[ "$path" = /* ]]; then
    echo "$path"
  elif [[ -e "$path" ]]; then
    echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  else
    # Path doesn't exist yet, try to resolve directory
    local dir="$(dirname "$path")"
    local base="$(basename "$path")"
    if [[ -d "$dir" ]]; then
      echo "$(cd "$dir" && pwd)/$base"
    else
      # Can't resolve, return as-is
      echo "$path"
    fi
  fi
}

# Validate that JOBS parameter is a positive integer
# Usage: validate_jobs "$JOBS" || exit 1
validate_jobs() {
  local jobs="$1"

  if ! [[ "$jobs" =~ ^[0-9]+$ ]] || [[ "$jobs" -lt 1 ]]; then
    echo "Error: JOBS must be a positive integer, got: $jobs" >&2
    return 1
  fi
  return 0
}

# Validate that input directory exists
# Usage: validate_input_dir "$IN" || exit 1
validate_input_dir() {
  local in_dir="$1"

  if [[ ! -d "$in_dir" ]]; then
    echo "Error: input directory not found: $in_dir" >&2
    return 1
  fi
  return 0
}

# Count samples in input directory
# Usage: n_samples=$(count_samples "$IN")
count_samples() {
  local in_dir="$1"
  find "$in_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
}

# Format elapsed time in seconds to human-readable format
# Usage: format_time $elapsed_seconds
format_time() {
  local seconds="$1"
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))
  local secs=$((seconds % 60))

  if [[ $hours -gt 0 ]]; then
    printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
  elif [[ $minutes -gt 0 ]]; then
    printf "%dm %ds" "$minutes" "$secs"
  else
    printf "%ds" "$secs"
  fi
}
