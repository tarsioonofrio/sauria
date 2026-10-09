# SAURIA ASIC campaign reports

This directory contains durable, consolidated reports for the INT16 array
campaign. Reports with different source revisions or measurement scopes stay
separate. Detailed artifacts for individual runs (logs, netlists, waveforms,
and tool reports) are kept under the corresponding profile directories, such
as `int16_4x4/logical/results/<run_id>/`, `int16_4x4/sim/run_artifacts/`,
`int16_4x4/power/results/`, and `int16_4x4/run_metadata/`.

## Current table

- `int16_ppa_energy_retile6x6_20261009.csv` and
  `int16_synthesis_internal_500mhz_retile6x6_20261009.csv` record the fresh
  2026-10-09 retiled 6x6 run from source commit `0f3f66c`. This snapshot covers
  only that variant (`X_used=6`, `Y_used=6`); its workload is Cin=3/Cout=12.
- The matching JSON files are the source records. The run passed RTL and
  gate-level golden checks with checksum `015f2e08`, completed Joules, and
  reported +1 ps slow-corner WNS. Treat the timing result as marginal. Area and
  power exclude uncharacterized SRAM macros.

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

The 6x6 timing pass is marginal at the slow corner and uses
`accelerator_internal` scope. The energy value is estimated from Joules power
and layer cycles at the 2 ns target period; it is not an integrated energy
measurement. SRAM macro area and power are excluded.

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

The current PPA/energy CSV includes Cin/Cout, standard-cell area, active PE
count, layer cycles, WNS, reported power, and estimated per-layer energy. The
estimate uses the 2 ns target period and measured layer cycles. All five
Cin=3/Cout=12 runs passed RTL and gate-level checks with checksum `015f2e08`.
Their IFMAP and weight tensor hashes match across all five arrays. All five
have nonnegative slow-corner WNS under the diagnostic `accelerator_internal`
scope; the 3x3, 5x5, and 6x6 margins are only 1–2 ps. This scope excludes
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
