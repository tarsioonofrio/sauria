#!/usr/bin/env python3
"""Generate the CSV for the INT16 internal-scope synthesis report."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "experiments/asic_notebook_power/reports/int16_synthesis_internal_500mhz_20261009.json"
DEFAULT_OUTPUT = ROOT / "experiments/asic_notebook_power/reports/int16_synthesis_internal_500mhz_20261009.csv"

FIELDS = [
    "cin",
    "cout",
    "array",
    "x_physical",
    "y_physical",
    "x_used",
    "y_used",
    "active_pes",
    "ifmap_words_per_local_sram_read",
    "weight_words_per_local_sram_read",
    "local_operand_words_if_srama_sramb_read_together",
    "active_ifmap_word_lanes",
    "active_weight_word_lanes",
    "active_operand_word_lanes",
    "standard_cell_area_um2",
    "cell_count",
    "target_frequency_mhz",
    "clock_period_ns",
    "timing_scope",
    "external_axi_data_width_bits",
    "external_words_per_axi_beat",
    "external_shared_bandwidth_bits_per_cycle",
    "external_shared_word_budget_per_cycle",
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
    operand_bits = int(manifest["operand_bits"])
    external = manifest["external_interface"]
    workload = manifest.get("workload", {})
    input_shape = workload.get("ifmap", [])
    output_shape = workload.get("ofmap", [])
    cin = input_shape[0] if input_shape else ""
    cout = output_shape[0] if output_shape else ""
    rows = []
    for result in manifest["results"]:
        x_physical = int(result["x_physical"])
        y_physical = int(result["y_physical"])
        x_used = int(result["x_used"])
        y_used = int(result["y_used"])
        rows.append(
            {
                "cin": cin,
                "cout": cout,
                "array": result["array"],
                "x_physical": x_physical,
                "y_physical": y_physical,
                "x_used": x_used,
                "y_used": y_used,
                "active_pes": x_used * y_used,
                "ifmap_words_per_local_sram_read": y_physical,
                "weight_words_per_local_sram_read": x_physical,
                "local_operand_words_if_srama_sramb_read_together": x_physical + y_physical,
                "active_ifmap_word_lanes": y_used,
                "active_weight_word_lanes": x_used,
                "active_operand_word_lanes": x_used + y_used,
                "standard_cell_area_um2": f'{float(result["standard_cell_area_um2"]):.3f}',
                "cell_count": result["cell_count"],
                "target_frequency_mhz": manifest["target_frequency_mhz"],
                "clock_period_ns": f'{float(manifest["clock_period_ns"]):g}',
                "timing_scope": manifest["timing_scope"],
                "external_axi_data_width_bits": external["axi_data_width_bits"],
                "external_words_per_axi_beat": int(external["axi_data_width_bits"]) // operand_bits,
                "external_shared_bandwidth_bits_per_cycle": external["shared_bandwidth_bits_per_cycle"],
                "external_shared_word_budget_per_cycle": int(external["shared_bandwidth_bits_per_cycle"]) // operand_bits,
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
