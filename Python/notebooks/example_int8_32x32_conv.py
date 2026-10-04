#!/usr/bin/env python3
"""Run the convolution example from example_int8_32x32.ipynb."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


NOTEBOOK_DIR = Path(__file__).resolve().parent
PYTHON_DIR = NOTEBOOK_DIR.parent
REPO_ROOT = PYTHON_DIR.parent
VERILATOR_DIR = REPO_ROOT / "test" / "verilator"
TEST_DIR = REPO_ROOT / "test"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--seed",
        type=int,
        default=20261004,
        help="seed for PyTorch and NumPy random tensors (default: %(default)s)",
    )
    parser.add_argument(
        "--no-compile",
        action="store_true",
        help="reuse the already compiled int8_32x32 Verilator model",
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

    if not args.no_compile:
        subprocess.run(
            ["sh", "./compile_sauria.sh", version],
            cwd=VERILATOR_DIR,
            check=True,
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
    output, _ = slib.Conv2d_SAURIA(
        input_tensor,
        weight_tensor,
        preload,
        golden,
        conv_dict,
        hw_params,
        generate_vcd=False,
        assert_no_errors=True,
        print_statistics=True,
        test_dir=str(TEST_DIR),
        silent=False,
    )
    output = output.astype(np.int32)
    print(f"CASE=conv mean_absolute_error={np.abs(output - golden).mean()}")


if __name__ == "__main__":
    main()
