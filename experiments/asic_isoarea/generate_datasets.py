#!/usr/bin/env python3
"""Generate shared FastConv inputs and references for the SAURIA study.

The CLI runs from the FastConv Python library, while all generated files and
copied configuration inputs stay inside this SAURIA checkout.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


DEFAULT_FAST_CONV_ROOT = Path("/home/tarsio/gaph/fast-convolution-rtl")
DEFAULT_FAST_CONV_RTL_ROOT = Path("/home/tarsio/gaph/FastConv_SystemVerilog")
CONFIG_FILES = ("init.json", "build.json", "gen.json", "bind.json", "quant.json")
CHANNEL_CASES = (1, 4, 16, 64)
IMAGE_SIDE = 34  # valid 3x3, stride 1, no padding -> 32x32 outputs
NBITS = 20
SEED = 0
SUFFIX = "out32-k3-s1-p0-trunc-n20-q8-seed0"
EXPECTED_CLI_FILES = ("pack_data.sv", "d.txt", "g.txt", "s.txt", "s_default_quant.txt", "sim.txt")
SAURIA_GOLDEN = "s_sauria20_mac_wrap.txt"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_value(repo: Path, *args: str) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "-C", str(repo), *args], text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sauria-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--fast-conv-root", type=Path, default=DEFAULT_FAST_CONV_ROOT)
    parser.add_argument("--fast-conv-rtl-root", type=Path, default=DEFAULT_FAST_CONV_RTL_ROOT)
    parser.add_argument("--python", type=Path, default=None, help="Python environment containing library dependencies.")
    parser.add_argument("--channels", type=int, nargs="+", default=list(CHANNEL_CASES), choices=CHANNEL_CASES)
    parser.add_argument("--timeout-sec", type=int, default=600, help="Per-case CLI timeout.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sauria_root = args.sauria_root.resolve()
    library_root = args.fast_conv_root.resolve()
    rtl_root = args.fast_conv_rtl_root.resolve()
    config_source = rtl_root / "rtl/conv4x4/data/wpn16/config"
    output_root = sauria_root / "experiments/asic_isoarea/datasets"
    # Keep virtual-environment symlinks intact: resolving .venv/bin/python
    # bypasses the venv and launches the base interpreter without dependencies.
    python = args.python or (library_root / ".venv/bin/python")
    cli_module = library_root / "src/fast_convolution/cli.py"

    required = [config_source / name for name in CONFIG_FILES]
    if not cli_module.is_file() or any(not path.is_file() for path in required):
        raise SystemExit("FastConv CLI or WPN16 configuration files are missing")
    if not python.is_file():
        raise SystemExit(f"Python interpreter not found: {python}")

    library_commit = git_value(library_root, "rev-parse", "HEAD")
    rtl_commit = git_value(rtl_root, "rev-parse", "HEAD")
    sim_source_hash = sha256(library_root / "src/fast_convolution/simulation.py")
    cli_source_hash = sha256(cli_module)
    config_hashes = {name: sha256(config_source / name) for name in CONFIG_FILES}
    result_rows = []

    for channels in args.channels:
        case_root = output_root / f"c{channels}"
        config_target = case_root / "config"
        sim_target = case_root / "sim" / f"sim-{SUFFIX}"
        already_generated = all((sim_target / name).is_file() for name in EXPECTED_CLI_FILES)
        if sim_target.exists() and not already_generated:
            partial_contents = [
                path.name for path in sim_target.iterdir()
                if path.name != "generator.log"
            ]
            if partial_contents:
                raise SystemExit(f"Refusing to overwrite generated data: {sim_target}")
            else:
                (sim_target / "generator.log").unlink(missing_ok=True)
        config_target.mkdir(parents=True, exist_ok=True)
        for name in CONFIG_FILES:
            target = config_target / name
            source = config_source / name
            if target.exists() and sha256(target) != config_hashes[name]:
                raise SystemExit(f"Existing config differs from FastConv WPN16: {target}")
            if not target.exists():
                shutil.copy2(source, target)

        command = [
            str(python), "-m", "fast_convolution.cli", "-p", str(case_root),
            "sim", "normal", "--image-side", str(IMAGE_SIDE),
            "-i", str(channels), "-o", str(channels), "-d", str(SEED),
            "-n", SUFFIX, "--truncated-weight-transform", "--nbits", str(NBITS),
            "--no-c",
        ]
        environment = os.environ.copy()
        environment["PYTHONPATH"] = str(library_root / "src") + os.pathsep + environment.get("PYTHONPATH", "")
        # PyTorch's default host-wide thread pool is much slower for the
        # small per-layer CPU workload used here.
        environment.setdefault("OMP_NUM_THREADS", "1")
        environment.setdefault("MKL_NUM_THREADS", "1")
        environment.setdefault("OPENBLAS_NUM_THREADS", "1")
        if not already_generated:
            try:
                completed = subprocess.run(
                    command,
                    cwd=sauria_root,
                    env=environment,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=args.timeout_sec,
                )
            except subprocess.TimeoutExpired as error:
                sim_target.mkdir(parents=True, exist_ok=True)
                (sim_target / "generator.log").write_text(error.stdout or f"Timed out after {args.timeout_sec} seconds.\n")
                raise SystemExit(f"FastConv CLI timed out for C={channels}; see {sim_target / 'generator.log'}")
            sim_target.mkdir(parents=True, exist_ok=True)
            (sim_target / "generator.log").write_text(completed.stdout)
            if completed.returncode:
                raise SystemExit(f"FastConv CLI failed for C={channels}; see {sim_target / 'generator.log'}")

        missing = [name for name in EXPECTED_CLI_FILES if not (sim_target / name).is_file()]
        if missing:
            raise SystemExit(f"FastConv CLI omitted files for C={channels}: {', '.join(missing)}")
        golden_command = [
            str(python), str(Path(__file__).with_name("generate_sauria_golden.py")),
            str(sim_target), "--channels", str(channels),
            "--input-side", str(IMAGE_SIDE), "--output-side", "32", "--bits", str(NBITS),
        ]
        golden_run = subprocess.run(
            golden_command,
            cwd=sauria_root,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        (sim_target / "sauria_golden.log").write_text(golden_run.stdout)
        if golden_run.returncode:
            raise SystemExit(f"SAURIA golden generation failed for C={channels}; see {sim_target / 'sauria_golden.log'}")
        header = (sim_target / "pack_data.sv").read_text()
        required_constants = {
            "NBITS": NBITS,
            "TRUNCATED_WEIGHT_TRANSFORM": 1,
            "RAW_SPATIAL_WEIGHTS": 1,
            "FEAT_INPUT_SIZE": IMAGE_SIDE,
            "FEAT_OUTPUT_SIZE": 32,
            "N_CHANNEL_IN": channels,
            "N_CHANNEL_OUT": channels,
        }
        for key, value in required_constants.items():
            if not re.search(rf"\b{key}\s*=\s*{value}\b", header):
                raise SystemExit(f"Generated package has unexpected {key} for C={channels}")

        files = {
            name: sha256(sim_target / name)
            for name in (*EXPECTED_CLI_FILES, SAURIA_GOLDEN)
        }
        manifest = {
            "tool": "fast-conv-rtl/src/fast_convolution/cli.py",
            "library_commit": library_commit,
            "library_worktree_dirty": git_value(library_root, "status", "--porcelain") != "",
            "simulation_py_sha256": sim_source_hash,
            "cli_py_sha256": cli_source_hash,
            "fastconv_rtl_commit": rtl_commit,
            "source_config": "rtl/conv4x4/data/wpn16/config",
            "source_config_sha256": config_hashes,
            "layer": {
                "input_side": IMAGE_SIDE,
                "output_side": 32,
                "kernel": [3, 3],
                "stride": 1,
                "padding": 0,
                "channel_in": channels,
                "channel_out": channels,
                "quantization_bits": 8,
                "signed_datapath_bits": NBITS,
                "truncated_weight_transform": True,
                "raw_spatial_weights_included": True,
                "seed": SEED,
                "bias": False,
            },
            "files_sha256": files,
            "reference_note": (
                "s_default_quant.txt is FastConv's unwrapped direct convolution over its "
                "Q8-scaled integer inputs. s_sauria20_mac_wrap.txt is the direct MAC reference "
                "recomputed from d.txt and original spatial weights, with signed 20-bit wrap "
                "at the output (modular accumulation). s.txt and const_feat_out in pack_data.sv "
                "are the truncated Winograd result. SAURIA must consume original spatial "
                "weights from g.txt, not transformed const_weight coefficients."
            ),
        }
        (sim_target / "dataset_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        result_rows.append({
            "Cin": channels,
            "Cout": channels,
            "input_side": IMAGE_SIDE,
            "output_side": 32,
            "kernel": "3x3",
            "stride": 1,
            "padding": 0,
            "quantization_bits": 8,
            "word_bits": NBITS,
            "truncated_weight_transform": True,
            "seed": SEED,
            "dataset": str(sim_target.relative_to(sauria_root)),
            "sauria_golden_sha256": files[SAURIA_GOLDEN],
        })

    summary_path = output_root / "summary.json"
    output_root.mkdir(parents=True, exist_ok=True)
    previous_rows = []
    if summary_path.is_file():
        previous_rows = json.loads(summary_path.read_text()).get("datasets", [])
    rows_by_channels = {row["Cin"]: row for row in previous_rows}
    rows_by_channels.update({row["Cin"]: row for row in result_rows})
    merged_rows = [rows_by_channels[channel] for channel in sorted(rows_by_channels)]
    summary_path.write_text(json.dumps({"datasets": merged_rows}, indent=2) + "\n")
    print(f"Recorded {len(result_rows)} datasets; summary now has {len(merged_rows)} under {output_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
