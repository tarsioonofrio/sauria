# SAURIA ASIC campaign reports

This directory contains durable, consolidated reports for the INT16 array
campaign. Reports with different source revisions or measurement scopes stay
separate. Detailed artifacts for individual runs (logs, netlists, waveforms,
and tool reports) are kept under the corresponding profile directories, such
as `int16_4x4/logical/results/<run_id>/`, `int16_4x4/sim/run_artifacts/`,
`int16_4x4/power/results/`, and `int16_4x4/run_metadata/`.

## Current table

- `int16_ppa_energy_20261006.csv` is the RTL/gate-simulation and Joules PPA and
  energy table for arrays 2x2 through 6x6 from the 2026-10-06 campaign.
- `int16_ppa_energy_20261006.json` is the input record used to build that
  table. It retains run IDs, source commits, measured PPA values, and power
  data used by the report generator.
- `int16_synthesis_internal_500mhz_20261007.csv` records the later 3x3 through
  6x6 Genus synthesis results from source commit `7a1eaacc`, including area,
  cell count, and slack at all three corners.
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

The PPA/energy CSV includes standard-cell area, active PE count, layer cycles,
WNS, reported power, and estimated per-layer energy. The energy estimate uses
the 2 ns target clock period and the recorded layer cycle count; it should not
be interpreted as a measured 500 MHz result when WNS is negative. The separate
synthesis CSV contains the later Genus area and three-corner timing results;
its diagnostic `accelerator_internal` scope excludes AXI-Lite AW/W valid-to-
ready paths and is not full-wrapper timing closure. Its 3x3, 5x5, and 6x6 slow
corner margins are only 1–2 ps. Both reports exclude SRAM macro area/power
because local SRAMs are black boxes without characterized macro models. Each
JSON input is the authoritative data record for its CSV; consult the per-run
artifacts for detailed tool output. The synthesis CSV also distinguishes the
per-read local SRAM A (IFMAP) and B (weights) word lanes from active feeder
lanes and from the external 128-bit AXI beat. The local word counts are port
widths if both banks return data on the same cycle, not measured sustained
traffic. The configured external budget is 128 bits/cycle, shared across
IFMAP, weights, and outputs; at 16 bits/word, that is an aggregate budget of
8 words/cycle, not a separate budget per tensor.
