// Copyright 2023 Barcelona Supercomputing Center (BSC)
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Licensed under the Solderpad Hardware License v 2.1 (the “License”);
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at

// https://solderpad.org/licenses/SHL-2.1/

// Unless required by applicable law or agreed to in writing, any work
// distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

// 8x8 systolic array with signed 16-bit integer operands and partial sums.
`define X   8
`define Y   8

`define ARITHMETIC   0
`define IA_W   16
`define IB_W   16
`define OC_W   16

// FP arithmetic definitions (unused for integer arithmetic).
`define FP_W    0
`define MANT_W  0

// Memory configuration
`define SRAMA_DEPTH     2048
`define RF_A            0
`define SRAMB_DEPTH     2048
`define RF_B            1
`define SRAMC_DEPTH     1024
`define RF_C            0

// Memory subsystem and bandwidth configuration
`define AXI_NOC_DATA_WIDTH  1024
`define DRAM_BANDWIDTH      160
`define DRAM_LATENCY        100

// PE configuration
`define STAGES_MUL   0
`define INTERMEDIATE_PIPELINE_STAGE   1

// Feeders configuration
`define M   3
`define ACT_FIFO_POSITIONS   5
`define WEI_FIFO_POSITIONS   4

// Exact integer arithmetic
`define MUL_TYPE   0
`define M_APPROX   0
`define MM_APPROX  0
`define ADD_TYPE   0
`define A_APPROX   0
`define AA_APPROX  0
