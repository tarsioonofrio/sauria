# SA6x6 w5 power run record

**Status: diagnostic only; do not use as the validated power result.**

The activity-based Genus/Joules flow completed on Paxos for the `sa6x6_w5`
netlist generated from SAURIA commit `5bdf0bc050c7a27c5a187da22fb760d7460b1d8a`.
The subsequent commit `8d6683b` changes only testbench diagnostics; it does not
change the synthesized RTL.

| Item | Result |
| --- | --- |
| Host / checkout | `paxos.inf.pucrs.br`, `/sim/tarsio/sauria` |
| Configuration | 6x6 array, w=5, 100-bit/cycle host port, 20-bit signed integers, C=16, 32x32 output, 3x3 kernel |
| Tools | Genus 21.12-s068_1; Xcelium 23.03-s003 |
| Genus synthesis | Exit 0; 57,747 instances; standard-cell area 65,924.334 (Genus library area units) |
| Setup timing | WNS +358 ps at 0.81 V/125 C; +547 ps at 0.90 V/25 C |
| Gate-level activity run | Exit 0; layer window 49,745 ns to 639,665 ns (294,960 cycles at 2 ns) |
| SDF annotation | 0 errors, 31,744 warnings (`SDFINF`); annotation is incomplete |
| Joules power run | Exit 0; average total 17.9060 mW |

The attached `power_evaluation.txt` reports 9.85694 mW for registers,
6.95101 mW for logic, and 1.09803 mW for clock. SRAM capacity and energy are
not represented by characterized macros in this flow; Joules reports memory
power as zero, so these figures cover standard-cell logic only.

This run is diagnostic because the RTL full-layer check still reports a
mismatch against the direct-convolution golden output. The gate-level run used
`POWER_ACTIVITY`, which intentionally skips that golden check so it could
produce a trace for Joules. The SDF warnings add a second limitation. The
17.9060 mW value is therefore not a validated power result.

The full logs and generated netlist/reports remain in the Paxos checkout under
`experiments/asic_isoarea/sa6x6_w5/{logical/results,sim/run_artifacts,power/}`.
