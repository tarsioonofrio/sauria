# SAURIA ASIC campaign reports

This directory contains durable, consolidated reports for the INT16 array
campaign. Reports with different source revisions or measurement scopes stay
separate. Detailed artifacts for individual runs (logs, netlists, waveforms,
and tool reports) are kept under the corresponding active profile directory.
The former square `int16_4x4` and `int16_5x5` profile definitions are archived
under `archive/experiments/asic_notebook_power/`; their existing rows below
remain historical measurements, not results for the new `int16_4x5` array.

## Current table

- `int16_ppa_energy_retile4x5_20261009.csv` and
  `int16_synthesis_internal_500mhz_retile4x5_20261009.csv` record the 2026-10-09
  4x5 campaign. RTL and SDF gate-level simulation passed all 10,800 outputs
  with checksum `015f2e08`; Joules completed. The profile/synthesis source was
  commit `a1431f6`; the rectangular gate SRAM models used for SDF validation
  were corrected in commit `636c69a`. Slow-corner WNS is 0 ps, so timing is a
  marginal pass. The matching JSON files are the source records.

- `int16_ppa_energy_retile6x6_20261009.csv` and
  `int16_synthesis_internal_500mhz_retile6x6_20261009.csv` record the fresh
  2026-10-09 retiled 6x6 run from source commit `0f3f66c`. This snapshot covers
  only that variant (`X_used=6`, `Y_used=6`); its workload is Cin=3/Cout=12.
- The matching JSON files are the source records. The run passed RTL and
  gate-level golden checks with checksum `015f2e08`, completed Joules, and
  reported +1 ps slow-corner WNS. Treat the timing result as marginal. Area and
  power exclude uncharacterized SRAM macros.

- `int16_ppa_energy_retile2x2_4x4_5x5_20261009.csv` and
  `int16_synthesis_internal_500mhz_retile2x2_4x4_5x5_20261009.csv` record the
  retiled 2x2, 4x4, and 5x5 runs from source commit `316013f`. All three passed
  RTL and gate-level golden checks with checksum `015f2e08` and generated Joules
  reports. Their matching JSON files are the source records.

- `int16_ppa_energy_20261009.csv` is the baseline RTL/gate-simulation and Joules
  PPA and energy table for arrays 2x2 through 6x6, from source commit
  `6bdb5b0` and the 2026-10-09 campaign. Its workload is Cin=3, Cout=12.
- `int16_ppa_energy_20261009.json` is the source record for that table. It
  retains tensor shapes and hashes, run IDs, measured area, layer cycles,
  timing slack, Joules power, output checksum, and source commit.
- `int16_synthesis_internal_500mhz_20261009.csv` records baseline Genus results for all
  five arrays from the same campaign, including area, cell count, critical
  paths, and slack at all three corners.
- `int16_synthesis_internal_500mhz_20261009.json` is the source record for
  that table, including the Cin=3/Cout=12 workload and per-run report paths.

| Retiled 6x6 metric | Result |
|---|---:|
| Standard-cell area | 64,613.178 µm² |
| Cell count | 56,793 |
| Active PEs | 36/36 |
| Layer cycles / estimated time | 21,658 / 43.316 µs |
| Slow / typical / fast WNS | +1 / +360 / +487 ps |
| Joules total power | 19.82780 mW |
| Estimated energy per layer | 0.858861 µJ |

| Retiled array | X/Y used | Active PEs | Standard-cell area (µm²) | Cycles | Slow WNS (ps) | Power (mW) | Est. energy (µJ) |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2x2 | 2/2 | 4/4 | 26,145.882 | 100,142 | +64 | 6.20488 | 1.242738 |
| 4x5 | 4/5 | 20/20 | 50,212.134 | 28,066 | 0 | 15.94390 | 0.894963 |
| 4x4 | 4/3 | 12/16 | 40,383.504 | 42,646 | +64 | 11.61220 | 0.990428 |
| 5x5 | 4/5 | 20/25 | 56,540.736 | 35,365 | +2 | 14.86960 | 1.051727 |

The 2x2/4x4/5x5 and 6x6 rows are prior retiled snapshots; the new 4x5 result
uses its own synthesis and PPA source files above. All retiled runs use
`accelerator_internal` scope. The 4x5, 5x5, and 6x6 timing passes are marginal
at the slow corner (0 ps, +2 ps, and +1 ps). Energy is estimated
from Joules power and layer cycles at the 2 ns target period; it is not an
integrated energy measurement. SRAM macro area and power are excluded. The
6x6 report is from source commit `0f3f66c`; the 2x2/4x4/5x5 report is from
`316013f`, so these snapshots retain separate provenance.

- `int16_ppa_energy_20261008.csv` and
  `int16_synthesis_internal_500mhz_20261008.csv` are historical reports from
  source commit `3cdb4b2`. That campaign used Cin=3, Cout=3.
- Their matching JSON files are the source records and retain the run metadata.

- `int16_ppa_energy_20261006.csv` is the RTL/gate-simulation and Joules PPA and
  energy table for arrays 2x2 through 6x6 from the historical 2026-10-06
  campaign.
- `int16_ppa_energy_20261006.json` is the input record used to build that
  table. It retains run IDs, source commits, measured PPA values, and power
  data used by the report generator.
- `int16_synthesis_internal_500mhz_20261007.csv` records the historical 3x3
  through 6x6 Genus synthesis results from source commit `7a1eaacc`, including
  area, cell count, and slack at all three corners.
- `int16_synthesis_internal_500mhz_20261007.json` is the source record for
  that synthesis-only report, including each run ID, critical path, and report
  directory, physical and active X/Y dimensions, and memory-port widths.

Regenerate the CSV from the repository root with:

```bash
make report
```

The target regenerates both CSVs from their JSON records. The default `REPORT`
and `SYNTH_REPORT` paths overwrite the corresponding CSVs. To choose another
path for either output, pass it through the matching variable:

```bash
make report REPORT=experiments/asic_notebook_power/reports/custom-name.csv
make report SYNTH_REPORT=experiments/asic_notebook_power/reports/custom-synthesis.csv
```

Each run-specific PPA/energy CSV includes Cin/Cout, standard-cell area, active PE
count, layer cycles, WNS, reported power, and estimated per-layer energy. The
estimate uses the 2 ns target period and measured layer cycles. The five
Cin=3/Cout=12 baseline array runs passed RTL and gate-level checks with
checksum `015f2e08`; their IFMAP and weight tensor hashes match across all five
arrays. Those baseline runs have nonnegative slow-corner WNS under the
diagnostic `accelerator_internal` scope; the 3x3, 5x5, and 6x6 margins are only
1–2 ps. The new 4x5 run also passes this scope at 0 ps. This scope excludes
AXI-Lite AW/W valid-to-ready paths and does not establish full-wrapper timing
closure. The campaign used `DRAM_BANDWIDTH=128` (128 bits/cycle); it is not the
planned 100/120-bit shared-budget comparison. Both current reports exclude
SRAM macro area/power because local SRAM instances are black boxes without
characterized SRAM macros. The surrounding SAURIA logic is synthesized, but
memory storage area and power are not included. Each JSON input is authoritative
for its CSV; consult per-run artifacts for tool output. The synthesis CSV
distinguishes local SRAM A (IFMAP) and B (weights) read lanes from active feeder
lanes and external AXI width. The local word counts are port widths if both
banks return data on the same cycle, not measured sustained traffic.
