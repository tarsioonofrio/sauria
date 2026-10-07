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

The campaign generates seeded reproducible inputs, weights, and bias with the
same layer shape and numeric format for each array. The vector manifests record
the seeds and SHA-256 hashes. Expected outputs use the independent NumPy
convolution and signed 16-bit wrap used by the experiment.

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

## Timing scope for the AXI-Lite configuration handshake

The default synthesis constraints measure the complete wrapper. They apply
half-period input and output delays to the ports, including the AXI-Lite host
configuration interface. This can make the combinational path from
`i_ctrl_aw_valid` to `o_ctrl_aw_ready` the reported critical path. The external
master and its timing contract are outside this experimental wrapper, so that
path cannot be interpreted as a measured SoC interface result.

For an accelerator-internal timing diagnostic, the `int16_2x2` constraints
accept `SAURIA_TIMING_SCOPE=accelerator_internal`. That view excludes the
combinational AXI-Lite AW/W valid-to-ready paths, because
software/configuration writes finish before the layer starts. This includes
cross-channel paths: the first diagnostic removed AWVALID → AWREADY, but then
Genus reported AWVALID → WREADY at −39 ps. That confirms the whole external
AW/W handshake boundary needs to be excluded for this internal diagnostic.
The default `wrapper` scope remains unchanged and continues to time those
paths under the generic half-period external delays. The internal view is
useful for examining the accelerator's remaining paths; its WNS must be
labeled as an internal diagnostic and must not be reported as timing closure
of the full wrapper or AXI-Lite interface.

For example, a 100 MHz diagnostic synthesis can be run with:

```bash
SAURIA_CLOCK_PERIOD_NS=10.0 \
SAURIA_TIMING_SCOPE=accelerator_internal \
LOGICAL_RESULTS_ROOT="$PWD/experiments/asic_notebook_power/int16_2x2/logical/results/<run-id>" \
./experiments/asic_notebook_power/int16_2x2/logical/run.sh
```

Use a new immutable run ID and keep the original wrapper-scope reports. Check
the Genus log for the selected scope, then inspect the timing report to verify
the AW/W valid-to-ready paths are absent and identify the new critical path.
No RTL behavior changes; the exception changes only which paths contribute
to this diagnostic timing summary.

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

`DRAM_BANDWIDTH` is one shared cap for the external memory model. A single DMA
command is serviced at a time, so IFMAP, weights, partial sums, and outputs do
not receive separate external channels. `DRAM_LATENCY` is charged for each
command. The direct SRAM host port has registered reads, which limit the modeled
SRAM-to-DRAM direction further; logs report the resulting service cycles and
bytes. This is a functional model of the excluded DMA/data movement contract,
not the omitted uDMA's physical area or exact internal arbitration.

The local SRAMs are synthesis black boxes because this flow does not have
characterized compatible SRAM macros. Genus area therefore reports the mapped
standard cells and Joules reports zero for the black-box memory category; that
zero is excluded memory power, not a measurement of SRAM consumption. Do not
present it as total accelerator power. Capacity per bank is written to each
vector manifest; report logic area and memory capacity separately.

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

The signed INT16 array sweep uses the same 3x32x32 layer, filter, output shape,
seed, and 16-bit signed operands/partial sums for every array. To satisfy the
workload tiling constraints, `X_used` is the largest divisor of the three
output channels no larger than the physical X size, and `Y_used` is the largest
divisor of the output width (30) no larger than the physical Y size. Thus 2x2
uses 1x2, 3x3 uses 3x3, 4x4 uses 3x3, 5x5 uses 3x5, and 6x6 uses 3x6 active
PEs. Each flow writes results into its own `int16_NxN` directory and immutable
run-id paths.

For example, the 6x6 signed INT16 case uses `X_used=3`, `Y_used=6`, and a 2 ns
clock:

```bash
SIM_CASES=conv-x3-y6 RUN_ID=<unique-run-id> ./experiments/asic_notebook_power/run_campaign.sh int16_6x6
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
INT16 PPA and estimated-energy table is
[`int16_ppa_energy_20261006.csv`](reports/int16_ppa_energy_20261006.csv),
with its source data and run metadata in
[`int16_ppa_energy_20261006.json`](reports/int16_ppa_energy_20261006.json).
Per-run simulation, synthesis, and power artifacts remain under each profile's
`sim/run_artifacts/`, `logical/results/`, `power/results/`, and
`run_metadata/` directories, as described above. See
[`reports/README.md`](reports/README.md) for the report contents and how to
regenerate the CSV.
