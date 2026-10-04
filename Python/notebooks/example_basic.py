#!/usr/bin/env python3
"""Run both convolution examples from example_basic.ipynb."""

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
        "--case",
        choices=("all", "small", "large"),
        default="all",
        help="which notebook convolution to run (default: all)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=20261004,
        help="seed for PyTorch and NumPy random tensors (default: %(default)s)",
    )
    parser.add_argument(
        "--no-compile",
        action="store_true",
        help="reuse the already compiled FP16_8x16 Verilator model",
    )
    parser.add_argument(
        "--vcd-small",
        action="store_true",
        help="write a VCD for the small case (can be large and slow)",
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

    import src.hw_versions as hwv
    import src.sauria_lib as slib

    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    version = "FP16_8x16"
    hw_params = hwv.get_params(version)
    print(f"SAURIA notebook: example_basic | version={version} | seed={args.seed}")

    if not args.no_compile:
        subprocess.run(
            ["sh", "./compile_sauria.sh", version],
            cwd=VERILATOR_DIR,
            check=True,
        )

    if args.case in ("all", "small"):
        channels_in = 32
        channels_out = 32
        kernel_h = kernel_w = 3
        stride = dilation = 1
        output_w = output_h = 8
        input_w = (1 + stride * (output_w - 1)) + (1 + dilation * (kernel_w - 1)) - 1
        input_h = (1 + stride * (output_h - 1)) + (1 + dilation * (kernel_h - 1)) - 1

        conv = torch.nn.Conv2d(
            channels_in,
            channels_out,
            (kernel_h, kernel_w),
            stride=stride,
            dilation=dilation,
        )
        input_torch = torch.randn(channels_in, input_h, input_w, dtype=torch.float32)
        golden_torch = conv(input_torch)

        input_tensor = input_torch.detach().numpy()
        weight_tensor = conv.weight.detach().numpy()
        bias = conv.bias.detach().numpy()
        preload = np.zeros((channels_out, output_h, output_w))
        preload[:, :, :] = bias.reshape(channels_out, 1, 1)
        golden = golden_torch.detach().numpy()
        tensor_shapes = [input_tensor.shape, weight_tensor.shape, golden.shape]
        tiling = {
            "C_tile_shape": [32, 4, 8],
            "tile_cin": 32,
            "X_used": 16,
            "Y_used": 8,
        }
        conv_dict = slib.get_conv_dict(
            tensor_shapes, tiling, hw_params, d=dilation, s=stride, preloads=True
        )

        print(
            "\nCASE=small "
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
            generate_vcd=args.vcd_small,
            assert_no_errors=True,
            print_statistics=True,
            test_dir=str(TEST_DIR),
            silent=False,
        )
        print(f"CASE=small mean_absolute_error={np.abs(output - golden).mean()}")

    if args.case in ("all", "large"):
        channels_in = 64
        channels_out = 128
        kernel_h = kernel_w = 3
        stride = dilation = 1
        output_w = output_h = 32
        input_w = (1 + stride * (output_w - 1)) + (1 + dilation * (kernel_w - 1)) - 1
        input_h = (1 + stride * (output_h - 1)) + (1 + dilation * (kernel_h - 1)) - 1
        tensor_shapes = [
            [channels_in, input_h, input_w],
            [channels_out, channels_in, kernel_h, kernel_w],
            [channels_out, output_h, output_w],
        ]
        tiling = {
            "C_tile_shape": [32, 8, 32],
            "tile_cin": 32,
            "loop_order": 1,
            "X_used": 16,
            "Y_used": 8,
        }

        print(
            "\nCASE=large "
            f"IFMAP={tuple(tensor_shapes[0])} WEIGHTS={tuple(tensor_shapes[1])} "
            f"OUTPUT={tuple(tensor_shapes[2])} TILE={tiling['C_tile_shape']}"
        )
        slib.generate_and_run_test(
            tensor_shapes,
            tiling,
            dilation,
            stride,
            hw_params,
            preload=True,
            generate_vcd=False,
            assert_no_errors=True,
            print_statistics=True,
            test_dir=str(TEST_DIR),
            silent=False,
        )


if __name__ == "__main__":
    main()
