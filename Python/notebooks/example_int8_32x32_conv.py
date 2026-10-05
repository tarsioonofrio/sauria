#!/usr/bin/env python3
"""Run the 3x3 INT8 convolution through SAURIA's original subsystem testbench."""

from __future__ import annotations

import argparse
import hashlib
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
        "--array-size",
        type=int,
        choices=(2, 3, 4, 5, 6, 8),
        default=8,
        help="physical systolic array dimension N for an NxN array (default: %(default)s)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
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

    version = f"int8_{args.array_size}x{args.array_size}"
    hw_params = hwv.get_params(version)
    print(
        f"SAURIA subsystem: 3x3 INT8 convolution | version={version} "
        f"| seed={args.seed}"
    )

    subprocess.run(
        ["sh", "./compile_sauria.sh", version],
        cwd=VERILATOR_DIR,
        check=True,
    )

    channels_in = channels_out = 3
    kernel_h = kernel_w = 3
    stride = dilation = 1
    input_h = input_w = 32
    output_h = (input_h - dilation * (kernel_h - 1) - 1) // stride + 1
    output_w = (input_w - dilation * (kernel_w - 1) - 1) // stride + 1

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
    golden_torch = (bias_torch + torch_functional.conv2d(
        input_torch.double(),
        weight_torch.double(),
        stride=stride,
        padding=0,
        dilation=dilation,
    )).to(torch.int32)

    input_tensor = input_torch.numpy()
    weight_tensor = weight_torch.numpy()
    preload = np.broadcast_to(
        bias_torch.numpy().astype(np.int32), (channels_out, output_h, output_w)
    ).copy()
    golden = golden_torch.numpy()
    tensor_shapes = [input_tensor.shape, weight_tensor.shape, golden.shape]
    x_used = max(
        size
        for size in range(1, min(args.array_size, channels_out) + 1)
        if channels_out % size == 0
    )
    y_used = max(
        size
        for size in range(1, min(args.array_size, output_w) + 1)
        if output_w % size == 0
    )
    tiling = {
        "C_tile_shape": [3, 10, 30],
        "tile_cin": 3,
        "X_used": x_used,
        "Y_used": y_used,
    }
    conv_dict = slib.get_conv_dict(
        tensor_shapes, tiling, hw_params, d=dilation, s=stride, preloads=True
    )

    print(
        "\nCASE=conv "
        f"IFMAP={input_tensor.shape} WEIGHTS={weight_tensor.shape} "
        f"OUTPUT={golden.shape} TILE={tiling['C_tile_shape']} "
        f"ARRAY={args.array_size}x{args.array_size} "
        f"PHYSICAL_MULTIPLIERS={args.array_size**2} "
        f"ACTIVE_PES={x_used * y_used} (X_used={x_used}, Y_used={y_used})"
    )
    dataset_hash = hashlib.sha256()
    for tensor in (input_tensor, weight_tensor, preload):
        dataset_hash.update(np.ascontiguousarray(tensor).tobytes())
    print(f"DATASET_SHA256={dataset_hash.hexdigest()}")
    output, stats = slib.Conv2d_SAURIA(
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
    output = np.asarray(output, dtype=np.int32)
    np.testing.assert_array_equal(output, golden)

    checksum = hashlib.sha256(np.asarray(output, dtype="<i4").tobytes()).hexdigest()
    print("TEST PASSED (full layer matches the direct int32 convolution)")
    print(f"LAYER_CYCLES={stats['total_cycles']}")
    print(f"OUTPUT_SHA256={checksum}")
    print(f"Official stimuli/results directory: {TEST_DIR}")


if __name__ == "__main__":
    main()
