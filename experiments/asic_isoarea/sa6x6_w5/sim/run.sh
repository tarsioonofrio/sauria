#!/usr/bin/env bash
set -euo pipefail

SIM_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_ROOT=$(cd -- "$SIM_ROOT/.." && pwd)
GIT_ROOT=$(git -C "$CONFIG_ROOT" rev-parse --show-toplevel)
RESULTS="$CONFIG_ROOT/logical/results"
RUN_ROOT="$SIM_ROOT/run_artifacts"
TB="$SIM_ROOT/tb.sv"
RAM_RTL="$GIT_ROOT/RTL/src/sauria_core/sram/ram_inferred.sv"
GATE_NETLIST="$RESULTS/gate_level/sauria_asic_top_logic_mapped.v"
CELL_MODELS=/pdk/tsmc/PDK28/PDK_TSMC28_bv/tcbn28hpcplusbwp30p140_190a/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp30p140_110a/tcbn28hpcplusbwp30p140.v
TB_ENTRY=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$CONFIG_ROOT/testbench-file.txt")
if [[ -z "$TB_ENTRY" ]]; then
    echo "testbench-file.txt is empty" >&2
    exit 2
fi
if [[ "$TB_ENTRY" = /* ]]; then TB="$TB_ENTRY"; else TB="$GIT_ROOT/$TB_ENTRY"; fi

source /usr/share/Modules/init/bash
module purge
module use /soft64/modulefiles
module load cadence/xcelium/2303

python3 "$SIM_ROOT/generate_vectors.py" --out "$SIM_ROOT/vectors"
mkdir -p "$RUN_ROOT"

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

(
    cd "$SIM_ROOT"
    xrun -f args.txt "${define_args[@]}" -define XRUN \
        "${rtl_files[@]}" "$TB" -run -exit -l "$RUN_ROOT/rtl-xrun.log"
)
if [[ -d "$SIM_ROOT/dut.shm" ]]; then
    mv "$SIM_ROOT/dut.shm" "$RUN_ROOT/rtl.dut.shm"
fi
if [[ -f "$SIM_ROOT/layer_window.txt" ]]; then
    cp "$SIM_ROOT/layer_window.txt" "$RUN_ROOT/rtl-layer-window.txt"
fi

if [[ ! -s "$GATE_NETLIST" ]]; then
    echo "Missing mapped gate netlist: $GATE_NETLIST" >&2
    exit 2
fi
(
    cd "$SIM_ROOT"
    xrun -f args.txt -sdf_cmd_file sdf_cmd.cmd -maxdelays \
        -define XRUN -define POWER_ACTIVITY \
        "$CELL_MODELS" "$RAM_RTL" "$GATE_NETLIST" "$TB" \
        -run -exit -l "$RUN_ROOT/gate-xrun.log"
)
if [[ -d "$SIM_ROOT/dut.shm" ]]; then
    mv "$SIM_ROOT/dut.shm" "$RUN_ROOT/gate.dut.shm"
fi
cp "$SIM_ROOT/layer_window.txt" "$RUN_ROOT/gate-layer-window.txt"
