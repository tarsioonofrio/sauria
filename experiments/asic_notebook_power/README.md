# SAURIA INT16 ASIC power campaign

This campaign records full-layer INT16 simulation, synthesis, gate simulation,
and power results for the active array profiles:

| Profile | SA dimensions | Arithmetic | Local SRAM depths (A/B/C) |
| --- | --- | --- | --- |
| `int16_NxN` | X=Y=2, 3, 4, 5, or 6 | signed 16-bit operands/partial sums | 2048 / 2048 / 1024 words |

Both target TSMC 28 nm Genus/Xcelium/Joules at 500 MHz (2 ns). The campaign
sequence is full-layer RTL golden simulation, logical synthesis, gate-level
SDF simulation, then Joules activity-based power at TT, 0.90 V, 25 C. Each
campaign stores synthesis outputs below `logical/results/<run_id>/`, so a new
run does not replace reports or netlists from earlier runs.

The deterministic workloads are:

| Profile | Case | Input | Weights | Output |
| --- | --- | --- | --- | --- |
| int16 | profile-specific active X/Y | 3x32x32 | 3x3x3x3 | 3x30x30 |

The INT16 array sweep now follows the FastConv `cmd_sim_normal` tensor
generation contract: seeded `N(0, 1)` IFMAP and weights, scaled by `2^8` and
truncated toward zero to represent eight fractional bits. These are signed
16-bit operands with wraparound, not saturated signed INT8 values. Bias is
disabled and initial partial sums are zero. All five array profiles use the
same seed and layer tensors; only their packed memory layout differs. The
vector manifests record the seed, quantization contract, and SHA-256 hashes.
Expected outputs use an independent direct NumPy convolution and signed 16-bit
accumulator wrap.

## Power boundary and limitations

The experimental top includes SAURIA's native `df_controller_top`, core logic,
feeders, systolic array, partial-sum manager, and local SRAMs. The uDMA and
platform AXI fabric stay outside the synthesis boundary. The testbench services
the controller's native DMA AXI-Lite command sequence and performs the requested
BTT byte copies between one external DRAM image and local SRAMs through the
official `0xD0040000`, `0xD0080000`, and `0xD00C0000` bank map. Each test programs
the controller and core before issuing one layer start; the controller advances
all tiles. The testbench checks that the output DRAM region differs from the
golden before start, then checks every expected output byte after the
controller completes the layer. It records each DMA job, traffic count, and
the activity window from the controller start through `layer_done`, before
testbench golden readback.

The experimental core wrapper buffers AXI-Lite AW and W independently because
the native controller sends them in separate states while the local register
adapter accepts a paired write. It also holds each B response until the
controller consumes it, so a delayed BREADY does not block that write from
reaching the register adapter or lose the start response.

## Timing scope

The experiment measures a convolution layer after its AXI-Lite configuration
registers have been programmed. Therefore, `accelerator_internal` is the
default timing scope for the `int16_2x2` through `int16_6x6` profiles. It
excludes the combinational AW/W valid-to-ready handshake paths, including
cross-channel combinations such as AWVALID → WREADY. This scope measures the
accelerator's internal paths; it does not establish timing closure for the
external AXI-Lite master interface.

Select `SAURIA_TIMING_SCOPE=wrapper` explicitly to include those external
handshake paths in a full-wrapper timing analysis. The Genus console prints
the selected scope, and each campaign records it in `campaign.txt`.

For example, a 100 MHz internal-scope synthesis can be run with:

```bash
SAURIA_CLOCK_PERIOD_NS=10.0 \
LOGICAL_RESULTS_ROOT="$PWD/experiments/asic_notebook_power/int16_2x2/logical/results/<run-id>" \
./experiments/asic_notebook_power/int16_2x2/logical/run.sh
```

To run the full-wrapper scope, set `SAURIA_TIMING_SCOPE=wrapper`. Use a new
immutable run ID for each scope, then verify the selected scope in the Genus
log and inspect which paths contribute to WNS. This setting changes timing
exceptions only; it does not change RTL behavior.

For the 100 MHz `int16_2x2` diagnostic on 2026-10-07, the first run
`int16-2x2-100mhz-internal-aw-excluded-20261007-b129314` excluded only
AWVALID → AWREADY. Genus completed with exit code 0, but the worst path was
still AWVALID → WREADY at −39 ps, so that run is evidence that the single-path
exception was insufficient. The corrected run
`int16-2x2-100mhz-internal-handshake-excluded-20261007-dbb8c7e` excludes the
AW/W valid-to-ready combinations. Genus completed with exit code 0; its
worst reported setup check at the 0.81 V, 125 °C corner had +4664 ps slack and
ran from `i_ctrl_aw_valid` to an internal clock-gating enable in
`df_controller_i`. The other reported corners had +4723 ps (0.90 V, 25 °C)
and +4783 ps (0.99 V, −40 °C). The timing reports are under
`int16_2x2/logical/results/<run_id>/reports/`, and the command logs and exit
codes are under `int16_2x2/run_metadata/<run_id>/`.

The corrected result is an accelerator timing diagnostic under the declared
10 ns clock and generic half-period I/O assumptions. It still times the
configuration input path to internal logic, including the clock-gating check;
it does not characterize or close the external AXI-Lite master interface.

The same corrected scope was synthesized at the 500 MHz target on 2026-10-07
as `int16-2x2-500mhz-internal-handshake-excluded-20261007-a960605`, using
source commit `a960605`. Genus 21.12 completed with exit code 0. The worst
reported setup path was met with +64 ps at 0.81 V, 125 °C, from
`sauria_dma_controller_I/sub_state_reg[0]` to `wdata_reg[30]`; the other
reported corners had +501 ps (0.90 V, 25 °C) and +769 ps (0.99 V, −40 °C).
The mapped design had 19,560 cells and 26,145.882 µm² standard-cell area.
These are synthesis results for this diagnostic constraint scope, not a
full-wrapper timing claim. Reports and logs are under the same
`logical/results/<run_id>/reports/` and `run_metadata/<run_id>/` locations
listed above.

The 3x3, 4x4, 5x5, and 6x6 INT16 profiles were synthesized with the same
500 MHz target, Genus 21.12, and `accelerator_internal` constraint scope on
2026-10-07, using source commit `7a1eaacc`. The table reports the worst setup
slack in each corner and mapped standard-cell area. All four Genus jobs exited
with code 0. `MET` at the slow corner is only a synthesis result under this
diagnostic scope; the 3x3, 5x5, and 6x6 margins are only 1–2 ps and should be
treated as marginal, not robust timing closure. The AW/W handshake paths are
excluded, so none of these results closes the full AXI-Lite wrapper.

| Array | Run ID | Slow corner slack (0.81 V, 125 °C) | Typical slack (0.90 V, 25 °C) | Fast corner slack (0.99 V, −40 °C) | Critical slow-corner path | Standard-cell area (µm²) | Cells | Genus exit |
|---|---|---:|---:|---:|---|---:|---:|---:|
| 3x3 | `int16-3x3-500mhz-internal-handshake-excluded-20261007-7a1eaac` | +1 ps | +381 ps | +500 ps | `psm_shift_fsm_i/main_state_q_reg[1]` → `psm_idxcnt_i/mask_q_reg[2]` | 35,793.702 | 32,019 | 0 |
| 4x4 | `int16-4x4-500mhz-internal-handshake-excluded-20261007-7a1eaac` | +64 ps | +498 ps | +787 ps | `sauria_dma_controller_I/sub_state_reg[0]` → `wdata_reg[30]` | 40,383.504 | 32,566 | 0 |
| 5x5 | `int16-5x5-500mhz-internal-handshake-excluded-20261007-7a1eaac` | +2 ps | +378 ps | +501 ps | `psm_shift_fsm_i/main_state_q_reg[2]` → `psm_idxcnt_i/mask_q_reg[1]` | 56,540.736 | 52,556 | 0 |
| 6x6 | `int16-6x6-500mhz-internal-handshake-excluded-20261007-7a1eaac` | +1 ps | +360 ps | +487 ps | `psm_shift_fsm_i/main_state_q_reg[3]` → `psm_idxcnt_i/mask_q_reg[2]` | 64,613.178 | 56,793 | 0 |

For each row, detailed timing, area, netlist, and SDF files are under
`int16_NxN/logical/results/<run_id>/`; the command log, host, commit, and exit
code are under `int16_NxN/run_metadata/<run_id>/`. The local SRAMs remain
black boxes, so these area values are standard cells only and exclude SRAM
macro area.

`DRAM_BANDWIDTH` is one shared cap for the external memory model. A single DMA
command is serviced at a time, so IFMAP, weights, partial sums, and outputs do
not receive separate external channels. `DRAM_LATENCY` is charged for each
command. The direct SRAM host port has registered reads, which limit the modeled
SRAM-to-DRAM direction further; logs report the resulting service cycles and
bytes. This is a functional model of the excluded DMA/data movement contract,
not the omitted uDMA's physical area or exact internal arbitration.

The local SRAM instances and their interfaces are inside the elaborated
synthesis hierarchy. Since this flow has no characterized compatible SRAM
macros, Genus keeps the storage modules as black boxes (logic abstracts) rather
than mapping the memory arrays to standard cells or SRAM macros. The surrounding
SAURIA logic remains synthesized, but the SRAM storage area is absent from the
reported standard-cell area. Joules likewise reports zero for the black-box
memory category; that zero is excluded memory power, not a measurement of SRAM
consumption. Do not present the reported area or power as including the SRAMs.
Capacity per bank is written to each vector manifest; report logic area and
memory capacity separately.

The integrated boundary and testbench still need an RTL full-layer golden pass
for each selected workload, followed by gate-level SDF golden passes, before a
Joules power result is considered valid. Joules reads both bounds of the gate
simulation's layer window. A lint/elaboration pass alone is not a functional or
power result. The official sequence is one controller start per layer; do not
preload full tensors into local SRAM and start the core directly.

## Run

Run one profile at a time in a task-specific checkout on Paxos through SSH and
`tmux`. Each run gets an immutable run id; keep artifacts under that profile's
`logical/results/<run_id>/`, `sim/run_artifacts/<run_id>/<case>/`,
`power/results/<run_id>/<case>/`, and `run_metadata/<run_id>/`. Use a
task-specific `TMPDIR` under `/sim` for large tool temporaries.

The signed INT16 workload uses the same `Cin=3`, `Cout=12`, `32x32` input,
`3x3` filter, `30x30` output, seed, and 16-bit signed operands/partial sums
for every array. The 2026-10-09 reports capture the earlier tiling
(`C_tile_shape=[3,10,30]`); the profiles are now configured for this mapping:

| Profile | `X_used` | `Y_used` | `C_tile_shape` | Active PEs |
|---|---:|---:|---:|---:|
| 2x2 | 2 | 2 | `[6,10,30]` | 4/4 |
| 3x3 | 3 | 3 | `[3,10,30]` | 9/9 |
| 4x4 | 4 | 3 | `[12,10,30]` | 12/16 |
| 5x5 | 4 | 5 | `[12,10,30]` | 20/25 |
| 6x6 | 6 | 6 | `[12,10,30]` | 36/36 |

`X_used` maps output-channel lanes and `Y_used` maps output-width lanes.
The 2x2 profile uses a 6-channel X tile; 3x3 keeps a 3-channel tile, and the
4x4 through 6x6 profiles use a 12-channel tile, within each profile's C-SRAM
capacity. With output width 30, the 4x4 array cannot use `Y_used=4`; with
`Cout=12`, the 5x5 array cannot use `X_used=5`. The 2026-10-09 reports remain
results for the earlier tiling; the retiled profiles require fresh functional
and ASIC runs before their PPA results are reported. Each flow writes results
into its own `int16_NxN` directory and immutable run-id paths.

For example, the retiled 6x6 signed INT16 case uses `X_used=6`, `Y_used=6`, and
a 2 ns clock:

```bash
SIM_CASES=conv-x6-y6 RUN_ID=<unique-run-id> ./experiments/asic_notebook_power/run_campaign.sh int16_6x6
```

The RTL layer check omits SHM dumping and per-cycle feeder traces by default to
keep large functional runs manageable. Gate-level simulation still records
`dut.shm` for Joules. Set `TRACE_DETAIL=1` when debugging to emit the detailed
SRAM and feeder traces in either simulation stage.

Use the root `Makefile` for `rtl-sim`, `synth`, `gate-sim`, `power`, and full
`flow` targets. `make report` writes the measured INT16 PPA and estimated
per-layer energy table to CSV. The input JSON records each run ID and source
commit. Energy is calculated from the Joules total and layer cycles at the
2 ns target period; it is an estimate under that clock and inherits both the
negative timing slack and SRAM power exclusion described above.

## Result reports

Durable summary reports are stored in [`reports/`](reports/). The current
INT16 PPA and estimated-energy table from the 2026-10-06 campaign is
[`int16_ppa_energy_20261006.csv`](reports/int16_ppa_energy_20261006.csv),
with its source data and run metadata in
[`int16_ppa_energy_20261006.json`](reports/int16_ppa_energy_20261006.json).
The separate synthesis-only report for the 3x3–6x6 internal-scope Genus runs
is [`int16_synthesis_internal_500mhz_20261007.csv`](reports/int16_synthesis_internal_500mhz_20261007.csv),
with source data in
[`int16_synthesis_internal_500mhz_20261007.json`](reports/int16_synthesis_internal_500mhz_20261007.json).
The two reports retain their own run IDs because their source commits and
timing scopes differ. The synthesis report shows local SRAM A/B read widths,
active feeder lanes, and the external shared bandwidth separately. For these
INT16 profiles, each local read returns up to Y IFMAP words from SRAMA and X
weight words from SRAMB; the external AXI configuration is 128 bits per beat
with a shared 128-bit/cycle budget (8 INT16 words/cycle total). `make report`
regenerates both CSVs.
Per-run simulation, synthesis, and power artifacts remain under each profile's
`sim/run_artifacts/`, `logical/results/`, `power/results/`, and
`run_metadata/` directories, as described above. See
[`reports/README.md`](reports/README.md) for the report contents and how to
regenerate the CSV.
