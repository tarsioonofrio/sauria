#!/usr/bin/env python3
"""Build the direct SAURIA golden output from a FastConv dataset."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import numpy as np


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--channels", type=int, required=True)
    parser.add_argument("--input-side", type=int, default=34)
    parser.add_argument("--output-side", type=int, default=32)
    parser.add_argument("--bits", type=int, default=20)
    args = parser.parse_args()

    dataset = args.dataset.resolve()
    channels = args.channels
    features = np.loadtxt(dataset / "d.txt", dtype=np.int64).reshape(
        channels, args.input_side, args.input_side
    )
    exported_weights = np.loadtxt(dataset / "g.txt", dtype=np.int64).reshape(-1)
    bias_words = channels * channels
    weight_count = channels * channels * 3 * 3
    if exported_weights.size != bias_words + weight_count:
        raise SystemExit("Unexpected FastConv g.txt size for bias-prefixed WPN16 format")
    if np.any(exported_weights[:bias_words] != 0):
        raise SystemExit("Nonzero bias found; the SAURIA layer contract is bias-free")
    weights = exported_weights[bias_words:].reshape(channels, channels, 3, 3)

    accumulated = np.zeros((channels, args.output_side, args.output_side), dtype=np.int64)
    for kr in range(3):
        for kc in range(3):
            feature_window = features[
                :, kr : kr + args.output_side, kc : kc + args.output_side
            ]
            accumulated += np.einsum(
                "oi,ihw->ohw", weights[:, :, kr, kc], feature_window, optimize=True
            )

    direct_reference = np.loadtxt(dataset / "s_default_quant.txt", dtype=np.int64).reshape(
        channels, args.output_side, args.output_side
    )
    if not np.array_equal(accumulated, direct_reference):
        mismatch_count = int(np.count_nonzero(accumulated != direct_reference))
        raise SystemExit(
            f"FastConv direct reference disagrees with d/g vectors at {mismatch_count} outputs"
        )

    modulus = 1 << args.bits
    sign_bit = 1 << (args.bits - 1)
    wrapped = np.mod(accumulated + sign_bit, modulus) - sign_bit
    output_path = dataset / "s_sauria20_mac_wrap.txt"
    np.savetxt(output_path, wrapped.reshape(-1), fmt="%d")
    print(
        f"Direct MAC matched all {accumulated.size} FastConv reference outputs; "
        f"wrote signed {args.bits}-bit wrap golden to {output_path} "
        f"(sha256={sha256(output_path)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
