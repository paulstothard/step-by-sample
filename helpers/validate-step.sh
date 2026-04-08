#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  validate-step.sh IN_DIR

Description:
  Validate input directory structure for step-by-sample workflows.
  Checks for common issues before running a pipeline step.

Arguments:
  IN_DIR    Input directory containing sample subdirectories

Checks:
  - Input directory exists and is readable
  - At least one sample subdirectory exists
  - Sample subdirectories are actually directories (not files)
  - Warn about empty sample directories
  - Warn about hidden files/directories that might be ignored
  - Display sample count and directory structure

Examples:
  validate-step.sh shovill_output
  validate-step.sh /path/to/fastq_input
EOF
}

if [[ $# -eq 0 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

IN_DIR="$1"

echo "Validating input directory: $IN_DIR"
echo

# Check if directory exists
if [[ ! -e "$IN_DIR" ]]; then
  echo "❌ ERROR: Input directory does not exist: $IN_DIR"
  exit 1
fi

if [[ ! -d "$IN_DIR" ]]; then
  echo "❌ ERROR: Path exists but is not a directory: $IN_DIR"
  exit 1
fi

if [[ ! -r "$IN_DIR" ]]; then
  echo "❌ ERROR: Input directory is not readable: $IN_DIR"
  exit 1
fi

echo "✓ Input directory exists and is readable"

# Count sample subdirectories
n_dirs=$(find "$IN_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')

if [[ "$n_dirs" -eq 0 ]]; then
  echo "❌ ERROR: No sample subdirectories found in: $IN_DIR"
  echo "   Expected structure: $IN_DIR/sample1/, $IN_DIR/sample2/, etc."
  exit 1
fi

echo "✓ Found $n_dirs sample subdirectories"

# Check for non-directory items at the sample level
n_files=$(find "$IN_DIR" -mindepth 1 -maxdepth 1 ! -type d | wc -l | tr -d ' ')

if [[ "$n_files" -gt 0 ]]; then
  echo "⚠ WARNING: Found $n_files non-directory items in $IN_DIR"
  echo "   These will be ignored during processing:"
  find "$IN_DIR" -mindepth 1 -maxdepth 1 ! -type d | head -n 10
  if [[ "$n_files" -gt 10 ]]; then
    echo "   ... and $((n_files - 10)) more"
  fi
fi

# Check for empty sample directories
empty_count=0
while IFS= read -r sample_dir; do
  n_items=$(find "$sample_dir" -mindepth 1 | wc -l | tr -d ' ')
  if [[ "$n_items" -eq 0 ]]; then
    if [[ "$empty_count" -eq 0 ]]; then
      echo "⚠ WARNING: Found empty sample directories:"
    fi
    echo "   $(basename "$sample_dir")"
    empty_count=$((empty_count + 1))
  fi
done < <(find "$IN_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ "$empty_count" -gt 0 ]]; then
  echo "   Total: $empty_count empty directories"
fi

# Check for hidden directories (often unintentional)
hidden_count=$(find "$IN_DIR" -mindepth 1 -maxdepth 1 -type d -name ".*" | wc -l | tr -d ' ')

if [[ "$hidden_count" -gt 0 ]]; then
  echo "⚠ WARNING: Found $hidden_count hidden sample directories (starting with .)"
  echo "   These will be processed but might be unintentional:"
  find "$IN_DIR" -mindepth 1 -maxdepth 1 -type d -name ".*" | head -n 5
fi

# Display sample list
echo
echo "Sample directories ($n_dirs total):"
find "$IN_DIR" -mindepth 1 -maxdepth 1 -type d | sort | head -n 20 | while read -r d; do
  echo "  - $(basename "$d")"
done

if [[ "$n_dirs" -gt 20 ]]; then
  echo "  ... and $((n_dirs - 20)) more"
fi

echo
echo "✓ Validation complete"
echo "  Ready to process $n_dirs samples from: $IN_DIR"
