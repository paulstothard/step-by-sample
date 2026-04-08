#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  repair-failed.sh OUT_DIR [--clean-outputs]

Description:
  Prepare failed samples for rerun by removing .failed markers.
  Optionally clean partial output files to start fresh.

Arguments:
  OUT_DIR           Output directory containing sample subdirectories

Options:
  --clean-outputs   Also remove all files in failed sample directories
                    (keeps only the directory structure)
  --dry-run         Show what would be done without making changes
  -h, --help        Show this help

Examples:
  repair-failed.sh quast_output
  repair-failed.sh quast_output --clean-outputs
  repair-failed.sh quast_output --dry-run

Notes:
  - Only processes samples with .failed markers
  - Always preserves run.log for inspection
  - With --clean-outputs, removes .done, .failed, and all output files
  - After repair, rebuild your run list with MODE="failed" or MODE="unfinished"
EOF
}

if [[ $# -eq 0 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

OUT_DIR="$1"
shift

CLEAN_OUTPUTS=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean-outputs)
      CLEAN_OUTPUTS=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "$OUT_DIR" ]]; then
  echo "Error: output directory not found: $OUT_DIR" >&2
  exit 1
fi

echo "Scanning for failed samples in: $OUT_DIR"
[[ "$DRY_RUN" -eq 1 ]] && echo "(DRY RUN - no changes will be made)"
[[ "$CLEAN_OUTPUTS" -eq 1 ]] && echo "(Clean outputs mode: will remove output files)"
echo

failed_count=0
repaired_count=0

while IFS= read -r sample_dir; do
  sample="$(basename "$sample_dir")"
  fail_marker="$sample_dir/.failed"
  done_marker="$sample_dir/.done"
  log_file="$sample_dir/run.log"

  if [[ ! -f "$fail_marker" ]]; then
    continue
  fi

  failed_count=$((failed_count + 1))
  echo "Processing: $sample"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  Would remove: .failed marker"
    if [[ -f "$done_marker" ]]; then
      echo "  Would remove: .done marker"
    fi
    if [[ "$CLEAN_OUTPUTS" -eq 1 ]]; then
      echo "  Would clean: all output files (preserving run.log)"
    fi
  else
    # Remove .failed marker
    rm -f "$fail_marker"
    echo "  Removed: .failed marker"

    # Remove .done marker if present (shouldn't be, but just in case)
    if [[ -f "$done_marker" ]]; then
      rm -f "$done_marker"
      echo "  Removed: .done marker"
    fi

    # Clean outputs if requested
    if [[ "$CLEAN_OUTPUTS" -eq 1 ]]; then
      # Preserve run.log temporarily
      temp_log=""
      if [[ -f "$log_file" ]]; then
        temp_log=$(mktemp)
        cp "$log_file" "$temp_log"
      fi

      # Remove all contents
      find "$sample_dir" -mindepth 1 -delete

      # Restore run.log
      if [[ -n "$temp_log" ]]; then
        cp "$temp_log" "$log_file"
        rm -f "$temp_log"
      fi

      echo "  Cleaned: all output files (preserved run.log)"
    fi

    repaired_count=$((repaired_count + 1))
  fi

  echo
done < <(find "$OUT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

echo "Summary:"
echo "  Failed samples found: $failed_count"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  Would repair: $failed_count samples"
  echo
  echo "Run without --dry-run to apply changes"
else
  echo "  Repaired: $repaired_count samples"
  echo
  if [[ "$repaired_count" -gt 0 ]]; then
    echo "Next steps:"
    echo "  1. Rebuild run list with MODE=\"failed\" or MODE=\"unfinished\""
    echo "  2. Execute the new run list"
    echo
    echo "Example:"
    echo "  # Edit your build script to set MODE=\"unfinished\""
    echo "  # Then run it to regenerate job scripts"
  fi
fi
