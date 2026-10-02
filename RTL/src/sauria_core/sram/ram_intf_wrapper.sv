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

module ram_intf_wrapper #(
    parameter IF_W = 32,
    parameter IF_ADR_W = 32,
    parameter RF = 0,

    parameter ADR_W = 10,
    parameter SRAM_W = 128,
    parameter SRAM_N = 8
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

    // Power & sleep signals
    input logic                         i_deepsleep,        // Deep Sleep enable (global)
    input logic                         i_powergate,        // Power Gating (global)

    // Selection bit
    input  logic                        i_select,           // Double buffering selection signal

    // Host-side Interface
    input  logic [IF_W-1:0]             i_data,             // Input data bus from Host
    input  logic [IF_ADR_W-1:0]         i_address,          // Address from Host 
    input  logic                        i_wren,             // Wite enable from Host
    input  logic [IF_W-1:0]             i_wmask,           // Write mask bus
    input  logic                        i_rden,             // Read enable from Host 
	output logic [IF_W-1:0]             o_data_out,         // Output data bus towards Host

    // Accelerator-side Interface
    input  logic [SRAM_W-1:0]           i_sram_data,        // Input data bus from Accelerator
    input  logic [ADR_W-1:0]            i_sram_addr,        // Address from Accelerator
    input  logic [0:SRAM_N-1]           i_sram_wmask,       // Write Mask from Accelerator
    input  logic                        i_sram_wren,        // Write Enable from Accelerator
    input  logic                        i_sram_rden,        // Read Enable from Accelerator
    output logic [SRAM_W-1:0]           o_sram_data         // Output data bus towards Accelerator

);

// --------------------
// DERIVED PARAMETERS
// --------------------

localparam int ACTUAL_SRAM_W = `max2(IF_W, SRAM_W);

localparam int HOST_N = (ACTUAL_SRAM_W + IF_W - 1) / IF_W;
localparam int HOST_N_BITS = $clog2(HOST_N);
localparam bit HOST_REPACK_PARTIAL_BYTE =
    (SRAM_W > IF_W) && (IF_W % 8 != 0) && (HOST_N == 2);

localparam int ACCEL_N = (ACTUAL_SRAM_W + SRAM_W - 1) / SRAM_W;
localparam int ACCEL_N_BITS = $clog2(ACCEL_N);
localparam int ACCEL_WMASK_W = SRAM_W/SRAM_N;

localparam int ACTUAL_ADR_W = (SRAM_W>=IF_W)? ADR_W : ADR_W - $clog2(ACCEL_N);

localparam MEM_DEPTH = 2**ADR_W;

// ----------
// SIGNALS
// ----------

logic [SRAM_W-1:0]              sram_wmask_expanded;

// Accelerator-side - Signal adaptation
logic [ACTUAL_ADR_W-1:0]        accel_phys_addr;
logic [ACTUAL_SRAM_W-1:0]       accel_phys_data;
logic [ACTUAL_SRAM_W-1:0]       accel_phys_wmask;
logic [ACCEL_WMASK_W-1:0]       accel_word_sel, accel_word_sel_shim_q;
logic [0:ACCEL_N-1][SRAM_W-1:0] accel_rdata_elements;

// Host-side - Signal adaptation
logic [ACTUAL_ADR_W-1:0]        host_phys_addr;
logic [ACTUAL_SRAM_W-1:0]       host_phys_data;
logic [ACTUAL_SRAM_W-1:0]       host_phys_wmask;
logic [HOST_N_BITS-1:0]         host_word_sel, host_word_sel_shim_q;
logic [0:HOST_N-1][IF_W-1:0]    host_rdata_elements;

// Double-Buffering - SRAM signals selection
logic [ACTUAL_ADR_W-1:0]        addr_0, addr_1;
logic [ACTUAL_SRAM_W-1:0]       indata_0, indata_1;
logic [ACTUAL_SRAM_W-1:0]       wmask_0, wmask_1;
logic [ACTUAL_SRAM_W-1:0]       outdata_0, outdata_1;
logic                           rden_0, rden_1, wren_0, wren_1;
logic                           cen_0, cen_1, rdwen_0, rdwen_1;
logic [IF_W-1:0]                host_low_data_0_q, host_low_data_1_q;
logic [IF_W-1:0]                host_low_wmask_0_q, host_low_wmask_1_q;
logic [ACTUAL_ADR_W-1:0]        host_low_addr_0_q, host_low_addr_1_q;
logic                           host_low_valid_0_q, host_low_valid_1_q;

// Output data bus selection
logic [ACTUAL_SRAM_W-1:0]       host_outdata, accel_outdata;
logic [IF_W-1:0]                host_outdata_sel;
logic [SRAM_W-1:0]              accel_outdata_sel;

// ------------------------------------------------------------
// Host IO signals adaptation
// ------------------------------------------------------------

genvar i;
generate

    // ************************************************
    // IF SRAM INTERFACE IS LARGER THAN HOST INTERFACE
    // ************************************************
    if (SRAM_W>IF_W) begin

        // Addres lower bits select words from bus, upper bits select address
        assign host_word_sel =     i_address[HOST_N_BITS-1:0];
        assign host_phys_addr =    i_address[HOST_N_BITS+ACTUAL_ADR_W-1:HOST_N_BITS];

        for (i=0; i<HOST_N; i++) begin : host_signal_adapt
            localparam int HOST_CHUNK_W =
                (IF_W < ACTUAL_SRAM_W - IF_W*i) ? IF_W : ACTUAL_SRAM_W - IF_W*i;

            // The final transfer may be narrower than IF_W. Keep it
            // right-aligned on reads and store only its valid bits on writes.
            assign host_rdata_elements[i] =
                {{(IF_W-HOST_CHUNK_W){1'b0}}, host_outdata[IF_W*i+:HOST_CHUNK_W]};
            assign host_phys_data[IF_W*i+:HOST_CHUNK_W] = i_data[HOST_CHUNK_W-1:0];
            assign host_phys_wmask[IF_W*i+:HOST_CHUNK_W] =
                (host_word_sel == i) ? i_wmask[HOST_CHUNK_W-1:0] : '0;
        end

        // Word selection is applied to the output, so it needs 1 cycle of shimming
        always_ff @(posedge i_clk or negedge i_rstn) begin : outreg
            if(~i_rstn) begin
                host_word_sel_shim_q <= 0;
            end else if (i_rden) begin
                host_word_sel_shim_q <= host_word_sel;
            end
        end

        // Select output element according to word_sel
        assign host_outdata_sel = host_rdata_elements[host_word_sel_shim_q];

        // Connect accelerator interface normally
        assign accel_phys_addr =        i_sram_addr;
        assign accel_phys_data =        i_sram_data;
        assign accel_phys_wmask =       sram_wmask_expanded;
        assign accel_outdata_sel =      accel_outdata;

    // ******************************************************
    // IF SRAM INTERFACE IS SMALLER THAN HOST INTERFACE
    // ******************************************************
    end else if (SRAM_W<IF_W) begin

        // Connect host interface normally
        assign host_phys_addr =     i_address;
        assign host_phys_data =     i_data;
        assign host_phys_wmask =    i_wmask;
        assign host_outdata_sel =   host_outdata;

        // Addres lower bits select words from bus, upper bits select address
        assign accel_word_sel =     i_sram_addr[ACCEL_N_BITS-1:0];
        assign accel_phys_addr =    i_sram_addr[ACCEL_N_BITS+ACTUAL_ADR_W-1:ACCEL_N_BITS];

        for (i=0; i<ACCEL_N; i++) begin : accel_signal_adapt
            localparam int ACCEL_CHUNK_W =
                (SRAM_W < ACTUAL_SRAM_W - SRAM_W*i) ? SRAM_W : ACTUAL_SRAM_W - SRAM_W*i;

            // The final element may be narrower than SRAM_W. Right-align it
            // on reads and adapt only the valid low bits on writes.
            assign accel_rdata_elements[i] =
                {{(SRAM_W-ACCEL_CHUNK_W){1'b0}}, accel_outdata[SRAM_W*i+:ACCEL_CHUNK_W]};
            assign accel_phys_data[SRAM_W*i+:ACCEL_CHUNK_W] =
                i_sram_data[ACCEL_CHUNK_W-1:0];
            assign accel_phys_wmask[SRAM_W*i+:ACCEL_CHUNK_W] =
                (accel_word_sel == i) ? sram_wmask_expanded[ACCEL_CHUNK_W-1:0] : '0;
        end

        // Word selection is applied to the output, so it needs 1 cycle of shimming
        always_ff @(posedge i_clk or negedge i_rstn) begin : accel_outreg
            if(~i_rstn) begin
                accel_word_sel_shim_q <= 0;
            end else if (i_sram_rden) begin
                accel_word_sel_shim_q <= accel_word_sel;
            end
        end

        // Select output element according to word_sel
        assign accel_outdata_sel = accel_rdata_elements[accel_word_sel_shim_q];

    // ******************************************************
    // IF SRAM INTERFACE AND HOST INTERFACE HAVE SAME SIZE
    // ******************************************************
    end else if (SRAM_W==IF_W) begin
        
        // Just connect everything normally
        assign host_phys_addr =         i_address;
        assign host_phys_data =         i_data;
        assign host_phys_wmask =        i_wmask;
        assign host_outdata_sel =       host_outdata;

        assign accel_phys_addr =        i_sram_addr;
        assign accel_phys_data =        i_sram_data;
        assign accel_phys_wmask =       sram_wmask_expanded;
        assign accel_outdata_sel =      accel_outdata;

    end

endgenerate

// ------------------------------------------------------------
// Accelerator IO signals adaptation
// ------------------------------------------------------------

// Extend bitmask bits
genvar j;
generate
    for (j=0; j<SRAM_N; j++) begin : accel_signal_adapt

        // Copy bitmask bit to all bits of element pointed to
        assign sram_wmask_expanded[ACCEL_WMASK_W*j+:ACCEL_WMASK_W] = {ACCEL_WMASK_W{i_sram_wmask[j]}};

    end
endgenerate

// ------------------------------------------------------------
// Input signals multiplexing
// ------------------------------------------------------------

assign rden_0 =     (i_select)?  i_sram_rden : i_rden;
assign rden_1 =     (!i_select)?  i_sram_rden : i_rden;

generate
    if (HOST_REPACK_PARTIAL_BYTE) begin : host_partial_byte_repack
        always_ff @(posedge i_clk or negedge i_rstn) begin
            if (!i_rstn) begin
                host_low_valid_0_q <= 1'b0;
                host_low_valid_1_q <= 1'b0;
                host_low_data_0_q <= '0;
                host_low_data_1_q <= '0;
                host_low_wmask_0_q <= '0;
                host_low_wmask_1_q <= '0;
                host_low_addr_0_q <= '0;
                host_low_addr_1_q <= '0;
            end else begin
                if (i_wren && !i_select) begin
                    if (host_word_sel == 0) begin
                        host_low_data_0_q <= host_phys_data[IF_W-1:0];
                        host_low_wmask_0_q <= host_phys_wmask[IF_W-1:0];
                        host_low_addr_0_q <= host_phys_addr;
                        host_low_valid_0_q <= 1'b1;
                    end else if (host_word_sel == 1) begin
                        host_low_valid_0_q <= 1'b0;
                    end
                end

                if (i_wren && i_select) begin
                    if (host_word_sel == 0) begin
                        host_low_data_1_q <= host_phys_data[IF_W-1:0];
                        host_low_wmask_1_q <= host_phys_wmask[IF_W-1:0];
                        host_low_addr_1_q <= host_phys_addr;
                        host_low_valid_1_q <= 1'b1;
                    end else if (host_word_sel == 1) begin
                        host_low_valid_1_q <= 1'b0;
                    end
                end
            end
        end

        assign addr_0 = (i_select) ? accel_phys_addr : host_phys_addr;
        assign indata_0 = (i_select) ? accel_phys_data :
            {host_phys_data[ACTUAL_SRAM_W-1:IF_W], host_low_data_0_q};
        assign wmask_0 = (i_select) ? accel_phys_wmask :
            {host_phys_wmask[ACTUAL_SRAM_W-1:IF_W], host_low_wmask_0_q};
        assign wren_0 = (i_select) ? i_sram_wren :
            (i_wren && (host_word_sel == 1) && host_low_valid_0_q &&
             (host_low_addr_0_q == host_phys_addr));

        assign addr_1 = (!i_select) ? accel_phys_addr : host_phys_addr;
        assign indata_1 = (!i_select) ? accel_phys_data :
            {host_phys_data[ACTUAL_SRAM_W-1:IF_W], host_low_data_1_q};
        assign wmask_1 = (!i_select) ? accel_phys_wmask :
            {host_phys_wmask[ACTUAL_SRAM_W-1:IF_W], host_low_wmask_1_q};
        assign wren_1 = (!i_select) ? i_sram_wren :
            (i_wren && (host_word_sel == 1) && host_low_valid_1_q &&
             (host_low_addr_1_q == host_phys_addr));
    end else begin : host_direct_mapping
        assign addr_0 = (i_select) ? accel_phys_addr : host_phys_addr;
        assign indata_0 = (i_select) ? accel_phys_data : host_phys_data;
        assign wmask_0 = (i_select) ? accel_phys_wmask : host_phys_wmask;
        assign wren_0 = (i_select) ? i_sram_wren : i_wren;

        assign addr_1 = (!i_select) ? accel_phys_addr : host_phys_addr;
        assign indata_1 = (!i_select) ? accel_phys_data : host_phys_data;
        assign wmask_1 = (!i_select) ? accel_phys_wmask : host_phys_wmask;
        assign wren_1 = (!i_select) ? i_sram_wren : i_wren;
    end
endgenerate

// ------------------------------------------------------------
// Output signals multiplexing
// ------------------------------------------------------------

assign accel_outdata = (i_select)? outdata_0 : outdata_1;
assign host_outdata = (!i_select)? outdata_0 : outdata_1;

// ------------------------------------------------------------
// Chip enable & read/write logic
// ------------------------------------------------------------

assign cen_0 = !(rden_0 | wren_0);  // ACTIVE LOW!!
assign cen_1 = !(rden_1 | wren_1);  // ACTIVE LOW!!

assign rdwen_0 = !(wren_0);
assign rdwen_1 = !(wren_1);

// ------------------------------------------------------------
// Outputs
// ------------------------------------------------------------

assign o_sram_data = accel_outdata_sel;
assign o_data_out = host_outdata_sel;

// ------------------------------------------------------------
// Submodules instantiation
// ------------------------------------------------------------

// SRAM 0
ram_inferred#(
    .ADR_W(ACTUAL_ADR_W),
    .SRAM_W(ACTUAL_SRAM_W)
) sram_0_i
        (.i_clk          (i_clk),
        .i_rstn         (i_rstn),
        .i_cen          (cen_0),
        .i_rdwen        (rdwen_0),
        .i_addr         (addr_0),
        .i_indata       (indata_0),
        .i_wmask        (wmask_0),
        .o_outdata      (outdata_0));

// SRAM 1
ram_inferred#(
    .ADR_W(ACTUAL_ADR_W),
    .SRAM_W(ACTUAL_SRAM_W)
) sram_1_i
        (.i_clk         (i_clk),
        .i_rstn         (i_rstn),
        .i_cen          (cen_1),
        .i_rdwen        (rdwen_1),
        .i_addr         (addr_1),
        .i_indata       (indata_1),
        .i_wmask        (wmask_1),
        .o_outdata      (outdata_1));

endmodule 
