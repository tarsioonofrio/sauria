# SAURIA ASIC campaign reports

This directory contains durable, consolidated reports for the INT16 array
campaign. Reports with different source revisions or measurement scopes stay
separate. Detailed artifacts for individual runs (logs, netlists, waveforms,
and tool reports) are kept under the corresponding profile directories, such
as `int16_4x4/logical/results/<run_id>/`, `int16_4x4/sim/run_artifacts/`,
`int16_4x4/power/results/`, and `int16_4x4/run_metadata/`.

## Current table

- `int16_ppa_energy_20261008.csv` is the current RTL/gate-simulation and Joules
  PPA and energy table for arrays 2x2 through 6x6, from source commit
  `3cdb4b2` and the 2026-10-08 campaign.
- `int16_ppa_energy_20261008.json` is the source record for that table. It
  retains run IDs, measured standard-cell area, layer cycles, timing slack,
  Joules power, output checksum, and source commit.
- `int16_synthesis_internal_500mhz_20261008.csv` records Genus results for all
  five arrays from the same campaign, including area, cell count, and slack at
  all three corners.
- `int16_synthesis_internal_500mhz_20261008.json` is the source record for
  that synthesis table, including critical paths and per-run report locations.

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

The current PPA/energy CSV includes standard-cell area, active PE count, layer
cycles, WNS, reported power, and estimated per-layer energy. The estimate uses
the 2 ns target period and recorded layer cycles. All five runs passed RTL and
gate-level checks with checksum `2f4ec8c3`; all five have nonnegative slow-
corner WNS under this campaign's diagnostic `accelerator_internal` scope.
The 3x3, 5x5, and 6x6 slow-corner margins are only 1–2 ps. That timing scope
excludes AXI-Lite AW/W valid-to-ready paths and does not establish full-wrapper
timing closure. The campaign used `DRAM_BANDWIDTH=128` (128 bits/cycle); it is
not the planned 100/120-bit shared-budget comparison. Both current reports
exclude SRAM macro area/power because local SRAM instances are black boxes
without characterized SRAM macros. The surrounding SAURIA logic is synthesized,
but memory storage area and power are not included. Each JSON input is the
authoritative record for its CSV; consult the per-run artifacts for detailed
tool output. The synthesis CSV distinguishes per-read local SRAM A (IFMAP) and
B (weights) word lanes from active feeder lanes and the external AXI width.
The local word counts are port widths if both banks return data on the same
cycle, not measured sustained traffic.
