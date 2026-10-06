"""
Copyright 2023 Barcelona Supercomputing Center (BSC)
SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

Licensed under the Solderpad Hardware License v 2.1 (the “License”);
you may not use this file except in compliance with the License, or,
at your option, the Apache License version 2.0.
You may obtain a copy of the License at

https://solderpad.org/licenses/SHL-2.1/

Unless required by applicable law or agreed to in writing, any work
distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.


Jordi Fornt <jfornt@bsc.es>
"""

import numpy as np
import sys
import os
from pathlib import Path
import subprocess

sys.path.insert(1, './../')
import src.data_helper as dh
import src.config_helper as cfg


REPO_ROOT = Path(__file__).resolve().parents[2]


def resolve_test_dir(test_dir="../../test"):
    """Resolve the official test data directory independently of later chdir calls."""
    path = Path(test_dir).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    return path.resolve()


def run_verilator_test(test_dir="../../test", generate_vcd=False, check_read_values=False):
    """Run the compiled original SAURIA subsystem testbench against test_dir."""
    test_dir = resolve_test_dir(test_dir)
    simulator_dir = REPO_ROOT / "test" / "verilator"
    simulator = simulator_dir / "Test-Sim"
    if not simulator.is_file():
        raise FileNotFoundError(
            f"Verilator binary not found: {simulator}. "
            "Compile the requested RTL version with compile_sauria.sh first."
        )

    stimuli_dir = test_dir / "stimuli"
    outputs_dir = test_dir / "outputs"
    required_stimuli = (
        stimuli_dir / "tstcfg.txt",
        stimuli_dir / "GoldenStimuli.txt",
        stimuli_dir / "initial_dram.txt",
        stimuli_dir / "gold_dram.txt",
    )
    missing_stimuli = [path for path in required_stimuli if not path.is_file()]
    if missing_stimuli:
        missing = ", ".join(str(path) for path in missing_stimuli)
        raise FileNotFoundError(f"Missing SAURIA test stimuli: {missing}")
    outputs_dir.mkdir(parents=True, exist_ok=True)

    max_cycles = int(os.environ.get("SAURIA_MAX_CYCLES", "1000000"))
    if max_cycles < 0:
        raise ValueError("SAURIA_MAX_CYCLES must be zero or a positive integer")

    command = [
        str(simulator),
        f"+max-cycles={max_cycles}",
        f"+stim_path={stimuli_dir}",
        f"+out_path={outputs_dir}",
    ]
    if check_read_values:
        command.append("+check_read_values")
    if generate_vcd:
        command.extend(["+vcd", f"+vcd_name={outputs_dir / 'verilated.vcd'}"])
    subprocess.run(command, cwd=simulator_dir, check=True)

# ---------------------------------------
# STIMULI MANAGEMENT
# ---------------------------------------

def generate_test_files(DRAM_mem, DRAM_mem_gold, controller_regs, testcfg_list, HOPTS, N_REGS, test_dir="../../test"):

    test_dir = resolve_test_dir(test_dir)
    
    N_VECTORS = N_REGS + 100 # Variable sized register region + an offset for high level configuration (100 should be more than enough)
            
    # Fill config arrays
    # ----------------------------------
    cfg_address, cfg_data_in, cfg_wren, cfg_rden, cfg_waitflag, cfg_checkflag, cfg_data_out = cfg.generate_controller_cmds(controller_regs, N_VECTORS, HOPTS)

    # Create & organize output matrices
    # ----------------------------------
    
    Input_Matrix = np.zeros((N_VECTORS, 7), dtype=np.uint64)
    
    Input_Matrix[:,0] = dh.convert_to_intN(cfg_data_in, HOPTS['CFG_AXI_DATA_WIDTH'])
    Input_Matrix[:,1] = dh.convert_to_intN(cfg_address, HOPTS['CFG_AXI_ADDR_WIDTH'])
    Input_Matrix[:,2] = cfg_wren
    Input_Matrix[:,3] = cfg_rden
    Input_Matrix[:,4] = cfg_waitflag
    Input_Matrix[:,5] = cfg_data_out
    Input_Matrix[:,6] = cfg_checkflag
        
    # Save output matrices
    # ----------------------------------

    # Create stmuli and output directories if it they don't exist
    (test_dir / "stimuli").mkdir(parents=True, exist_ok=True)
    (test_dir / "outputs").mkdir(parents=True, exist_ok=True)

    # Save matrices
    np.savetxt(test_dir / "stimuli/GoldenStimuli.txt", Input_Matrix, fmt='%01X', delimiter=' ')
    np.savetxt(test_dir / "stimuli/initial_dram.txt", DRAM_mem, fmt='%01X', delimiter=' ')
    np.savetxt(test_dir / "stimuli/gold_dram.txt", DRAM_mem_gold, fmt='%01X', delimiter=' ')
    
    # Generate and save test config file 
    np.savetxt(test_dir / "stimuli/tstcfg.txt", np.array(testcfg_list), fmt='%01X', delimiter=' ')

    # Remove previous outputs to raise an error in case nothing is produced
    # No error if files do not exist
    try:
        (test_dir / "outputs/test_results.txt").unlink()
    except OSError:
        pass
    try:
        (test_dir / "outputs/test_stats.txt").unlink()
    except OSError:
        pass

# ---------------------------------------
# OUTPUT FILE PARSING
# ---------------------------------------

def parse_test_outputs(HOPTS, tensor_size, test_dir="../../test"):

    test_dir = resolve_test_dir(test_dir)

    # Read tensor outputs
    raw_outputs = np.atleast_1d(np.loadtxt(test_dir / "outputs/test_results.txt", dtype=str))

    # Verilator may omit the initial address marker when $writememh writes a
    # contiguous range. Only discard a token when it is actually an address.
    if raw_outputs.size > 0 and raw_outputs[0].startswith('@'):
        raw_outputs = raw_outputs[1:]

    # Transform strings into 8b integer values
    out_bytes = np.array([int(x,16) for x in raw_outputs])

    # Cap data to total tensor size (usually there is some padding)
    N_bytes = int(np.ceil(HOPTS['OC_W']/8))
    expected_bytes = tensor_size*N_bytes
    if out_bytes.size < expected_bytes:
        raise ValueError(
            f"test_results.txt contains {out_bytes.size} output bytes; "
            f"expected at least {expected_bytes} for {tensor_size} values"
        )
    out_bytes = out_bytes[:expected_bytes]

    # Join bytes into words (values) - WARNING - We assume words are multiples of 8b!!!!
    out_values = np.zeros(int(out_bytes.size//N_bytes),dtype=np.int64)

    for i in range(N_bytes):
        out_values += (out_bytes[i::N_bytes] << 8*(i))

    # Integer outputs are two's-complement words. Convert them to signed
    # values before comparing with the Python convolution reference.
    if HOPTS['OP_TYPE'] == 0:
        sign_bit = 1 << (HOPTS['OC_W'] - 1)
        word_mask = (1 << HOPTS['OC_W']) - 1
        out_values &= word_mask
        out_values[out_values >= sign_bit] -= 1 << HOPTS['OC_W']

    # Read statistics outputs
    stats_outputs = np.atleast_1d(np.loadtxt(test_dir / "outputs/test_stats.txt", dtype=int))
    if stats_outputs.size < 4:
        raise ValueError(
            f"test_stats.txt contains {stats_outputs.size} values; expected at least 4"
        )
    stats_dict = {
        '1tile_SAURIA_cycles'   :   stats_outputs[0],
        '1tile_SAURIA_stalls'   :   stats_outputs[1],
        'sim_time'              :   stats_outputs[2]
    }

    n_test_errors = stats_outputs[3]

    return out_values, stats_dict, n_test_errors
