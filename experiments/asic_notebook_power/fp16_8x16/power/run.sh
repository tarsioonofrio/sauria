#!/usr/bin/env bash
set -euo pipefail
POWER_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source /usr/share/Modules/init/bash
module purge
module use /soft64/modulefiles
module load cadence/genus/211
: "${POWER_CASE:?set POWER_CASE to a completed workload case}"
mkdir -p "$POWER_ROOT/results/$POWER_CASE"
genus -f "$POWER_ROOT/power.tcl" 2>&1 | tee "$POWER_ROOT/results/$POWER_CASE/joules.log"
[[ -s "$POWER_ROOT/results/$POWER_CASE/power_evaluation.txt" ]] || { echo "Joules did not create power report for $POWER_CASE" >&2; exit 3; }
