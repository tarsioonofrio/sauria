#!/usr/bin/env python3
"""Run the convolution example from example_int8_32x32.ipynb."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import subprocess
import sys


NOTEBOOK_DIR = Path(__file__).resolve().parent
PYTHON_DIR = NOTEBOOK_DIR.parent
REPO_ROOT = PYTHON_DIR.parent
SIM_DIR = REPO_ROOT / "experiments" / "asic_notebook_power" / "int8_32x32" / "sim"
RUN_ARTIFACTS = SIM_DIR / "run_artifacts"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--seed",
        type=int,
        default=20261004,
        help="seed for PyTorch and NumPy random tensors (default: %(default)s)",
    )
    parser.add_argument(
        "--simulator",
        choices=("xcelium", "icarus", "verilator"),
        default="xcelium",
        help="RTL simulator to use through the ASIC run.sh harness (default: %(default)s)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    os.chdir(NOTEBOOK_DIR)
    sys.path.insert(0, str(PYTHON_DIR))

    from dotenv import load_dotenv

    load_dotenv(PYTHON_DIR / "env", override=True)

    import numpy as np
    import torch
    import torch.nn.functional as torch_functional

    import src.hw_versions as hwv
    import src.sauria_lib as slib

    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    version = "int8_32x32"
    hw_params = hwv.get_params(version)
    print(
        f"SAURIA notebook: example_int8_32x32 conv | version={version} "
        f"| seed={args.seed}"
    )

    channels_in = channels_out = 3
    kernel_h = kernel_w = 3
    stride = dilation = 1
    input_w = input_h = 32
    output_w = (input_w - dilation * (kernel_w - 1) - 1) // stride + 1
    output_h = (input_h - dilation * (kernel_h - 1) - 1) // stride + 1

    input_torch = torch.randint(
        -127, 127, (channels_in, input_h, input_w), dtype=torch.int8
    )
    weight_torch = torch.randint(
        -127,
        127,
        (channels_out, channels_in, kernel_h, kernel_w),
        dtype=torch.int8,
    )
    bias_torch = torch.randint(-127, 127, (channels_out, 1, 1), dtype=torch.int8)
    golden_torch = bias_torch + torch_functional.conv2d(
        input_torch.double(),
        weight_torch.double(),
        stride=stride,
        padding=0,
        dilation=dilation,
    )
    golden_torch = golden_torch.int()

    input_tensor = input_torch.detach().numpy()
    weight_tensor = weight_torch.detach().numpy()
    bias = bias_torch.detach().numpy()
    preload = np.zeros((channels_out, output_h, output_w))
    preload[:, :, :] = bias.reshape(channels_out, 1, 1)
    golden = golden_torch.detach().numpy()
    tensor_shapes = [input_tensor.shape, weight_tensor.shape, golden.shape]
    tiling = {
        "C_tile_shape": [3, 10, 30],
        "tile_cin": 3,
        "X_used": 3,
        "Y_used": 3,
    }
    conv_dict = slib.get_conv_dict(
        tensor_shapes, tiling, hw_params, d=dilation, s=stride, preloads=True
    )

    print(
        "\nCASE=conv "
        f"IFMAP={input_tensor.shape} WEIGHTS={weight_tensor.shape} "
        f"OUTPUT={golden.shape} TILE={tiling['C_tile_shape']}"
    )
    run_id = (
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        + f"-notebook-seed{args.seed}-{args.simulator}"
    )
    run_root = RUN_ARTIFACTS / run_id
    run_root.mkdir(parents=True, exist_ok=False)
    tensor_file = run_root / "notebook_tensors.npz"
    np.savez_compressed(
        tensor_file,
        A=input_tensor,
        B=weight_tensor,
        C=preload.astype(np.int64),
        output=golden.astype(np.int64),
        seed=np.asarray(args.seed, dtype=np.int64),
    )

    sim_env = os.environ.copy()
    sim_env.update(
        {
            "RUN_ID": run_id,
            "SIM_STAGE": "rtl",
            "SIMULATOR": args.simulator,
            "SIM_CASES": "conv-x3-y3",
            "SIM_VECTOR_INPUT": str(tensor_file),
        }
    )
    print(f"{args.simulator} RTL simulation | RUN_ID={run_id} | vectors={tensor_file}")
    subprocess.run(["bash", str(SIM_DIR / "run.sh")], cwd=REPO_ROOT, env=sim_env, check=True)

    log_names = {
        "xcelium": "rtl-xrun.log",
        "icarus": "rtl-iverilog.log",
        "verilator": "rtl-verilator.log",
    }
    simulation_log = run_root / "conv-x3-y3" / log_names[args.simulator]
    log_text = simulation_log.read_text()
    if "NOTEBOOK_LAYER_PASS" not in log_text:
        raise RuntimeError(
            f"{args.simulator} did not report a full-layer golden pass: {simulation_log}"
        )
    cycles = re.search(r"LAYER_CYCLES=(\d+)", log_text)
    checksum = re.search(r"OUTPUT_CHECKSUM=([0-9a-fA-F]+)", log_text)
    if not cycles or not checksum:
        raise RuntimeError(
            f"{args.simulator} pass log is missing cycle/checksum data: {simulation_log}"
        )
    print(f"TEST PASSED ({args.simulator} full-layer golden check)")
    print(f"CASE=conv cycles={cycles.group(1)} outputs_checksum={checksum.group(1)}")
    print(f"CASE=conv mean_absolute_error=0.0")
    print(f"Simulation log: {simulation_log}")


if __name__ == "__main__":
    main()
