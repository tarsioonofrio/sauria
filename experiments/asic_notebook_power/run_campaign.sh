#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE=${1:?usage: run_campaign.sh fp16_8x16|int8_32x32|int16_6x6}
case "$PROFILE" in
    fp16_8x16) CASES=(conv-small conv-large) ;;
    int8_32x32) CASES=(conv gemm) ;;
    int16_6x6) CASES=(conv-x3-y6) ;;
    *) echo "Unknown profile: $PROFILE" >&2; exit 2 ;;
esac
if [[ -n "${SIM_CASES:-}" ]]; then
    read -r -a CASES <<< "$SIM_CASES"
    ((${#CASES[@]} > 0)) || { echo "SIM_CASES must name at least one workload" >&2; exit 2; }
    for case_name in "${CASES[@]}"; do
        case "$PROFILE:$case_name" in
            fp16_8x16:conv-small|fp16_8x16:conv-large|int8_32x32:conv|int8_32x32:gemm|int8_32x32:conv-x3-y3|int16_6x6:conv-x3-y6) ;;
            *) echo "Unknown workload for $PROFILE: $case_name" >&2; exit 2 ;;
        esac
    done
fi
ROOT=$(git rev-parse --show-toplevel)
CONFIG_ROOT="$ROOT/experiments/asic_notebook_power/$PROFILE"
RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$(git -C "$ROOT" rev-parse --short HEAD)}
REPORT_ROOT="$CONFIG_ROOT/run_metadata/$RUN_ID"
LOGICAL_RESULTS_ROOT="$CONFIG_ROOT/logical/results/$RUN_ID"
SIM_RESULTS_ROOT="$CONFIG_ROOT/sim/run_artifacts/$RUN_ID"
POWER_RESULTS_ROOT="$CONFIG_ROOT/power/results/$RUN_ID"
if [[ -e "$REPORT_ROOT" || -e "$LOGICAL_RESULTS_ROOT" || -e "$SIM_RESULTS_ROOT" || -e "$POWER_RESULTS_ROOT" ]]; then
    echo "RUN_ID already has campaign artifacts; choose a fresh RUN_ID: $RUN_ID" >&2
    exit 2
fi
mkdir -p "$REPORT_ROOT"

{
    echo "campaign_start=$(date -Is)"
    echo "run_id=$RUN_ID"
    echo "host=$(hostname -f)"
    echo "profile=$PROFILE"
    echo "git_root=$ROOT"
    echo "git_commit=$(git -C "$ROOT" rev-parse HEAD)"
    echo "git_status=$(git -C "$ROOT" status --short --branch | tr '\n' ';')"
    echo "logical_results=$LOGICAL_RESULTS_ROOT"
    echo "pvt=TSMC28 TT 0.90V 25C for activity-based Joules report"
    echo "clock_target_mhz=500"
    echo "memory_power=excluded (uncharacterized SRAM black boxes)"
    echo "workloads=$(IFS=,; echo "${CASES[*]}")"
} | tee "$REPORT_ROOT/campaign.txt"

LOGICAL_RESULTS_ROOT="$LOGICAL_RESULTS_ROOT" RUN_ID="$RUN_ID" SIM_STAGE=rtl \
    "$CONFIG_ROOT/sim/run.sh" 2>&1 | tee "$REPORT_ROOT/rtl-simulation-console.log"
LOGICAL_RESULTS_ROOT="$LOGICAL_RESULTS_ROOT" "$CONFIG_ROOT/logical/run.sh" 2>&1 | tee "$REPORT_ROOT/logical-console.log"
LOGICAL_RESULTS_ROOT="$LOGICAL_RESULTS_ROOT" RUN_ID="$RUN_ID" SIM_STAGE=gate \
    "$CONFIG_ROOT/sim/run.sh" 2>&1 | tee "$REPORT_ROOT/gate-simulation-console.log"
for case_name in "${CASES[@]}"; do
    LOGICAL_RESULTS_ROOT="$LOGICAL_RESULTS_ROOT" POWER_CASE="$case_name" POWER_RUN_ID="$RUN_ID" \
        "$CONFIG_ROOT/power/run.sh" 2>&1 | tee "$REPORT_ROOT/power-$case_name-console.log"
done
{
    echo "campaign_end=$(date -Is)"
    echo "campaign_commit=$(git -C "$ROOT" rev-parse HEAD)"
    echo "run_id=$RUN_ID"
    echo "logical_exit=0"
    echo "rtl_simulation_exit=0"
    echo "gate_simulation_exit=0"
    echo "power_cases=${CASES[*]}"
} | tee -a "$REPORT_ROOT/campaign.txt"
