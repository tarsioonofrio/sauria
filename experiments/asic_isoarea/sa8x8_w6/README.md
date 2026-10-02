# SAURIA ASIC synthesis input: 8x8, w=6

Derived from the FastConv TSMC 28 nm Genus flow at
`rtl/conv2x2/synthesis/conv-i16-h16-t00-o4-m16-all`.

- Top: `sauria_asic_top` (the experimental wrapper in `common/`).
- Array: X=8, Y=8; signed integer operands and accumulator/output are 20 bits.
- Multiplier and adder are exact (`MUL_TYPE=0`, all approximation values 0).
- Target clock: 500 MHz (2 ns); TSMC28 MMMC/PVT inputs copied from FastConv.
- External data budget metadata: 120 bits/cycle total. The logical synthesis
  top has a 160-bit memory port, matching the 160-bit local SRAM words for this
  square array. The 120-bit/cycle budget applies to the combined
  activation/weight stream and must be enforced by the functional testbench.
- Signed int8 values must be sign-extended to 20 bits before writing the host memory port.
- `multiplier_ideal` treats both operands as signed 20-bit values and produces a 40-bit product.
  The exact adder accumulates into 20 bits; assignment discards high bits, so overflow wraps
  modulo 2^20. No saturation is implemented.
- SRAM depths are selected to hold the largest planned 34x34x64 input,
  3x3x64x64 weight tensor, and 32x32x64 output, packed across Y/X lanes.
- The current SAURIA SRAM implementation uses `ram_inferred`; these synthesis
  inputs do not map it to a TSMC SRAM macro. Report capacity separately from
  standard-cell logic area unless a compatible macro is integrated and validated.

The FastConv flow's synthesis scripts are copied under `logical/` and `scripts/`.
The input list retains SAURIA's native `RTL/filelist.f` order, expands its
PULP/RTL paths, and appends the wrapper. `list-incdir.txt` supplies the
include roots required by the vendored AXI and common-cells RTL.
