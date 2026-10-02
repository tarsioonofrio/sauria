// SAURIA 6x6 array with exact signed 20-bit integer arithmetic.

`define X   6
`define Y   6

`define ARITHMETIC  0
`define IA_W        20
`define IB_W        20
`define OC_W        20
`define FP_W        0
`define MANT_W      0

`define SRAMA_DEPTH 16384
`define RF_A        0
`define SRAMB_DEPTH 8192
`define RF_B        1
`define SRAMC_DEPTH 16384
`define RF_C        0

`define AXI_NOC_DATA_WIDTH 128
`define DRAM_BANDWIDTH     100
`define DRAM_LATENCY       100

`define STAGES_MUL                  0
`define INTERMEDIATE_PIPELINE_STAGE 1

`define M                  3
`define ACT_FIFO_POSITIONS 5
`define WEI_FIFO_POSITIONS 4

`define MUL_TYPE 0
`define M_APPROX 0
`define MM_APPROX 0
`define ADD_TYPE 0
`define A_APPROX 0
`define AA_APPROX 0
