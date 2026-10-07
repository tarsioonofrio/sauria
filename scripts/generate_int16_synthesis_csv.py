#!/usr/bin/env python3
"""Generate the CSV for the INT16 internal-scope synthesis report."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "experiments/asic_notebook_power/reports/int16_synthesis_internal_500mhz_20261007.json"
DEFAULT_OUTPUT = ROOT / "experiments/asic_notebook_power/reports/int16_synthesis_internal_500mhz_20261007.csv"

FIELDS = [
    "array",
    "x_used",
    "y_used",
    "active_pes",
    "standard_cell_area_um2",
    "cell_count",
    "target_frequency_mhz",
    "clock_period_ns",
    "timing_scope",
    "slow_corner_wns_ps",
    "typical_corner_wns_ps",
    "fast_corner_wns_ps",
    "slow_corner_critical_startpoint",
    "slow_corner_critical_endpoint",
    "genus_version",
    "genus_exit_code",
    "sram_macro_area_included",
    "run_id",
    "source_commit",
    "report_path",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    manifest = json.loads(args.input.read_text(encoding="utf-8"))
    rows = []
    for result in manifest["results"]:
        rows.append(
            {
                "array": result["array"],
                "x_used": result["x_used"],
                "y_used": result["y_used"],
                "active_pes": int(result["x_used"]) * int(result["y_used"]),
                "standard_cell_area_um2": f'{float(result["standard_cell_area_um2"]):.3f}',
                "cell_count": result["cell_count"],
                "target_frequency_mhz": manifest["target_frequency_mhz"],
                "clock_period_ns": f'{float(manifest["clock_period_ns"]):g}',
                "timing_scope": manifest["timing_scope"],
                "slow_corner_wns_ps": result["slow_corner_wns_ps"],
                "typical_corner_wns_ps": result["typical_corner_wns_ps"],
                "fast_corner_wns_ps": result["fast_corner_wns_ps"],
                "slow_corner_critical_startpoint": result["slow_corner_critical_startpoint"],
                "slow_corner_critical_endpoint": result["slow_corner_critical_endpoint"],
                "genus_version": manifest["genus_version"],
                "genus_exit_code": result["genus_exit_code"],
                "sram_macro_area_included": str(manifest["sram_macro_area_included"]).lower(),
                "run_id": result["run_id"],
                "source_commit": manifest["source_commit"],
                "report_path": result["report_path"],
            }
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} synthesis results to {args.output}")


if __name__ == "__main__":
    main()
