#!/usr/bin/env python3
"""Generate deterministic SAURIA-native inputs and golden for sa6x6_w5."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "Python"))

from src import data_helper, execution_model, sauria_lib  # noqa: E402
from src.config_helper import get_sauria_regs  # noqa: E402
from src.hw_versions import get_params  # noqa: E402


CHANNELS = 16
INPUT_SIDE = 34
OUTPUT_SIDE = 32
KERNEL = 3
WORD_BITS = 20
OPERAND_BITS = 8
LANES = 6
SRAM_BITS = WORD_BITS * LANES
X_USED = 4
Y_USED = 4
SEED = 0
WORD_MASK = (1 << WORD_BITS) - 1


def pack_words(values: np.ndarray) -> list[int]:
    flat = [int(value) & WORD_MASK for value in values.reshape(-1)]
    words = []
    for base in range(0, len(flat), LANES):
        word = 0
        for lane, value in enumerate(flat[base : base + LANES]):
            word |= value << (lane * WORD_BITS)
        words.append(word)
    return words


def write_mem(path: Path, values: list[int], width: int) -> None:
    digits = (width + 3) // 4
    path.write_text("".join(f"{value:0{digits}x}\n" for value in values))


def signed_wrap(values: np.ndarray, bits: int) -> np.ndarray:
    modulus = 1 << bits
    sign = 1 << (bits - 1)
    return ((values.astype(np.int64) + sign) % modulus - sign).astype(np.int64)


def direct_quantized_convolution(features: np.ndarray, weights: np.ndarray) -> np.ndarray:
    """Independent integer reference, with the SAURIA 20-bit output wrap."""
    acc = np.zeros((CHANNELS, OUTPUT_SIDE, OUTPUT_SIDE), dtype=np.int64)
    for kh in range(KERNEL):
        for kw in range(KERNEL):
            patch = features[:, kh : kh + OUTPUT_SIDE, kw : kw + OUTPUT_SIDE]
            acc += np.einsum(
                "oc,chw->ohw",
                weights[:, :, kh, kw].astype(np.int64),
                patch.astype(np.int64),
                dtype=np.int64,
                optimize=True,
            )
    return signed_wrap(acc, WORD_BITS)


def tensor_sha256(values: np.ndarray) -> str:
    canonical = np.asarray(values, dtype="<i8", order="C")
    return hashlib.sha256(canonical.tobytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("vectors"))
    parser.add_argument("--seed", type=int, default=SEED)
    args = parser.parse_args()

    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)

    hopts = get_params("asic_int20_6x6")
    tensor_shapes = (
        [CHANNELS, INPUT_SIDE, INPUT_SIDE],
        [CHANNELS, CHANNELS, KERNEL, KERNEL],
        [CHANNELS, OUTPUT_SIDE, OUTPUT_SIDE],
    )
    tiling = {
        "C_tile_shape": [CHANNELS, OUTPUT_SIDE, OUTPUT_SIDE],
        "tile_cin": CHANNELS,
        "X_used": X_USED,
        "Y_used": Y_USED,
    }
    conv = sauria_lib.get_conv_dict(
        tensor_shapes, tiling, hopts, preloads=0, d=1, s=1, p=0
    )

    # Generate the same signed 8-bit integer operands as SAURIA's int8 data
    # path, but keep the actual hardware/model parameters at 20 bits.
    generation_hopts = dict(hopts)
    generation_hopts["IA_W"] = OPERAND_BITS
    generation_hopts["IB_W"] = OPERAND_BITS
    np.random.seed(args.seed)
    features, weights, psum_init = data_helper.generate_tensors(
        conv, generation_hopts, insert_deadbeef=False
    )

    model_output, _, _ = execution_model.get_ideal_results(
        features,
        weights,
        psum_init,
        conv,
        hopts,
        sauria_lib.get_sa_dict(hopts),
    )
    golden = signed_wrap(model_output, WORD_BITS)
    direct = direct_quantized_convolution(features, weights)
    if not np.array_equal(golden, direct):
        mismatch = int(np.count_nonzero(golden != direct))
        raise RuntimeError(
            f"SAURIA model disagrees with direct quantized convolution at {mismatch} outputs"
        )

    optimized_weights = data_helper.optimize_weight_tensor_shape(weights, conv)
    regs, _ = get_sauria_regs(conv, hopts, silent=True)

    write_mem(out / "ifmap.mem", pack_words(features), SRAM_BITS)
    write_mem(out / "weights.mem", pack_words(optimized_weights), SRAM_BITS)
    write_mem(
        out / "psum_init.mem",
        [0] * ((golden.size + LANES - 1) // LANES),
        SRAM_BITS,
    )
    write_mem(out / "golden.mem", [int(x) & WORD_MASK for x in golden.reshape(-1)], WORD_BITS)
    write_mem(
        out / "config.mem",
        [((int(address) & 0xFFFFFFFF) << 32) | (int(data) & 0xFFFFFFFF) for address, data in regs],
        64,
    )

    vector_files = (
        "ifmap.mem",
        "weights.mem",
        "psum_init.mem",
        "golden.mem",
        "config.mem",
    )
    manifest = {
        "generator": "SAURIA Python data_helper.generate_tensors",
        "golden_model": "SAURIA Python execution_model.get_ideal_results",
        "independent_check": "direct signed integer convolution, then signed 20-bit wrap",
        "seed": args.seed,
        "array": {"x": hopts["X"], "y": hopts["Y"], "x_used": X_USED, "y_used": Y_USED},
        "layer": {
            "cin": CHANNELS,
            "cout": CHANNELS,
            "ifmap": [CHANNELS, INPUT_SIDE, INPUT_SIDE],
            "weights": [CHANNELS, CHANNELS, KERNEL, KERNEL],
            "output": [CHANNELS, OUTPUT_SIDE, OUTPUT_SIDE],
            "kernel": [KERNEL, KERNEL],
            "stride": 1,
            "padding": 0,
        },
        "numeric": {
            "operand_signed_bits": OPERAND_BITS,
            "operand_representation_bits": WORD_BITS,
            "accumulator_signed_bits": WORD_BITS,
            "overflow": "wrap modulo 2^20 after accumulation",
            "saturation": False,
            "ifmap_range": [int(features.min()), int(features.max())],
            "weight_range": [int(weights.min()), int(weights.max())],
            "output_range": [int(golden.min()), int(golden.max())],
        },
        "counts": {
            "register_words": len(regs),
            "ifmap_scalars": int(features.size),
            "weight_scalars": int(weights.size),
            "output_scalars": int(golden.size),
        },
        "sha256": {
            "ifmap_tensor_i64le": tensor_sha256(features),
            "weights_tensor_i64le": tensor_sha256(weights),
            "golden_tensor_i64le": tensor_sha256(golden),
            "vectors": {
                name: hashlib.sha256((out / name).read_bytes()).hexdigest()
                for name in vector_files
            },
        },
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(
        f"Generated SAURIA-native vectors in {out}; seed={args.seed}; "
        f"input range={manifest['numeric']['ifmap_range']}; "
        f"weight range={manifest['numeric']['weight_range']}; "
        f"golden sha256={manifest['sha256']['golden_tensor_i64le']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
