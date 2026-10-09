#!/usr/bin/env python3
"""Generate the CSV summary for the measured INT16 ASIC campaign."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "experiments/asic_notebook_power/reports/int16_ppa_energy_20261009.json"
DEFAULT_OUTPUT = ROOT / "experiments/asic_notebook_power/reports/int16_ppa_energy_20261009.csv"

FIELDS = [
    "cin",
    "cout",
    "array",
    "x_used",
    "y_used",
    "active_pes",
    "standard_cell_area_um2",
    "layer_cycles",
    "clock_period_ns",
    "estimated_layer_time_us",
    "wns_ps",
    "timing_met_500mhz",
    "power_mw",
    "estimated_energy_uj",
    "sram_power_included",
    "output_checksum",
    "run_id",
    "source_commit",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    manifest = json.loads(args.input.read_text(encoding="utf-8"))
    period_ns = float(manifest["clock_period_ns"])
    workload = manifest.get("workload", {})
    input_shape = workload.get("ifmap", [])
    output_shape = workload.get("ofmap", [])
    cin = input_shape[0] if input_shape else ""
    cout = output_shape[0] if output_shape else ""
    rows = []
    for result in manifest["results"]:
        cycles = int(result["layer_cycles"])
        wns_ps = float(result["wns_ps"])
        power_mw = float(result["power_mw"])
        layer_time_ns = cycles * period_ns
        rows.append(
            {
                "cin": cin,
                "cout": cout,
                "array": result["array"],
                "x_used": result["x_used"],
                "y_used": result["y_used"],
                "active_pes": int(result["x_used"]) * int(result["y_used"]),
                "standard_cell_area_um2": f'{float(result["standard_cell_area_um2"]):.3f}',
                "layer_cycles": cycles,
                "clock_period_ns": f"{period_ns:g}",
                "estimated_layer_time_us": f"{layer_time_ns / 1000:.3f}",
                "wns_ps": f"{wns_ps:.1f}",
                "timing_met_500mhz": str(wns_ps >= 0).lower(),
                "power_mw": f"{power_mw:.5f}",
                "estimated_energy_uj": f"{power_mw * layer_time_ns / 1_000_000:.6f}",
                "sram_power_included": str(bool(manifest["sram_power_included"])).lower(),
                "output_checksum": result["output_checksum"],
                "run_id": result["run_id"],
                "source_commit": result["source_commit"],
            }
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} results to {args.output}")


if __name__ == "__main__":
    main()
