// Copyright 2023 Barcelona Supercomputing Center (BSC)
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

// Licensed under the Solderpad Hardware License v 2.1 (the “License”);
// you may not use this file except in compliance with the License, or,
// at your option, the Apache License version 2.0.
// You may obtain a copy of the License at

// https://solderpad.org/licenses/SHL-2.1/

// Unless required by applicable law or agreed to in writing, any work
// distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations
// under the License.

//
// Jordi Fornt <jfornt@bsc.es>

// ----------
// MACROS
// ----------

// Macro for MAX of 2 parameters
`define max2(a,b)  ((a) > (b) ? (a) : (b))

// --------------------
// MODULE DECLARATION
// --------------------

module sram_top #(
    parameter IF_W = 32,
    parameter IF_ADR_W = 32,
    parameter ADRA_W = 10,
    parameter SRAMA_W = 128,
    parameter RF_A = 0,
    parameter ADRB_W = 10,
    parameter SRAMB_W = 128,
    parameter RF_B = 0,
    parameter ADRC_W = 10,
    parameter SRAMC_W = 128,
    parameter RF_C = 0,

    parameter SRAMC_N = 8,
    parameter EXTENDED_HOST_MAP = 0
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

    // Power & sleep signals
    input logic                         i_deepsleep,        // Deep Sleep enable (global)
    input logic                         i_powergate,        // Power Gating (global)

    // Selection bit
    input  logic [0:2]                  i_select,           // Double buffering selection signal

    // Host-side Interface
    input  logic [IF_W-1:0]             i_data,             // Input data bus from Host
    input  logic [IF_ADR_W-1:0]         i_address,          // Address from Host 
    input  logic                        i_wren,             // Wite enable from Host
    input  logic [IF_W-1:0]             i_wmask,           // Write mask bus
    input  logic                        i_rden,             // Read enable from Host 
	output logic [IF_W-1:0]             o_data_out,         // Output data bus towards Host

    // Accelerator-side Interface (SRAMA)
    input  logic [ADRA_W-1:0]           i_srama_addr,        // Address from Accelerator
    input  logic                        i_srama_rden,        // Read Enable from Accelerator
    output logic [SRAMA_W-1:0]          o_srama_data,        // Output data bus towards Accelerator

    // Accelerator-side Interface (SRAMB)
    input  logic [ADRB_W-1:0]           i_sramb_addr,        // Address from Accelerator
    input  logic                        i_sramb_rden,        // Read Enable from Accelerator
    output logic [SRAMB_W-1:0]          o_sramb_data,        // Output data bus towards Accelerator

    // Accelerator-side Interface (SRAMC)
    input  logic [SRAMC_W-1:0]          i_sramc_data,        // Input data bus from Accelerator
    input  logic [ADRC_W-1:0]           i_sramc_addr,        // Address from Accelerator
    input  logic [0:SRAMC_N-1]          i_sramc_wmask,       // Write Mask from Accelerator
    input  logic                        i_sramc_wren,        // Write Enable from Accelerator
    input  logic                        i_sramc_rden,        // Read Enable from Accelerator
    output logic [SRAMC_W-1:0]          o_sramc_data         // Output data bus towards Accelerator

);

localparam IF_LSB_BITS = $clog2(IF_W/8);
localparam HOST_ADR_W = IF_ADR_W - IF_LSB_BITS;

// The host address carries both the global SRAM selection and the local
// offset. Strip the selection bits before handing the address to the SRAM
// adapters; otherwise non-power-of-two host widths can shift those global
// bits into the physical SRAM address when the adapter adds a chunk selector.
logic [HOST_ADR_W-1:0] host_local_address;
generate
    if (EXTENDED_HOST_MAP) begin : extended_host_address_map
        // Experimental ASIC wrapper map: the upper two address bits select
        // the SRAM bank, leaving the lower address range available for the
        // complete configured SRAM depth. The default map remains unchanged.
        assign host_local_address = i_address[29:IF_LSB_BITS];
    end else begin : standard_host_address_map
        assign host_local_address = i_address[IF_ADR_W-1:IF_LSB_BITS] &
                                    ~(sauria_addr_pkg::SAURIA_MEM_ADDR_MASK >> IF_LSB_BITS);
    end
endgenerate

// ----------
// SIGNALS
// ----------

// Host-side - Output Selection
logic [IF_ADR_W-1:0] host_sram_select_d, host_sram_select_q;
logic [IF_W-1:0]     host_srama_data, host_sramb_data, host_sramc_data;
logic [IF_W-1:0]     host_sram_output;

// Host-side - Read & Write Enables
logic               host_srama_rden, host_sramb_rden, host_sramc_rden;
logic               host_srama_wren, host_sramb_wren, host_sramc_wren;

// Output Registers
logic [IF_W-1:0]        host_sram_output_q;
logic [SRAMA_W-1:0]     srama_output_q, srama_output_d;
logic [SRAMB_W-1:0]     sramb_output_q, sramb_output_d;
logic [SRAMC_W-1:0]     sramc_output_q, sramc_output_d;

// ------------------------------------------------------------
// Host SRAM selection - Based on upper SRAM bits
// ------------------------------------------------------------

generate
    if (EXTENDED_HOST_MAP) begin : extended_host_bank_select
        always_comb begin
            case (i_address[31:30])
                2'd0: host_sram_select_d = sauria_addr_pkg::SRAMA_OFFSET;
                2'd1: host_sram_select_d = sauria_addr_pkg::SRAMB_OFFSET;
                2'd2: host_sram_select_d = sauria_addr_pkg::SRAMC_OFFSET;
                default: host_sram_select_d = '0;
            endcase
        end
    end else begin : standard_host_bank_select
        assign host_sram_select_d = i_address & sauria_addr_pkg::SAURIA_MEM_ADDR_MASK;
    end
endgenerate

always_comb begin : host_rd_wr_enables
    
    host_srama_wren = 0;
    host_srama_rden = 0;
    host_sramb_wren = 0;
    host_sramb_rden = 0;
    host_sramc_wren = 0;    
    host_sramc_rden = 0;
    host_sram_output = 32'h4BADADD2;

    // Inputs selected by input address
    // +++++++++++++++++++++++++++++++++

    // Offset = 1 selects SRAMA
    if (host_sram_select_d==sauria_addr_pkg::SRAMA_OFFSET) begin
        host_srama_wren = i_wren;
        host_srama_rden = i_rden;

    // Offset = 2 selects SRAMB
    end else if (host_sram_select_d==sauria_addr_pkg::SRAMB_OFFSET) begin
        host_sramb_wren = i_wren;
        host_sramb_rden = i_rden;

    // Offset = 3 selects SRAMC
    end else if (host_sram_select_d==sauria_addr_pkg::SRAMC_OFFSET) begin
        host_sramc_wren = i_wren;    
        host_sramc_rden = i_rden;
    end

    // Output selected by input address + 1 latency cycle
    // +++++++++++++++++++++++++++++++++++++++++++++++++++++

    // Offset = 1 selects SRAMA
    if (host_sram_select_q==sauria_addr_pkg::SRAMA_OFFSET) begin
        host_sram_output = host_srama_data;

    // Offset = 2 selects SRAMB
    end else if (host_sram_select_q==sauria_addr_pkg::SRAMB_OFFSET) begin
        host_sram_output = host_sramb_data;

    // Offset = 3 selects SRAMC
    end else if (host_sram_select_q==sauria_addr_pkg::SRAMC_OFFSET) begin
        host_sram_output = host_sramc_data;
    end

end

// ------------------------------------------------------------
// Output registers
// ------------------------------------------------------------

// Register
always_ff @(posedge i_clk or negedge i_rstn) begin : outreg
    if(~i_rstn) begin
        host_sram_select_q <= 0;
        host_sram_output_q <= 0;
        srama_output_q <= 0;
        sramb_output_q <= 0;
        sramc_output_q <= 0;
    end else begin

        if (i_rden) begin
            host_sram_select_q <= host_sram_select_d;
            host_sram_output_q <= host_sram_output;
        end

        if (i_srama_rden) begin
            srama_output_q <= srama_output_d;
        end

        if (i_sramb_rden) begin
            sramb_output_q <= sramb_output_d;
        end

        if (i_sramc_rden) begin
            sramc_output_q <= sramc_output_d;
        end
    end
end

assign o_data_out = host_sram_output_q;
assign o_srama_data = srama_output_q;
assign o_sramb_data = sramb_output_q;
assign o_sramc_data = sramc_output_q;

// ------------------------------------------------------------
// Submodules instantiation
// ------------------------------------------------------------

// SRAMA
ram_intf_wrapper #(
    .IF_W(IF_W),
    .IF_ADR_W(IF_ADR_W-IF_LSB_BITS),
    .ADR_W(ADRA_W),
    .SRAM_W(SRAMA_W),
    .RF(RF_A)
) SRAMA_i (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_deepsleep	(i_deepsleep),
        .i_powergate    (i_powergate),
        .i_select       (i_select[0]),
        .i_data         (i_data),
        .i_wmask        (i_wmask),
        .i_address      (host_local_address),
        .i_wren         (host_srama_wren),
        .i_rden         (host_srama_rden),
        .o_data_out     (host_srama_data),

        .i_sram_data	('0),
        .i_sram_addr    (i_srama_addr),
        .i_sram_wmask   ('0),
        .i_sram_wren    ('0),
        .i_sram_rden	(i_srama_rden),
        .o_sram_data    (srama_output_d));

// SRAMB
ram_intf_wrapper #(
    .IF_W(IF_W),
    .IF_ADR_W(IF_ADR_W-IF_LSB_BITS),
    .ADR_W(ADRB_W),
    .SRAM_W(SRAMB_W),
    .RF(RF_B)
) SRAMB_i (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_deepsleep	(i_deepsleep),
        .i_powergate    (i_powergate),
        .i_select       (i_select[1]),
        .i_data         (i_data),
        .i_wmask        (i_wmask),
        .i_address      (host_local_address),
        .i_wren         (host_sramb_wren),
        .i_rden         (host_sramb_rden),
        .o_data_out     (host_sramb_data),

        .i_sram_data	('0),
        .i_sram_addr    (i_sramb_addr),
        .i_sram_wmask   ('0),
        .i_sram_wren    ('0),
        .i_sram_rden	(i_sramb_rden),
        .o_sram_data    (sramb_output_d));

// SRAMC
ram_intf_wrapper #(
    .IF_W(IF_W),
    .IF_ADR_W(IF_ADR_W-IF_LSB_BITS),
    .ADR_W(ADRC_W),
    .SRAM_W(SRAMC_W),
    .SRAM_N(SRAMC_N),
    .RF(RF_C)
) SRAMC_i (
        .i_clk          (i_clk),
        .i_rstn         (i_rstn),
        
        .i_deepsleep	(i_deepsleep),
        .i_powergate    (i_powergate),
        .i_select       (i_select[2]),
        .i_data         (i_data),
        .i_wmask        (i_wmask),
        .i_address      (host_local_address),
        .i_wren         (host_sramc_wren),
        .i_rden         (host_sramc_rden),
        .o_data_out     (host_sramc_data),

        .i_sram_data	(i_sramc_data),
        .i_sram_addr    (i_sramc_addr),
        .i_sram_wmask   (i_sramc_wmask),
        .i_sram_wren    (i_sramc_wren),
        .i_sram_rden	(i_sramc_rden),
        .o_sram_data    (sramc_output_d));

endmodule 
