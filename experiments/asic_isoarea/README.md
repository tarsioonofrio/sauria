# SAURIA ASIC iso-area preparation

Six Genus input configurations adapt the FastConv TSMC 28 nm flow for SAURIA:
`sa4x4_w5`, `sa4x4_w6`, `sa6x6_w5`, `sa6x6_w6`, `sa8x8_w5`, and `sa8x8_w6`.
Each directory contains `list-file.txt`, `list-define.txt`, `list-incdir.txt`,
`top-module.txt`, `top-parameters.txt`, and project-local copies of the Genus
scripts, MMMC setup, and 500 MHz SDC.

The experimental `common/sauria_asic_top.sv` includes SAURIA's `sauria_logic`
and local SRAMs but excludes the subsystem DMA, CPU, and AXI fabrics. Its memory
host port matches the local SRAM word width (`20*X` bits) for each square array
point. The 100/120-bit-per-cycle total input budgets are traffic constraints
for the shared activation/weight stream; the layer-level functional harness
must enforce them before they can be called verified.

The default RTL memory is inferred from registers. No macro mapping or synthesis
run is included here. Until compatible SRAM macros are selected and validated,
report standard-cell logic area and logical memory capacity separately.

No `testbench-file.txt` is supplied yet: the existing subsystem testbench targets
`sauria_subsystem`, while this synthesis boundary is `sauria_asic_top`. A
wrapper-level complete-layer testbench must be adapted before functional
simulation or bandwidth compliance can be claimed.

## FastConv simulation vectors

`generate_datasets.py` calls the CLI in `fast-convolution-rtl` and stores
reusable layer vectors under `datasets/c{C}/sim/`. It copies the WPN16
configuration from `FastConv_SystemVerilog/rtl/conv4x4/data/wpn16/config`, then
runs the library with `--truncated-weight-transform --nbits 20`. The checked-in
snapshot currently contains channels 1, 4, and 16; channel 64 is supported by
the generator but was not completed because generation exceeded the available
run window. The 34x34 input produces the required 32x32 output for valid 3x3,
stride-1 convolution with no padding. Seed 0 is used for each case. Generate
only the missing larger case with
`python3 experiments/asic_isoarea/generate_datasets.py --channels 64`.

Each generated package carries the same quantized feature and original spatial
weight inputs for both architectures. `d.txt` contains features, `g.txt`
contains the quantized spatial weights, and `s_default_quant.txt` is the
library's direct convolution reference over those Q8-scaled integer inputs.
Here `quant.json`'s `bits: 8` means scale the sampled values by 256 and cast to
integer; it does not clamp them to signed int8, so inputs can exceed ±127.
`s_default_quant.txt` keeps the unwrapped mathematical sum.
`s_sauria20_mac_wrap.txt` is a second direct-convolution golden, recomputed
from `d.txt` and the original weights in `g.txt` and wrapped as a signed
20-bit MAC result. The wrap after the complete sum is equivalent to wrapping
each addition modulo 2^20. `s.txt` and
`const_feat_out` in `pack_data.sv` are the truncated Winograd result for
FastConv. Since `RAW_SPATIAL_WEIGHTS=1`, SAURIA must be loaded from the spatial
weights in `g.txt`; its golden output must not be taken from `s.txt`.
`dataset_manifest.json` records the exact CLI inputs, source revisions, and
SHA-256 hashes. The checked-in vectors are a generated snapshot; regeneration
requires the FastConv Python environment and source trees at the paths declared
in the script.

Example regeneration command:

```bash
python3 experiments/asic_isoarea/generate_datasets.py
```

Data generation alone does not validate SAURIA RTL compatibility. In
particular, the FastConv CLI's truncation flag models its weight-transform
truncation. The 6x6 configuration is present in both the RTL defines and Python
test configuration; its parameter lookup reports X=Y=6 and 20-bit exact
integer arithmetic. Functional simulation did not complete: the existing
Verilator 5.050 test harness rejects the AXI test memory's dynamically indexed
nonblocking write, and the installed ModelSim command exited without
compiling. The SAURIA testbench still needs a layer-level direct-convolution
golden check against RTL. The generated Q8-scaled values are the representation
used by the existing FastConv WPN16 dataset; their range is wider than signed
int8, so the data still needs to be reconciled with the experiment's stated
signed-input range before claiming complete numerical equivalence.
