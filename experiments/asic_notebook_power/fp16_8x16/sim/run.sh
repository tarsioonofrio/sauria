#!/usr/bin/env bash
set -Eeuo pipefail

SIM_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_ROOT=$(cd -- "$SIM_ROOT/.." && pwd)
GIT_ROOT=$(git -C "$CONFIG_ROOT" rev-parse --show-toplevel)
RESULTS="$CONFIG_ROOT/logical/results"
RUN_ROOT="$SIM_ROOT/run_artifacts"
TB_ENTRY=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$CONFIG_ROOT/testbench-file.txt")
TB="$GIT_ROOT/$TB_ENTRY"
RAM_RTL="$GIT_ROOT/RTL/src/sauria_core/sram/ram_inferred.sv"
GATE_NETLIST="$RESULTS/gate_level/sauria_asic_top_logic_mapped.v"
CELL_MODELS=/pdk/tsmc/PDK28/PDK_TSMC28_bv/tcbn28hpcplusbwp30p140_190a/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp30p140_110a/tcbn28hpcplusbwp30p140.v
PYTHON=${SAURIA_PYTHON:-/sim/tarsio/sauria/Python/sauria-env/bin/python}

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
if [[ "$CONFIG_ROOT" == */fp16_8x16 ]]; then
    case_list=(conv-small conv-large)
else
    case_list=(conv gemm)
fi
mkdir -p "$RUN_ROOT"
[[ -x "$PYTHON" ]] || { echo "Missing Python environment: $PYTHON" >&2; exit 2; }
[[ -s "$GATE_NETLIST" ]] || { echo "Missing synthesized netlist: $GATE_NETLIST" >&2; exit 2; }

for case_name in "${case_list[@]}"; do
    CASE_ROOT="$RUN_ROOT/$case_name"
    VECTOR_ROOT="$SIM_ROOT/vectors"
    mkdir -p "$CASE_ROOT"
    "$PYTHON" "$GIT_ROOT/experiments/asic_notebook_power/common/generate_vectors.py" \
        --profile "$(basename "$CONFIG_ROOT")" --case "$case_name" --out "$VECTOR_ROOT" \
        > "$CASE_ROOT/vector-generation.json"
    rm -rf "$CASE_ROOT/vectors"
    cp -a "$VECTOR_ROOT" "$CASE_ROOT/vectors"
    # run.env contains only integer word counts generated from the manifest.
    # shellcheck disable=SC1091
    source "$VECTOR_ROOT/run.env"
    PLUSARGS=(
        "+IFMAP_WORDS=$IFMAP_WORDS"
        "+WEIGHT_WORDS=$WEIGHT_WORDS"
        "+OUTPUT_WORDS=$OUTPUT_WORDS"
        "+OUTPUT_VALUES=$OUTPUT_VALUES"
        "+MAX_LAYER_CYCLES=${MAX_LAYER_CYCLES:-20000000}"
    )
    rm -rf "$SIM_ROOT/dut.shm"
    rm -f "$SIM_ROOT/layer_window.txt" "$SIM_ROOT/output-readback.mem"
    (
        cd "$SIM_ROOT"
        xrun -f args.txt "${include_args[@]}" "${define_args[@]}" -define XRUN \
            "${rtl_files[@]}" "$TB" -run -exit \
            -l "$CASE_ROOT/rtl-xrun.log" "${PLUSARGS[@]}"
    )
    [[ -s "$SIM_ROOT/dut.shm" ]] || { echo "$case_name RTL run did not create SHM" >&2; exit 3; }
    [[ -s "$SIM_ROOT/layer_window.txt" ]] || { echo "$case_name RTL run did not create layer window" >&2; exit 3; }
    mv "$SIM_ROOT/dut.shm" "$CASE_ROOT/rtl.dut.shm"
    cp "$SIM_ROOT/layer_window.txt" "$CASE_ROOT/rtl-layer-window.txt"
    mv "$SIM_ROOT/output-readback.mem" "$CASE_ROOT/output-readback.mem"
    grep -q 'OUTPUTS_CHECKED=' "$CASE_ROOT/rtl-xrun.log" || { echo "$case_name RTL golden check missing" >&2; exit 4; }

    rm -rf "$SIM_ROOT/dut.shm"
    rm -f "$SIM_ROOT/layer_window.txt"
    (
        cd "$SIM_ROOT"
        xrun -f args.txt -sdf_cmd_file sdf_cmd.cmd -maxdelays \
            "${include_args[@]}" "${define_args[@]}" -define XRUN -define POWER_ACTIVITY \
            "$CELL_MODELS" "$RAM_RTL" "$GATE_NETLIST" "$TB" -run -exit \
            -l "$CASE_ROOT/gate-xrun.log" "${PLUSARGS[@]}"
    )
    [[ -s "$SIM_ROOT/dut.shm" ]] || { echo "$case_name gate run did not create SHM" >&2; exit 5; }
    [[ -s "$SIM_ROOT/layer_window.txt" ]] || { echo "$case_name gate run did not create layer window" >&2; exit 5; }
    mv "$SIM_ROOT/dut.shm" "$CASE_ROOT/gate.dut.shm"
    cp "$SIM_ROOT/layer_window.txt" "$CASE_ROOT/gate-layer-window.txt"
    grep -q 'LAYER_CYCLES=' "$CASE_ROOT/gate-xrun.log" || { echo "$case_name gate run did not reach layer completion" >&2; exit 6; }
    echo "SIM_PASS $case_name" | tee -a "$RUN_ROOT/simulation-status.txt"
done
