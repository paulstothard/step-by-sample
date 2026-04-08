#!/usr/bin/env bash
# Quick verification script to check test installation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Verifying test installation..."
echo

# Check test scripts exist
tests=(
  "run-all-tests.sh"
  "test-01-workflow.sh"
  "test-02-helpers.sh"
  "test-03-edge-cases.sh"
  "test-04-reruns.sh"
)

echo "Checking test scripts..."
all_found=1
for test in "${tests[@]}"; do
  if [[ -f "$SCRIPT_DIR/$test" ]]; then
    echo "  ✓ $test"
  else
    echo "  ✗ $test (missing)"
    all_found=0
  fi
done

# Check libraries
echo
echo "Checking test libraries..."
if [[ -f "$SCRIPT_DIR/lib/test-helpers.sh" ]]; then
  echo "  ✓ lib/test-helpers.sh"
else
  echo "  ✗ lib/test-helpers.sh (missing)"
  all_found=0
fi

if [[ -f "$SCRIPT_DIR/lib/mock-commands.sh" ]]; then
  echo "  ✓ lib/mock-commands.sh"
else
  echo "  ✗ lib/mock-commands.sh (missing)"
  all_found=0
fi

# Check mock Slurm
echo
echo "Checking mock Slurm..."
if [[ -f "$SCRIPT_DIR/mock-slurm/sbatch" ]]; then
  echo "  ✓ mock-slurm/sbatch"
else
  echo "  ✗ mock-slurm/sbatch (missing)"
  all_found=0
fi

# Check executability
echo
echo "Checking execute permissions..."
perms_ok=1
for test in "${tests[@]}"; do
  if [[ -x "$SCRIPT_DIR/$test" ]]; then
    continue
  else
    echo "  ✗ $test (not executable)"
    perms_ok=0
  fi
done

if [[ $perms_ok -eq 1 ]]; then
  echo "  ✓ All test scripts are executable"
fi

# Check project files exist
echo
echo "Checking project files..."
if [[ -f "$PROJECT_ROOT/helpers/common.sh" ]]; then
  echo "  ✓ helpers/common.sh"
else
  echo "  ✗ helpers/common.sh (missing)"
  all_found=0
fi

if [[ -f "$PROJECT_ROOT/examples/build-jobs-template.sh" ]]; then
  echo "  ✓ examples/build-jobs-template.sh"
else
  echo "  ✗ examples/build-jobs-template.sh (missing)"
  all_found=0
fi

# Summary
echo
echo "═══════════════════════════════════════"
if [[ $all_found -eq 1 ]] && [[ $perms_ok -eq 1 ]]; then
  echo "✓ Test installation verified!"
  echo
  echo "Run tests with:"
  echo "  cd tests"
  echo "  ./run-all-tests.sh"
  exit 0
else
  echo "✗ Installation incomplete"
  echo
  if [[ $perms_ok -eq 0 ]]; then
    echo "Fix permissions with:"
    echo "  chmod +x tests/*.sh tests/lib/*.sh tests/mock-slurm/*"
    echo
  fi
  exit 1
fi
