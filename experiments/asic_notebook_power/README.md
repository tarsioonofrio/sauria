# SAURIA notebook-target ASIC power campaign

This exploratory campaign maps the **same hardware profiles used by the two
Python notebooks**, separate from `experiments/asic_isoarea` and its signed
20-bit 4x4/6x6/8x8 comparison:

| Profile | SA dimensions | Arithmetic | Local SRAM depths (A/B/C) |
| --- | --- | --- | --- |
| `fp16_8x16` | X=16, Y=8 | SAURIA FP16, 16-bit operands/partial sums | 16384 / 8192 / 16384 words |
| `int8_32x32` | X=32, Y=32 | signed 8-bit operands, signed 32-bit partial sums | 16384 / 16384 / 16384 words |

Both use the TSMC 28 nm Genus/Xcelium/Joules inputs and 500 MHz (2 ns) target
clock. Activity-based power is evaluated at TT, 0.90 V, 25 C. The flows run
logical synthesis, a full-layer RTL simulation checked against a software
golden, a gate-level SDF activity simulation, and Joules.

The four deterministic workloads are:

| Profile | Case | Input | Weights | Output |
| --- | --- | --- | --- | --- |
| FP16 | `conv-small` | 32x10x10 | 32x32x3x3 | 32x8x8 |
| FP16 | `conv-large` | 64x34x34 | 128x64x3x3 | 128x32x32 |
| int8 | `conv` | 64x66x66 | 64x64x3x3 | 64x64x64 |
| int8 | `gemm` | 512x1x256 | 512x512x1x1 | 512x1x256 |

Notebook cells use unseeded random tensors. These flows generate seeded,
reproducible tensors with the same shapes, numeric formats, and tiling for the
same hardware workloads; the vector manifests record the exact seeds and
SHA-256 hashes. FP16 expected outputs use SAURIA's Python execution model. The
int8 expected outputs use an independent int64 NumPy convolution/GEMM followed
by the configured signed 32-bit wrap.

## Power boundary and limitations

The experimental top retains SAURIA's local SRAMs, feeders, controllers,
systolic array, and partial-sum manager. It uses a separate extended host map
for the three banks: the upper two address bits select A/B/C and the lower
address bits span each bank's configured depth. The default SAURIA host map is
unchanged in other flows. This lets the testbench preload and verify a complete
notebook layer, including the int8 output tensor, without aliasing addresses.
The preload and readback stay outside the measured interval. SRAMs are synthesis black boxes because
this flow does not have characterized compatible SRAM macros. Genus/Joules
therefore report standard-cell logic activity only; memory power is zero in the
report and must not be presented as total accelerator power. Capacity per bank
is written to each vector manifest. Report logic area and memory capacity
separately.

The TB loads the complete deterministic layer into the local SRAMs before the
measured `start` window. The window includes compute-side SRAM reads, feeder
stalls, systolic activity, partial-sum updates, drain, and final output commits;
it excludes host preload traffic, external DRAM, CPU, DMA, and AXI. These are
not external-memory full-system power numbers and are not directly comparable
to the 20-bit iso-area campaign without aligning the workload/bandwidth
boundary.

The power number is valid only for a workload whose RTL golden check passes
and whose gate-level simulation reaches `LAYER_CYCLES`. Preserve SDF warnings
with each run; they are recorded in the case's `gate-xrun.log`.

## Run

Run one profile at a time in a clean campaign checkout, on Paxos, through SSH
and tmux:

```bash
bash experiments/asic_notebook_power/run_campaign.sh fp16_8x16
bash experiments/asic_notebook_power/run_campaign.sh int8_32x32
```

The durable artifacts stay under that profile's `logical/results/`,
`sim/run_artifacts/<case>/`, `power/results/<case>/`, and
`run_metadata/` directories. Use a task-specific `TMPDIR` under `/sim` for
large tool temporaries.
