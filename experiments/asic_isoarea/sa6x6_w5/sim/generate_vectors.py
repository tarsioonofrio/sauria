#!/usr/bin/env python3
"""Generate direct-host SRAM/config vectors for the 6x6, C=16 ASIC layer."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "Python"))

from src.config_helper import get_sauria_regs  # noqa: E402
from src.hw_versions import get_params  # noqa: E402


CHANNELS = 16
INPUT_SIDE = 34
OUTPUT_SIDE = 32
KERNEL = 3
WORD_BITS = 20
LANES = 6
SRAM_BITS = WORD_BITS * LANES
X_USED = 4
Y_USED = 4


def pack_words(values: np.ndarray) -> list[int]:
    mask = (1 << WORD_BITS) - 1
    flat = [int(value) & mask for value in values.reshape(-1)]
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


def sauria_registers(hopts: dict[str, int]) -> np.ndarray:
    rows_active = sum(1 << (hopts["Y"] - 1 - i) for i in range(Y_USED))
    cols_active = sum(1 << (hopts["X"] - 1 - i) for i in range(X_USED))
    dil_pat = sum(
        1 << (hopts["DILP_W"] - 1 - i)
        for i in range(hopts["DILP_W"])
        if i < KERNEL
    )
    conv = {
        "B_w": KERNEL,
        "B_h": KERNEL,
        "s": 1,
        "d": 1,
        "w_til": OUTPUT_SIDE,
        "h_til": OUTPUT_SIDE,
        "k_til": CHANNELS,
        "c_til": CHANNELS,
        "A_w_til": INPUT_SIDE,
        "A_h_til": INPUT_SIDE,
        "B_w_eff": KERNEL,
        "B_h_eff": KERNEL,
        "N_cswitch": (OUTPUT_SIDE // Y_USED)
        * OUTPUT_SIDE
        * (CHANNELS // X_USED),
        "X_used": X_USED,
        "Y_used": Y_USED,
        "preload_en": 0,
        "Dil_pat": dil_pat,
        "rows_active": rows_active,
        "cols_active": cols_active,
        "lwoffs": np.asarray(
            [i if i < Y_USED else 0 for i in range(hopts["Y"])], dtype=np.int64
        ),
        "thres": 0,
    }
    regs, _ = get_sauria_regs(conv, hopts, silent=True)
    return regs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dataset",
        type=Path,
        default=ROOT
        / "experiments/asic_isoarea/datasets/c16/sim/sim-out32-k3-s1-p0-trunc-n20-q8-seed0",
    )
    parser.add_argument("--out", type=Path, default=Path("vectors"))
    args = parser.parse_args()

    dataset = args.dataset.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)

    features = np.loadtxt(dataset / "d.txt", dtype=np.int64).reshape(
        CHANNELS, INPUT_SIDE, INPUT_SIDE
    )
    exported_weights = np.loadtxt(dataset / "g.txt", dtype=np.int64).reshape(-1)
    bias_count = CHANNELS * CHANNELS
    weights = exported_weights[bias_count:].reshape(
        CHANNELS, CHANNELS, KERNEL, KERNEL
    )
    golden = np.loadtxt(dataset / "s_sauria20_mac_wrap.txt", dtype=np.int64).reshape(-1)

    # Match Python/src/data_helper.py::optimize_weight_tensor_shape for a
    # single full-layer tile: [Ktile,Ctile,Cin,Kh,Kw,k_til].
    optimized_weights = weights.reshape(1, CHANNELS, CHANNELS, KERNEL, KERNEL)
    optimized_weights = optimized_weights.reshape(
        1, CHANNELS, 1, CHANNELS, KERNEL, KERNEL
    )
    optimized_weights = np.moveaxis(optimized_weights, 1, -1).reshape(-1)

    write_mem(out / "ifmap.mem", pack_words(features), SRAM_BITS)
    write_mem(out / "weights.mem", pack_words(optimized_weights), SRAM_BITS)
    write_mem(
        out / "psum_init.mem",
        [0] * ((golden.size + LANES - 1) // LANES),
        SRAM_BITS,
    )
    write_mem(out / "golden.mem", [int(x) & ((1 << WORD_BITS) - 1) for x in golden], WORD_BITS)

    hopts = get_params("asic_int20_6x6")
    regs = sauria_registers(hopts)
    write_mem(
        out / "config.mem",
        [((int(address) & 0xFFFFFFFF) << 32) | (int(data) & 0xFFFFFFFF) for address, data in regs],
        64,
    )
    (out / "meta.txt").write_text(
        f"config_words={len(regs)}\n"
        f"ifmap_words={(features.size + LANES - 1) // LANES}\n"
        f"weight_words={(optimized_weights.size + LANES - 1) // LANES}\n"
        f"output_words={(golden.size + LANES - 1) // LANES}\n"
        f"ifmap_scalars={features.size}\n"
        f"weight_scalars={optimized_weights.size}\n"
        f"output_scalars={golden.size}\n"
        f"golden_sha256={__import__('hashlib').sha256((dataset / 's_sauria20_mac_wrap.txt').read_bytes()).hexdigest()}\n"
    )
    print(f"Generated C=16 layer vectors in {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
