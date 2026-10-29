# SAURIA as the direct-convolution baseline of FastConv (ISCAS 2027)

This fork of [SAURIA](https://github.com/bsc-loca/sauria) (BSC) provides the direct-convolution baseline of

> T. O. da Silva and F. G. Moraes, "Trading Multiplications for Simpler Transforms: Area and Energy
> Efficiency of Polynomial Winograd Convolution," submitted to the *IEEE International Symposium on Circuits
> and Systems (ISCAS)*, 2027.

SAURIA is an output-stationary systolic-array CNN accelerator with on-the-fly im2col (Fornt et al.,
IEEE TVLSI 2023). The paper compares it with the FastConv fast-convolution cores
([FastConv_SystemVerilog](https://github.com/tarsioonofrio/FastConv_SystemVerilog)) on the same layer
(3×32×32 input, 12 output channels, 3×3 kernel, stride 1, no padding), in the same technology and flow
(TSMC 28 nm, 500 MHz). This fork adds signed 16-bit profiles with 9, 20 and 36 processing elements, an ASIC
wrapper with the native controller and local SRAMs, a testbench that services the controller's DMA requests,
and the synthesis, gate-level simulation and power flow. The three arrays reach 947.5, 895.0 and 858.9 nJ per
layer for 35 794, 50 212 and 64 613 µm² of standard cells.

The README of the original project, with the fork's notes on choosing the active lanes, is in
[`README.upstream.md`](README.upstream.md); how the fork relates to and syncs with upstream is in
[`UPSTREAM.md`](UPSTREAM.md) (in Portuguese).

## Layout

| Folder | Content |
|---|---|
| `experiments/asic_notebook_power/` | the paper experiments: one folder per profile (`int16_3x3/`, `int16_4x5/`, `int16_6x6/`, plus `int16_2x2/`), `common/` (ASIC top, testbench, SRAM models, vector generator), `reports/` (the paper's numbers as JSON/CSV and the SRAM access counts), `run_campaign.sh` |
| `RTL/` | SAURIA RTL; `RTL/hw_versions/int16_*.svh` are square INT16 profiles added here (the ASIC profiles set the array shape and widths in their own `list-define.txt`) |
| `Python/` | upstream Python library and notebooks, with the fork's INT16 examples |
| `test/verilator/` | upstream Verilator testbench, adapted to the new profiles |
| `scripts/` | report generators (`generate_int16_ppa_csv.py`, `generate_int16_synthesis_csv.py`) |
| `archive/` | retired profiles (4×4, 5×5) and their historical reports |
| `tools/`, `pulp_platform/` | upstream Verilator installer and submodules |

## Configurations

All three are the same accelerator with signed 16-bit operands and partial sums, local SRAM depths of
2048/2048/1024 words (A/B/C) and the timing scope `accelerator_internal`; only the array shape changes.

| Paper label | Profile | Array (X×Y) | Case | Report (`experiments/asic_notebook_power/reports/`) | Rerun snapshot |
|---|---|---|---|---|---|
| SAURIA, 9 MACs | `int16_3x3` | 3×3 | `conv-x3-y3` | `int16_ppa_energy_20261009.json` | `6bdb5b0` |
| SAURIA, 20 MACs | `int16_4x5` | 4×5 | `conv-x4-y5` | `int16_ppa_energy_retile4x5_20261009.json` | `636c69a` |
| SAURIA, 36 MACs | `int16_6x6` | 6×6 | `conv-x6-y6` | `int16_ppa_energy_retile6x6_20261009.json` | `0f3f66c` |

The workload is the same for all: inputs and weights drawn from N(0, 1) with seed `20261004` (IFMAP first,
then weights), scaled by 2⁸ and truncated toward zero, with signed 16-bit wrap-around; bias disabled. The
direct-convolution golden has the FNV-1a checksum `015f2e08`.

## Quick start

Without the EDA tools (about a second, Python ≥ 3.8 with NumPy): regenerate the paper's tensors and golden and
check them against the published hashes and checksum.

```bash
python3 experiments/asic_notebook_power/common/generate_vectors.py \
  --profile int16_3x3 --case conv-x3-y3 --out /tmp/sauria-iscas2027 --paper-dataset-only
```

It exits with status 0 and prints `"output_fnv1a32": "015f2e08"` with the SHA-256 of every tensor. Rebuild the
paper's CSVs from the committed JSON reports:

```bash
make report PYTHON=<python ≥ 3.8>      # the two CSVs come out byte-identical
```

The whole flow of one profile, with the Cadence tools and the library (on the Paxos server, inside `tmux`,
with a new `RUN_ID` each time):

```bash
make flow PROFILE=int16_3x3 RUN_ID=<new-id>     # RTL sim, synthesis, gate-level sim, power
make rtl-sim|synth|gate-sim|power PROFILE=int16_6x6 [CASE=conv-x6-y6] RUN_ID=<id>
make help
```

A rerun reproduces the published PPA only from the snapshot of each row (table above); check out that commit
first and restore the branch afterwards.

## Requirements

| Item | Version used | Notes |
|---|---|---|
| Python | ≥ 3.8 | NumPy for the dataset check; `Python/requirements_pip.txt` for the full vector generation |
| Verilator | 5.052 | RTL simulation and SRAM access counts; needs g++ 15 (`gcc-toolset-15`). Upstream recommends 4.224 for its own testbench |
| Cadence Genus | 21.1 | synthesis and power (Joules engine) |
| Cadence Xcelium | 23.03 | gate-level simulation with SDF |
| TSMC 28 nm HPC+ standard cells | | under NDA, not included |
| GNU make, bash, tmux | | the EDA targets check the host (`paxos.inf.pucrs.br`), the checkout path and `tmux` |

## Where each number of the paper comes from

All values are in `experiments/asic_notebook_power/reports/`; the JSON files keep run IDs, checksums, tool
versions and commits. Energy is power × cycles × 2 ns.

| Paper | Value | File |
|---|---|---|
| ASIC table, SAURIA 9 MACs | 44 044 cycles, 35 793.702 µm², 10.7567 mW, 947.5 nJ | `int16_ppa_energy_20261009.json` (and `.csv`) |
| ASIC table, SAURIA 20 MACs | 28 066 cycles, 50 212.134 µm², 15.9439 mW, 895.0 nJ | `int16_ppa_energy_retile4x5_20261009.json` |
| ASIC table, SAURIA 36 MACs | 21 658 cycles, 64 613.178 µm², 19.8278 mW, 858.9 nJ | `int16_ppa_energy_retile6x6_20261009.json` |
| Synthesis details | area, cells, slack per profile | `int16_synthesis_internal_500mhz_20261009.json` (and `.csv`) |
| Memory-energy estimate | accesses per SRAM bank A/B/C | `sram_access_counts_ce13ea3_20261010.csv` (Verilator 5.052, `NOTEBOOK_LAYER_PASS`) |

[`reports/iscas2027/README.md`](experiments/asic_notebook_power/reports/iscas2027/README.md) (in Portuguese)
has the full mapping, the rerun procedure and how the paper's comparison tables are built together with the
FastConv and WinoCNN reports.

## Changes to the SAURIA RTL

The fork keeps the upstream structure and interfaces and puts the flow in `experiments/`. Changes in `RTL/`,
`Python/` and `test/` since the upstream base (`2bb469e`, 2025-11-26):

- **Profiles:** `RTL/hw_versions/int16_{2x2,3x3,4x4,5x5,6x6,7x7,8x8}.svh` (16-bit operands, depths above),
  known to `Python/src/hw_versions.py`; the ASIC profiles (including the non-square 4×5) pass `X`, `Y`, widths
  and depths as defines.
- **Local SRAMs:** non-power-of-two banks, partial and unaligned host transfers and width packing without data
  loss (`sram/ram_intf_wrapper.sv`, `sram/sram_top.sv`).
- **Feeders and partial-sum manager:** IFMAP elements kept across stalls, read pointer bounded by accepted
  elements, pipeline drain after the weights finish (`data_feeder/*`, `psm/psm_idxcnt.sv`,
  `control/feeders_fsm.sv`).
- **Testbench:** Verilator scripts and tester adapted to the INT16 profiles (`test/verilator/`).

Each fix has its own commit (`git log 2bb469e..HEAD -- RTL`).

## Flow, step by step

`run_campaign.sh <profile>` runs the four stages for one case and stores each run under its `RUN_ID`
(`run_metadata/`, `logical/results/`, `sim/run_artifacts/`, `power/results/` inside the profile), so earlier
results are never overwritten.

### 01: vectors (`common/generate_vectors.py`)

Writes the float and quantized tensors, both direct-convolution goldens, statistics and hashes to
`normal_dataset/`, and the packed `.mem` images of the external memory for the selected array. All arrays read
the same tensors; only the memory layout differs.

### 02: RTL simulation (`<profile>/sim/run.sh`, `SIM_STAGE=rtl`)

The ASIC top (`common/sauria_asic_top.sv`: native `df_controller_top`, core, feeders, systolic array,
partial-sum manager, local SRAMs) runs under `common/tb.sv`. The testbench serves the controller's AXI-Lite DMA
commands with byte copies between one external memory image and the local SRAMs, starts one layer, checks that
the output region differs from the golden before the start and equals it after `layer_done`, and records the
activity window from the start to `layer_done`.

### 03: synthesis (`<profile>/logical/run.sh`)

Genus 21.1 at 2 ns with the `accelerator_internal` timing scope (the combinational AXI-Lite handshake paths are
left out; `SAURIA_TIMING_SCOPE=wrapper` includes them). The SRAMs are black boxes (`common/ram_inferred_blackbox.sv`).

### 04: gate-level simulation (`<profile>/sim/run.sh`, `SIM_STAGE=gate`)

Xcelium 23.03 simulates the netlist with SDF and a behavioral SRAM model matched to the mapped netlist
(`common/ram_inferred_gate_model.sv`), with the same golden check.

### 05: power (`<profile>/power/run.sh`)

Genus/Joules at TT, 0.90 V, 25 °C with the activity of the gate-level window; `power_evaluation.txt` per case.

### 06: reports (`make report`)

The JSON campaign reports are condensed into the CSVs used by the paper's table generator.

## Notes

- **Timing.** The slow-corner WNS is close to zero (down to 1 ps); read the notes in each JSON before calling
  it a robust timing closure.
- **The 4×5 point** uses the synthesis of `a1431f6` and the gate-level SRAM model fixed in `636c69a`; its
  snapshot contains both.
- **SRAM access counts** come from separate count-only runs with seed 0; they feed a memory-energy model and
  are not power measurements.
- EDA outputs are not versioned (`.gitignore`); text outputs needed to interpret a run are.

## Limitations

- Area and power exclude the local SRAMs (black boxes without a characterized macro); the uDMA and the AXI
  fabric are outside the synthesis boundary.
- Timing is measured inside the accelerator; it does not close the external AXI-Lite interface.
- SAURIA uses 16-bit operands and accumulators; its precision and boundary differ from the FastConv cores, so
  the paper uses it as a reference point, not as an equivalent measurement.
- Power is at the typical corner with one workload.

## License

SAURIA is released under the [Solderpad Hardware License v2.1](https://solderpad.org/licenses/SHL-2.1/)
(`LICENSE`); the fork does not change it. Submodules keep their own licenses. The
standard-cell library is not distributed. Cite SAURIA as Fornt et al., "An Energy-Efficient GeMM-Based
Convolution Accelerator With On-the-Fly im2col," IEEE TVLSI 31(11), 2023 (BibTeX in `README.upstream.md`).
