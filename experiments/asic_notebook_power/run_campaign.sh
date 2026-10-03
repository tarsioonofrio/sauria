#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE=${1:?usage: run_campaign.sh fp16_8x16|int8_32x32}
case "$PROFILE" in
    fp16_8x16) CASES=(conv-small conv-large) ;;
    int8_32x32) CASES=(conv gemm) ;;
    *) echo "Unknown profile: $PROFILE" >&2; exit 2 ;;
esac
ROOT=$(git rev-parse --show-toplevel)
CONFIG_ROOT="$ROOT/experiments/asic_notebook_power/$PROFILE"
REPORT_ROOT="$CONFIG_ROOT/run_metadata"
mkdir -p "$REPORT_ROOT"

{
    echo "campaign_start=$(date -Is)"
    echo "host=$(hostname -f)"
    echo "profile=$PROFILE"
    echo "git_root=$ROOT"
    echo "git_commit=$(git -C "$ROOT" rev-parse HEAD)"
    echo "git_status=$(git -C "$ROOT" status --short --branch | tr '\n' ';')"
    echo "pvt=TSMC28 TT 0.90V 25C for activity-based Joules report"
    echo "clock_target_mhz=500"
    echo "memory_power=excluded (uncharacterized SRAM black boxes)"
    echo "workloads=$(IFS=,; echo "${CASES[*]}")"
} | tee "$REPORT_ROOT/campaign.txt"

"$CONFIG_ROOT/logical/run.sh" 2>&1 | tee "$REPORT_ROOT/logical-console.log"
"$CONFIG_ROOT/sim/run.sh" 2>&1 | tee "$REPORT_ROOT/simulation-console.log"
for case_name in "${CASES[@]}"; do
    POWER_CASE="$case_name" "$CONFIG_ROOT/power/run.sh" 2>&1 | tee "$REPORT_ROOT/power-$case_name-console.log"
done
{
    echo "campaign_end=$(date -Is)"
    echo "campaign_commit=$(git -C "$ROOT" rev-parse HEAD)"
    echo "logical_exit=0"
    echo "simulation_exit=0"
    echo "power_cases=${CASES[*]}"
} | tee -a "$REPORT_ROOT/campaign.txt"
