#!/usr/bin/env bash
set -Eeuo pipefail

SIM_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_ROOT=$(cd -- "$SIM_ROOT/.." && pwd)
GIT_ROOT=$(git -C "$CONFIG_ROOT" rev-parse --show-toplevel)
RESULTS=${LOGICAL_RESULTS_ROOT:-"$CONFIG_ROOT/logical/results"}
RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$(git -C "$GIT_ROOT" rev-parse --short HEAD)}
RUN_ROOT="$SIM_ROOT/run_artifacts/$RUN_ID"
TB_ENTRY=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$CONFIG_ROOT/testbench-file.txt")
TB="$GIT_ROOT/$TB_ENTRY"
RAM_RTL="$GIT_ROOT/RTL/src/sauria_core/sram/ram_inferred.sv"
GATE_NETLIST="$RESULTS/gate_level/sauria_asic_top_logic_mapped.v"
CELL_MODELS=/pdk/tsmc/PDK28/PDK_TSMC28_bv/tcbn28hpcplusbwp30p140_190a/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp30p140_110a/tcbn28hpcplusbwp30p140.v
PYTHON=${SAURIA_PYTHON:-/sim/tarsio/sauria/Python/sauria-env/bin/python}
SIM_STAGE=${SIM_STAGE:-all}
[[ "$SIM_STAGE" == rtl || "$SIM_STAGE" == gate || "$SIM_STAGE" == all ]] || { echo "SIM_STAGE must be rtl, gate, or all" >&2; exit 2; }

source /usr/share/Modules/init/bash
module purge
module use /soft64/modulefiles
module load cadence/xcelium/2303

rtl_files=()
while IFS= read -r source_file; do
    source_file="${source_file#"${source_file%%[![:space:]]*}"}"
    [[ -z "$source_file" || "$source_file" == \#* ]] && continue
    [[ "$source_file" == *ram_inferred_blackbox.sv ]] && continue
    if [[ "$source_file" = /* ]]; then rtl_files+=("$source_file"); else rtl_files+=("$GIT_ROOT/$source_file"); fi
done < "$CONFIG_ROOT/list-file.txt"
rtl_files+=("$RAM_RTL")

define_args=()
while IFS= read -r define; do
    define="${define#"${define%%[![:space:]]*}"}"
    [[ -z "$define" || "$define" == \#* ]] && continue
    if [[ "$define" == "-define "* ]]; then define="${define#-define }"; fi
    define_args+=(-define "$define")
done < "$CONFIG_ROOT/list-define.txt"

include_args=()
while IFS= read -r include_dir; do
    include_dir="${include_dir#"${include_dir%%[![:space:]]*}"}"
    [[ -z "$include_dir" || "$include_dir" == \#* ]] && continue
    [[ "$include_dir" != /* ]] && include_dir="$GIT_ROOT/$include_dir"
    include_args+=(-incdir "$include_dir")
done < "$CONFIG_ROOT/list-incdir.txt"

case_list=()
if [[ -n "${SIM_CASES:-}" ]]; then
    read -r -a case_list <<< "$SIM_CASES"
elif [[ "$CONFIG_ROOT" == */fp16_8x16 ]]; then
    case_list=(conv-small conv-large)
else
    case_list=(conv gemm)
fi
for case_name in "${case_list[@]}"; do
    case "$(basename "$CONFIG_ROOT"):$case_name" in
        fp16_8x16:conv-small|fp16_8x16:conv-large|int8_32x32:conv|int8_32x32:gemm|int8_32x32:conv-x3-y3) ;;
        *) echo "Unsupported SIM_CASES entry for $(basename "$CONFIG_ROOT"): $case_name" >&2; exit 2 ;;
    esac
done
mkdir -p "$RUN_ROOT"
[[ -x "$PYTHON" ]] || { echo "Missing Python environment: $PYTHON" >&2; exit 2; }
if [[ "$SIM_STAGE" != rtl ]]; then
    [[ -s "$GATE_NETLIST" ]] || { echo "Missing synthesized netlist: $GATE_NETLIST" >&2; exit 2; }
fi

for case_name in "${case_list[@]}"; do
    CASE_ROOT="$RUN_ROOT/$case_name"
    VECTOR_ROOT="$CASE_ROOT/vectors"
    mkdir -p "$CASE_ROOT/rtl" "$CASE_ROOT/gate"
    "$PYTHON" "$GIT_ROOT/experiments/asic_notebook_power/common/generate_vectors.py" \
        --profile "$(basename "$CONFIG_ROOT")" --case "$case_name" --out "$VECTOR_ROOT" \
        > "$CASE_ROOT/vector-generation.json"
    # run.env contains only integer word counts generated from the manifest.
    # shellcheck disable=SC1091
    source "$VECTOR_ROOT/run.env"
    PLUSARGS=(
        "+CONTROLLER_CONFIG_WORDS=$CONTROLLER_CONFIG_WORDS"
        "+DRAM_BYTES=$DRAM_BYTES"
        "+OUTPUT_VALUES=$OUTPUT_VALUES"
        "+DRAM_A_OFFSET=$DRAM_A_OFFSET"
        "+DRAM_B_OFFSET=$DRAM_B_OFFSET"
        "+DRAM_C_OFFSET=$DRAM_C_OFFSET"
        "+OUTPUT_BYTES=$OUTPUT_BYTES"
        "+VECTOR_DIR=$VECTOR_ROOT"
        "+MAX_LAYER_CYCLES=20000000"
    )
    if [[ "${TRACE_DETAIL:-0}" == 1 ]]; then PLUSARGS+=("+TRACE_DETAIL"); fi
    if [[ "$SIM_STAGE" != gate ]]; then
        (
            cd "$CASE_ROOT/rtl"
            xrun -f "$SIM_ROOT/args.txt" "${include_args[@]}" "${define_args[@]}" -define XRUN \
                "${rtl_files[@]}" "$TB" -run -exit \
                -l "$CASE_ROOT/rtl-xrun.log" "${PLUSARGS[@]}" \
                "+ARTIFACT_DIR=$CASE_ROOT/rtl"
        )
        [[ -s "$CASE_ROOT/rtl/layer_window.txt" ]] || { echo "$case_name RTL run did not create layer window" >&2; exit 3; }
        cp "$CASE_ROOT/rtl/layer_window.txt" "$CASE_ROOT/rtl-layer-window.txt"
        grep -q 'NOTEBOOK_LAYER_PASS' "$CASE_ROOT/rtl-xrun.log" || { echo "$case_name RTL full-layer golden check missing" >&2; exit 4; }
    fi

    if [[ "$SIM_STAGE" != rtl ]]; then
        GATE_SDF="$RESULTS/gate_level/sauria_asic_top_analysis_view_0p90v_25c_captyp_nominal.sdf"
        [[ -s "$GATE_SDF" ]] || { echo "Missing nominal gate SDF: $GATE_SDF" >&2; exit 5; }
        cat > "$CASE_ROOT/gate-sdf.cmd" <<SDF
SDF_FILE = $GATE_SDF,
LOG_FILE = "$CASE_ROOT/gate/sdf_log.log",
SCOPE = tb.dut;
MTM_CONTROL = "MAXIMUM",
SCALE_FACTORS = "1.0:1.0:1.0",
SCALE_TYPE = "FROM_MAXIMUM";
SDF
        (
            cd "$CASE_ROOT/gate"
            xrun -f "$SIM_ROOT/args.txt" -sdf_cmd_file "$CASE_ROOT/gate-sdf.cmd" -maxdelays \
                "${include_args[@]}" "${define_args[@]}" -define XRUN -define POWER_ACTIVITY \
                "$CELL_MODELS" "$RAM_RTL" "$GATE_NETLIST" "$TB" -run -exit \
                -l "$CASE_ROOT/gate-xrun.log" "${PLUSARGS[@]}" +DUMP_SHM \
                "+ARTIFACT_DIR=$CASE_ROOT/gate"
        )
        [[ -e "$CASE_ROOT/gate/dut.shm" ]] || { echo "$case_name gate run did not create SHM" >&2; exit 5; }
        [[ -s "$CASE_ROOT/gate/layer_window.txt" ]] || { echo "$case_name gate run did not create layer window" >&2; exit 5; }
        cp "$CASE_ROOT/gate/layer_window.txt" "$CASE_ROOT/gate-layer-window.txt"
        grep -q 'NOTEBOOK_LAYER_PASS' "$CASE_ROOT/gate-xrun.log" || { echo "$case_name gate full-layer golden check missing" >&2; exit 6; }
    fi
    echo "SIM_${SIM_STAGE^^}_PASS $case_name" | tee -a "$RUN_ROOT/simulation-status.txt"
done
