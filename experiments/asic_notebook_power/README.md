# SAURIA notebook-target ASIC power campaign

This exploratory campaign maps the **same hardware profiles used by the two
Python notebooks**, separate from `experiments/asic_isoarea` and its signed
20-bit 4x4/6x6/8x8 comparison:

| Profile | SA dimensions | Arithmetic | Local SRAM depths (A/B/C) |
| --- | --- | --- | --- |
| `fp16_8x16` | X=16, Y=8 | SAURIA FP16, 16-bit operands/partial sums | 2048 / 1024 / 2048 words |
| `int8_32x32` | X=32, Y=32 | signed 8-bit operands, signed 32-bit partial sums | 2048 / 2048 / 1024 words |

Both target TSMC 28 nm Genus/Xcelium/Joules at 500 MHz (2 ns). The intended
sequence is logical synthesis, full-layer RTL golden simulation, gate-level
SDF simulation, then Joules activity-based power at TT, 0.90 V, 25 C. The
current direct-core wrapper does not yet implement the full-layer sequence.

The four deterministic workloads are:

| Profile | Case | Input | Weights | Output |
| --- | --- | --- | --- | --- |
| FP16 | `conv-small` | 32x10x10 | 32x32x3x3 | 32x8x8 |
| FP16 | `conv-large` | 64x34x34 | 128x64x3x3 | 128x32x32 |
| int8 | `conv` | 64x66x66 | 64x64x3x3 | 64x64x64 |
| int8 | `gemm` | 512x1x256 | 512x512x1x1 | 512x1x256 |

Notebook cells use unseeded random tensors. These flows generate seeded,
reproducible tensors with the same shapes, numeric formats, and tile shapes for
the same hardware workloads; the vector manifests record the exact seeds and
SHA-256 hashes. The SRAM depths and tile shapes match the notebook hardware
configuration instead of enlarging the memories to hold whole layers. FP16
expected outputs use SAURIA's Python execution model. The int8 expected outputs
use an independent int64 NumPy convolution/GEMM followed by the configured
signed 32-bit wrap.

## Power boundary and limitations

The current experimental top retains SAURIA's local SRAMs, feeders,
systolic array, and partial-sum manager. It does not yet include the notebook's
`df_controller_top` tile scheduler or model the DMA's tile transfers. The direct
preload testbench therefore cannot be used as a full-layer System+Convolution
result; use it only as a diagnostic until that boundary is implemented. The
current testbench's direct SRAM preload does not model tile reloads, DMA
completion, or the shared external bandwidth. Its `DRAM_BANDWIDTH` setting is
therefore not evidence that the accelerator is throttled at that interface.

The local SRAMs are synthesis black boxes because this flow does not have
characterized compatible SRAM macros. A future Genus/Joules result will cover
standard-cell logic only; memory power must not be reported as zero or
presented as total accelerator power. Capacity per bank is written to each
vector manifest. Report logic area and memory capacity separately.

**This campaign is not ready for full-layer ASIC power runs.** The existing
`run_campaign.sh` is retained as a scaffold, but must not be used to claim
System+Convolution area, timing, or power until the tile scheduler and a
bandwidth-limited DMA transaction model are integrated, and both notebooks'
golden checks pass at RTL and gate level. For the official notebook sequence,
program the controller/core, issue one layer start, and let
`df_controller_top` advance all tiles. Do not preload the complete tensors into
the local SRAMs and start the core directly.

## Run

When the controller and DMA model are integrated, run one profile at a time in
a clean campaign checkout on Paxos through SSH and `tmux`. Keep durable
artifacts under that profile's `logical/results/`,
`sim/run_artifacts/<case>/`, `power/results/<case>/`, and `run_metadata/`, and
use a task-specific `TMPDIR` under `/sim` for large tool temporaries.
