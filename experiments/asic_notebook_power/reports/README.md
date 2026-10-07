# SAURIA ASIC campaign reports

This directory contains durable, consolidated reports for the INT16 array
campaign. Detailed artifacts for individual runs (logs, netlists, waveforms,
and tool reports) are kept under the corresponding profile directories, such
as `int16_4x4/logical/results/<run_id>/`, `int16_4x4/sim/run_artifacts/`,
`int16_4x4/power/results/`, and `int16_4x4/run_metadata/`.

## Current table

- `int16_ppa_energy_20261006.csv` is the table for arrays 2x2 through 6x6.
- `int16_ppa_energy_20261006.json` is the input record used to build that
  table. It retains run IDs, source commits, measured PPA values, and power
  data used by the report generator.

Regenerate the CSV from the repository root with:

```bash
make report
```

The default output overwrites the dated CSV above. To choose another CSV path,
pass it through `REPORT`:

```bash
make report REPORT=experiments/asic_notebook_power/reports/custom-name.csv
```

The report includes standard-cell area, active PE count, layer cycles, WNS,
whether the 500 MHz timing target is met, reported power, and estimated
per-layer energy. The energy estimate uses the 2 ns target clock period and
the recorded layer cycle count; it should not be interpreted as a measured
500 MHz result when WNS is negative. SRAM power is excluded because the local
SRAMs are black boxes in this flow and do not have characterized macro power
models. The JSON input is the authoritative data record for the generated
summary; consult the per-run artifacts for detailed tool output.
