#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run-list-slurm.sh RUN_LIST [options]

Description:
  Submit a Slurm array job that runs one job script per array task.

Arguments:
  RUN_LIST   Text file containing one job script path per line.

Options:
  --account NAME       Slurm account
  --partition NAME     Slurm partition
  --time HH:MM:SS      Wall time. Default: 04:00:00
  --mem VALUE          Memory per task, e.g. 8G. Default: 8G
  --cpus N             CPUs per task. Default: 4
  --array-max N        Maximum concurrent array tasks. Default: 20
  --log-dir DIR        Directory for Slurm stdout/stderr logs. Default: slurm-logs
  --keep-script PATH   Write the generated array script to PATH instead of a temp file
  -h, --help           Show this help

Examples:
  run-list-slurm.sh run-quast.txt --account myacct --partition cpu
  run-list-slurm.sh run-quast.txt --time 08:00:00 --mem 16G --cpus 8 --array-max 10
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

LIST="$1"
shift

ACCOUNT="${ACCOUNT:-}"
PARTITION="${PARTITION:-}"
TIME="${TIME:-04:00:00}"
MEM="${MEM:-8G}"
CPUS="${CPUS:-4}"
ARRAY_MAX="${ARRAY_MAX:-20}"
LOG_DIR="${LOG_DIR:-slurm-logs}"
KEEP_SCRIPT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account)
      ACCOUNT="${2:?Missing value for --account}"
      shift 2
      ;;
    --partition)
      PARTITION="${2:?Missing value for --partition}"
      shift 2
      ;;
    --time)
      TIME="${2:?Missing value for --time}"
      shift 2
      ;;
    --mem)
      MEM="${2:?Missing value for --mem}"
      shift 2
      ;;
    --cpus)
      CPUS="${2:?Missing value for --cpus}"
      shift 2
      ;;
    --array-max)
      ARRAY_MAX="${2:?Missing value for --array-max}"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="${2:?Missing value for --log-dir}"
      shift 2
      ;;
    --keep-script)
      KEEP_SCRIPT="${2:?Missing value for --keep-script}"
      shift 2
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

if [[ ! -f "$LIST" ]]; then
  echo "Error: run list not found: $LIST" >&2
  exit 1
fi

mapfile -t scripts < <(grep -Ev '^[[:space:]]*($|#)' "$LIST")

if [[ "${#scripts[@]}" -eq 0 ]]; then
  echo "Error: no runnable entries found in: $LIST" >&2
  exit 1
fi

for script in "${scripts[@]}"; do
  if [[ ! -f "$script" ]]; then
    echo "Error: listed script not found: $script" >&2
    exit 1
  fi
done

if ! command -v sbatch >/dev/null 2>&1; then
  echo "Error: sbatch not found in PATH" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

SUBMIT_DIR="$(pwd)"
N="${#scripts[@]}"

if [[ -n "$KEEP_SCRIPT" ]]; then
  SBATCH_SCRIPT="$KEEP_SCRIPT"
else
  tmp_base="${TMPDIR:-/tmp}"
  tmp_base="${tmp_base%/}"
  SBATCH_SCRIPT="$(mktemp "$tmp_base/run-list-slurm.XXXXXX")"
fi

ACCOUNT_LINE=""
PARTITION_LINE=""

if [[ -n "$ACCOUNT" ]]; then
  ACCOUNT_LINE="#SBATCH --account=$ACCOUNT"
fi

if [[ -n "$PARTITION" ]]; then
  PARTITION_LINE="#SBATCH --partition=$PARTITION"
fi

cat >"$SBATCH_SCRIPT" <<EOF
#!/usr/bin/env bash
#SBATCH --time=$TIME
#SBATCH --mem=$MEM
#SBATCH --cpus-per-task=$CPUS
#SBATCH --array=1-$N%$ARRAY_MAX
#SBATCH --output=$LOG_DIR/%A_%a.out
#SBATCH --error=$LOG_DIR/%A_%a.err
$ACCOUNT_LINE
$PARTITION_LINE

set -euo pipefail

cd "$SUBMIT_DIR"

LIST="$LIST"
script=\$(grep -Ev '^[[:space:]]*($|#)' "\$LIST" | sed -n "\${SLURM_ARRAY_TASK_ID}p")

if [[ -z "\$script" ]]; then
  echo "No script found for SLURM_ARRAY_TASK_ID=\$SLURM_ARRAY_TASK_ID" >&2
  exit 1
fi

echo "Task:   \$SLURM_ARRAY_TASK_ID"
echo "Script: \$script"

bash "\$script"
EOF

chmod +x "$SBATCH_SCRIPT"

echo "Run list:     $LIST"
echo "Entries:      $N"
echo "Time:         $TIME"
echo "Memory:       $MEM"
echo "CPUs:         $CPUS"
echo "Array max:    $ARRAY_MAX"
echo "Log dir:      $LOG_DIR"
[[ -n "$ACCOUNT" ]] && echo "Account:      $ACCOUNT"
[[ -n "$PARTITION" ]] && echo "Partition:    $PARTITION"
echo "Array script: $SBATCH_SCRIPT"

submit_out="$(sbatch "$SBATCH_SCRIPT")"
echo "$submit_out"
