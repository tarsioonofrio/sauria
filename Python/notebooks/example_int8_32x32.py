#!/usr/bin/env python3
"""Run the GEMM example from example_int8_32x32.ipynb."""

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

    import src.hw_versions as hwv
    import src.sauria_lib as slib

    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    version = "int8_32x32"
    hw_params = hwv.get_params(version)
    print(f"SAURIA notebook: example_int8_32x32 GEMM | version={version} | seed={args.seed}")

    if not args.no_compile:
        subprocess.run(
            ["sh", "./compile_sauria.sh", version],
            cwd=VERILATOR_DIR,
            check=True,
        )

    input_channels = 512
    vector_count = 256
    output_channels = 512
    matrix_a = np.random.randint(
        -127, 127, size=(input_channels, vector_count), dtype=np.int8
    )
    matrix_b = np.random.randint(
        -127, 127, size=(output_channels, input_channels), dtype=np.int8
    )
    bias = np.random.randint(-127, 127, size=(output_channels, 1), dtype=np.int8)
    matmul_golden = np.matmul(matrix_b.astype(np.int32), matrix_a.astype(np.int32))
    golden_with_bias = matmul_golden + bias.astype(np.int32)

    tensor_a = matrix_a.reshape(input_channels, 1, vector_count)
    tensor_b = matrix_b.reshape(output_channels, input_channels, 1, 1)
    tensor_c = matmul_golden.reshape(output_channels, 1, vector_count)
    tensor_shapes = [tensor_a.shape, tensor_b.shape, tensor_c.shape]
    tiling = {
        "C_tile_shape": [128, 1, 256],
        "tile_cin": 256,
        "X_used": 32,
        "Y_used": 32,
    }
    conv_dict = slib.get_conv_dict(
        tensor_shapes, tiling, hw_params, d=1, s=1, preloads=True
    )

    print(
        "\nCASE=gemm "
        f"A={matrix_a.shape} B={matrix_b.shape} "
        f"OUTPUT={matmul_golden.shape} TILE={tiling['C_tile_shape']}"
    )
    output, _ = slib.Conv2d_SAURIA(
        tensor_a,
        tensor_b,
        None,
        tensor_c,
        conv_dict,
        hw_params,
        generate_vcd=False,
        assert_no_errors=True,
        print_statistics=True,
        test_dir=str(TEST_DIR),
        silent=False,
    )
    output_with_bias = output.squeeze().astype(np.int32) + bias.astype(np.int32)
    print(
        "CASE=gemm mean_absolute_error="
        f"{np.abs(output_with_bias - golden_with_bias).mean()}"
    )


if __name__ == "__main__":
    main()
