#!/usr/bin/env python3
"""Generate deterministic SAURIA-native workload vectors for notebook ASIC flows."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Python"))

from src import data_helper, execution_model, sauria_lib  # noqa: E402
from src.config_helper import get_controller_regs, get_sauria_regs  # noqa: E402
from src.hw_versions import get_params  # noqa: E402


PROFILES = {
    "fp16_8x16": {
        "version": "FP16_8x16",
        # Keep the SRAM capacities from hw_versions.get_params used by the
        # notebooks. These are word depths, not complete-layer capacities.
        "memory_depths": (2048, 1024, 2048),
        # SRAM A is Y lanes, SRAM B is X lanes, and SRAM C is Y lanes.
        "lanes": (16, 8, 8),
        "cases": {
            "conv-small": {
                "shapes": ([32, 10, 10], [32, 32, 3, 3], [32, 8, 8]),
                "tiling": {"C_tile_shape": [32, 4, 8], "tile_cin": 32, "X_used": 16, "Y_used": 8},
                "seed": 20261003,
            },
            "conv-large": {
                "shapes": ([64, 34, 34], [128, 64, 3, 3], [128, 32, 32]),
                "tiling": {"C_tile_shape": [32, 8, 32], "tile_cin": 32, "loop_order": 1, "X_used": 16, "Y_used": 8},
                "seed": 20261004,
            },
        },
    },
    "int8_32x32": {
        "version": "int8_32x32",
        "memory_depths": (2048, 2048, 1024),
        "lanes": (32, 32, 32),
        "cases": {
            "conv-x3-y3": {
                "shapes": ([3, 32, 32], [3, 3, 3, 3], [3, 30, 30]),
                "tiling": {"C_tile_shape": [3, 10, 30], "tile_cin": 3, "X_used": 3, "Y_used": 3},
                "seed": 20261004,
            },
            "conv": {
                "shapes": ([64, 66, 66], [64, 64, 3, 3], [64, 64, 64]),
                "tiling": {"C_tile_shape": [64, 8, 64], "tile_cin": 64, "X_used": 32, "Y_used": 32},
                "seed": 20261005,
            },
            "gemm": {
                "shapes": ([512, 1, 256], [512, 512, 1, 1], [512, 1, 256]),
                "tiling": {"C_tile_shape": [128, 1, 256], "tile_cin": 256, "X_used": 32, "Y_used": 32},
                "seed": 20261006,
            },
        },
    },
}

for array_size in (2, 3, 4, 5, 6, 7, 8):
    x_used = max(value for value in (1, 3) if value <= array_size)
    y_used = max(value for value in (1, 2, 3, 5, 6, 10, 15, 30) if value <= array_size)
    case_name = f"conv-x{x_used}-y{y_used}"
    PROFILES[f"int16_{array_size}x{array_size}"] = {
        "version": f"int16_{array_size}x{array_size}",
        "memory_depths": (2048, 2048, 1024),
        # SRAM A/C carry Y lanes; SRAM B carries X lanes.
        "lanes": (array_size, array_size, array_size),
        "cases": {
            case_name: {
                # Keep the same Cin=3, Cout=12 layer for every array. The
                # output tile remains three channels so it fits the C SRAM;
                # the controller iterates over all four output-channel tiles.
                "shapes": ([3, 32, 32], [12, 3, 3, 3], [12, 30, 30]),
                "tiling": {
                    "C_tile_shape": [3, 10, 30],
                    "tile_cin": 3,
                    "X_used": x_used,
                    "Y_used": y_used,
                },
                "seed": 20261004,
            },
        },
    }


def update_memory_depths(hopts: dict, depths: tuple[int, int, int]) -> None:
    hopts["MEMA_DEPTH"], hopts["MEMB_DEPTH"], hopts["MEMC_DEPTH"] = depths
    hopts["ADRA_W"] = int(np.ceil(np.log2(hopts["MEMA_DEPTH"])))
    hopts["ADRB_W"] = int(np.ceil(np.log2(hopts["MEMB_DEPTH"])))
    hopts["ADRC_W"] = int(np.ceil(np.log2(hopts["MEMC_DEPTH"])))
    hopts["IFM_WOFS_W"] = int(np.ceil(np.log2(hopts["MEMA_N"])))
    hopts["WEI_WOFS_W"] = int(np.ceil(np.log2(hopts["MEMB_N"])))
    hopts["PSM_WOFS_W"] = int(np.ceil(np.log2(hopts["MEMC_N"])))
    hopts["IFM_IDX_W"] = hopts["ADRA_W"] + hopts["IFM_WOFS_W"] + 1
    hopts["WEI_IDX_W"] = hopts["ADRB_W"] + hopts["WEI_WOFS_W"] + 1
    hopts["PSM_IDX_W"] = hopts["ADRC_W"] + hopts["PSM_WOFS_W"] + 1
    hopts["MEMA_size"] = hopts["MEMA_DEPTH"] * hopts["MEMA_N"]
    hopts["MEMB_size"] = hopts["MEMB_DEPTH"] * hopts["MEMB_N"]
    hopts["MEMC_size"] = hopts["MEMC_DEPTH"] * hopts["MEMC_N"]


def signed_wrap(values: np.ndarray, bits: int) -> np.ndarray:
    modulus = 1 << bits
    sign = 1 << (bits - 1)
    return ((values.astype(np.int64) + sign) % modulus - sign).astype(np.int64)


def fp16_fma_convolution(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> np.ndarray:
    """Reference the SAURIA FP16 MAC: fused multiply-add, rounded per MAC."""
    output_h = a.shape[1] - b.shape[2] + 1
    output_w = a.shape[2] - b.shape[3] + 1
    acc = np.asarray(c, dtype=np.float16).astype(np.float64)
    for cin in range(a.shape[0]):
        for kh in range(b.shape[2]):
            for kw in range(b.shape[3]):
                activation = a[cin, kh:kh + output_h, kw:kw + output_w].astype(np.float64)
                weights = b[:, cin, kh, kw].astype(np.float64)[:, None, None]
                # Binary16 operands and accumulators are exactly represented in
                # binary64 here; convert back after each MAC to model FP16 RNE.
                acc = (weights * activation[None, :, :] + acc).astype(np.float16).astype(np.float64)
    return acc.astype(np.float16)


def case_tensors(profile: str, case: str, hopts: dict, conv: dict, seed: int):
    if profile == "fp16_8x16":
        rng = np.random.default_rng(seed)
        np.random.seed(seed)
        a, b, c = data_helper.generate_tensors(conv, hopts, insert_deadbeef=False)
        output = fp16_fma_convolution(a, b, c)
        return a, b, c, output, "FP16 fused multiply-add with rounding after each MAC"

    shapes = PROFILES[profile]["cases"][case]["shapes"]
    a_shape, b_shape, out_shape = shapes
    if profile.startswith("int16_"):
        # Match FastConv cmd_sim_normal: seeded N(0, 1) tensors, Q8 scaling,
        # truncation toward zero, and signed wrap at the configured port width.
        # "8 bits" here means fractional precision, not signed int8 saturation.
        rng = np.random.RandomState(seed)
        a = signed_wrap(
            (rng.normal(0, 1, size=a_shape) * (2**8)).astype(np.int64),
            hopts["IA_W"],
        )
        b = signed_wrap(
            (rng.normal(0, 1, size=b_shape) * (2**8)).astype(np.int64),
            hopts["IB_W"],
        )
    else:
        rng = np.random.default_rng(seed)
        a = rng.integers(-127, 127, size=a_shape, dtype=np.int16).astype(np.int8)
        b = rng.integers(-127, 127, size=b_shape, dtype=np.int16).astype(np.int8)
    c = np.zeros(out_shape, dtype=np.int64)
    if profile.startswith("int16_"):
        # The FastConv normal simulation used for the reference workload has
        # bias disabled; keep preload/initial partial sums at zero.
        out = c.copy()
        for kh in range(3):
            for kw in range(3):
                patch = a[:, kh:kh + out_shape[1], kw:kw + out_shape[2]].astype(np.int64)
                out += np.einsum("oc,chw->ohw", b[:, :, kh, kw].astype(np.int64), patch, optimize=True)
    elif case.startswith("conv"):
        c[:, :, :] = rng.integers(-127, 127, size=(out_shape[0], 1, 1), dtype=np.int16)
        out = c.copy()
        for kh in range(3):
            for kw in range(3):
                patch = a[:, kh:kh + out_shape[1], kw:kw + out_shape[2]].astype(np.int64)
                out += np.einsum("oc,chw->ohw", b[:, :, kh, kw].astype(np.int64), patch, optimize=True)
    else:
        out = np.matmul(b[:, :, 0, 0].astype(np.int64), a[:, 0, :].astype(np.int64))[:, None, :]
    out = signed_wrap(out, hopts["OC_W"])
    golden_model = (
        "direct convolution of seeded Gaussian Q8 operands, bias disabled, "
        f"signed {hopts['OC_W']}-bit accumulator wrap"
        if profile.startswith("int16_")
        else "direct integer convolution/GEMM with signed accumulator wrap"
    )
    return a, b, c, out, golden_model


def encoded(values: np.ndarray, bits: int, floating: bool, mantissa: int) -> np.ndarray:
    flat = np.asarray(values).reshape(-1)
    if floating:
        return data_helper.encode_array_to_FP(flat, mantissa, bits).astype(np.uint64)
    return np.asarray(flat, dtype=np.int64).astype(np.uint64) & ((1 << bits) - 1)


def pack(values: np.ndarray, lanes: int, bits: int, floating: bool, mantissa: int) -> list[int]:
    flat = encoded(values, bits, floating, mantissa)
    packed: list[int] = []
    for start in range(0, flat.size, lanes):
        word = 0
        for lane, value in enumerate(flat[start:start + lanes]):
            word |= int(value) << (lane * bits)
        packed.append(word)
    return packed


def write_words(path: Path, words: list[int], width: int) -> None:
    digits = (width + 3) // 4
    path.write_text("".join(f"{value:0{digits}x}\n" for value in words))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tensor_sha256(values: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(values).tobytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES, required=True)
    parser.add_argument("--case", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument(
        "--input-npz",
        type=Path,
        help="use A, B, C, output, and seed arrays from this NPZ instead of generated vectors",
    )
    args = parser.parse_args()

    profile = PROFILES[args.profile]
    if args.case not in profile["cases"]:
        parser.error(f"unknown case {args.case!r} for {args.profile}")
    case_spec = profile["cases"][args.case]
    outdir = args.out.resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    hopts = get_params(profile["version"])
    update_memory_depths(hopts, profile["memory_depths"])
    shapes = case_spec["shapes"]
    tiling = dict(case_spec["tiling"])
    conv = sauria_lib.get_conv_dict(shapes, tiling, hopts, preloads=True, d=1, s=1, p=0)
    vector_source = "generated"
    seed = case_spec["seed"]
    if args.input_npz:
        with np.load(args.input_npz, allow_pickle=False) as tensors:
            a = tensors["A"]
            b = tensors["B"]
            c = tensors["C"]
            output = tensors["output"]
            if "seed" in tensors.files:
                seed = int(tensors["seed"])
        expected_shapes = tuple(tuple(shape) for shape in shapes)
        actual_shapes = (a.shape, b.shape, output.shape)
        if actual_shapes != expected_shapes or c.shape != output.shape:
            raise ValueError(
                f"NPZ tensor shapes do not match {args.profile}/{args.case}: "
                f"A/B/output={actual_shapes}, C={c.shape}, expected={expected_shapes}"
            )
        golden_model = "caller-provided full-precision integer convolution output"
        vector_source = str(args.input_npz.resolve())
    else:
        a, b, c, output, golden_model = case_tensors(
            args.profile, args.case, hopts, conv, seed
        )
    if tuple(output.shape) != tuple(shapes[2]):
        raise RuntimeError(f"model output shape {output.shape} does not match requested {shapes[2]}")

    weights = data_helper.optimize_weight_tensor_shape(b, conv)
    regs, _ = get_sauria_regs(conv, hopts, silent=True)
    _, _, _, loop_order = execution_model.get_tiling_loops(conv)
    dram, dram_gold, dram_offsets = data_helper.assign_dram_values(
        a, weights, c, output, 0, conv, hopts
    )
    controller_args = get_controller_regs(
        conv, regs, len(regs), dram_offsets, loop_order, silent=True
    )
    float_mode = bool(hopts["OP_TYPE"])
    x_lanes, y_lanes, c_lanes = profile["lanes"]
    a_words = pack(a, y_lanes, hopts["IA_W"], float_mode, hopts["IA_MANT"])
    b_words = pack(weights, x_lanes, hopts["IB_W"], float_mode, hopts["IB_MANT"])
    c_words = pack(c, c_lanes, hopts["OC_W"], float_mode, hopts["IC_MANT"])
    gold_words = encoded(output, hopts["OC_W"], float_mode, hopts["IC_MANT"])

    write_words(outdir / "ifmap.mem", a_words, y_lanes * hopts["IA_W"])
    write_words(outdir / "weights.mem", b_words, x_lanes * hopts["IB_W"])
    write_words(outdir / "psum_init.mem", c_words, c_lanes * hopts["OC_W"])
    write_words(outdir / "golden.mem", [int(x) for x in gold_words], hopts["OC_W"])
    write_words(outdir / "config.mem", [((int(addr) & 0xffffffff) << 32) | (int(val) & 0xffffffff) for addr, val in regs], 64)
    # Match Conv2d_SAURIA's native path: the host programs the dataflow
    # controller once, then its start register advances all tiles and its DMA
    # commands fetch from / write back to the external-memory image.
    controller_writes = [(int(hopts["CTRL_offset"]) + 0x8, 0x3)]
    controller_writes.extend(
        (int(hopts["CTRL_offset"]) + 0x10 + 4 * index, int(value) & 0xffffffff)
        for index, value in enumerate(controller_args)
    )
    write_words(
        outdir / "controller_config.mem",
        [((address & 0xffffffff) << 32) | value for address, value in controller_writes],
        64,
    )
    write_words(outdir / "dram.mem", [int(value) for value in dram], 8)
    write_words(outdir / "dram_gold.mem", [int(value) for value in dram_gold], 8)

    layer = {
        "input_shape": list(shapes[0]),
        "weight_shape": list(shapes[1]),
        "output_shape": list(shapes[2]),
        "kernel": list(shapes[1][2:]),
        "stride": 1,
        "padding": 0,
        "dilation": 1,
    }
    counts = {
        "config_words": len(regs),
        "controller_config_words": len(controller_writes),
        "dram_bytes": int(dram.size),
        "output_bytes": int(dram.size - dram_offsets[2]),
        "ifmap_words": len(a_words),
        "weight_words": len(b_words),
        "output_words": len(c_words),
        "output_values": int(output.size),
    }
    files = [
        "ifmap.mem", "weights.mem", "psum_init.mem", "golden.mem", "config.mem",
        "controller_config.mem", "dram.mem", "dram_gold.mem",
    ]
    manifest = {
        "profile": args.profile,
        "version": profile["version"],
        "case": args.case,
        "seed": seed,
        "vector_source": vector_source,
        "array": {"x": hopts["X"], "y": hopts["Y"]},
        "numbers": {"operand_bits": [hopts["IA_W"], hopts["IB_W"]], "accumulator_bits": hopts["OC_W"], "floating": float_mode, "overflow": "signed wrap modulo 2^OC_W" if not float_mode else "SAURIA floating-point encoding/rounding model", "saturation": False if not float_mode else "SAURIA FP encoder underflow-to-zero and overflow clamp"},
        "memory_depths": list(profile["memory_depths"]),
        "memory_capacity_bits_per_bank": [hopts["MEMA_W"] * hopts["MEMA_DEPTH"], hopts["MEMB_W"] * hopts["MEMB_DEPTH"], hopts["MEMC_W"] * hopts["MEMC_DEPTH"]],
        "layer": layer,
        "tiling": tiling,
        "controller": {
            "config_base": int(hopts["CTRL_offset"]),
            "register_count": len(controller_args),
            "layer_start_address": int(hopts["CTRL_offset"]),
            "dram_offsets_bytes": [int(x) for x in dram_offsets],
            "loop_order": int(loop_order),
            "start_policy": "one layer start; controller schedules all tiles",
        },
        "golden_model": golden_model,
        "tensor_sha256": {
            "ifmap": tensor_sha256(a),
            "weights": tensor_sha256(b),
            "initial_partial_sums": tensor_sha256(c),
            "golden": tensor_sha256(output),
        },
        "quantization": (
            {
                "distribution": "normal",
                "mean": 0,
                "standard_deviation": 1,
                "fractional_bits": 8,
                "conversion": "truncate toward zero after multiplying by 2^8",
                "operand_width_bits": [hopts["IA_W"], hopts["IB_W"]],
                "signed_overflow": "wrap modulo 2^operand_width",
                "bias": "disabled; zero initial partial sums",
                "saturation": False,
            }
            if args.profile.startswith("int16_")
            else None
        ),
        "counts": counts,
        "sha256": {name: sha256(outdir / name) for name in files},
    }
    (outdir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    env_values = {
        **counts,
        "dram_a_offset": int(dram_offsets[0]),
        "dram_b_offset": int(dram_offsets[1]),
        "dram_c_offset": int(dram_offsets[2]),
    }
    (outdir / "run.env").write_text("".join(f"{key.upper()}={value}\n" for key, value in env_values.items()))
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
