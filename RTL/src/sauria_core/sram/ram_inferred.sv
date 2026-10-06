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

// --------------------
// MODULE DECLARATION
// --------------------

module ram_inferred #(
    parameter ADR_W = 10,
    parameter SRAM_W = 128
)(
    // Clk, RST
	input  logic 				        i_clk,
	input  logic					    i_rstn,

    // Inputs
    input  logic                        i_cen,
    input  logic                        i_rdwen,
    input  logic [ADR_W-1:0]            i_addr,
    input  logic [SRAM_W-1:0]           i_indata,
    input  logic [SRAM_W-1:0]           i_wmask,

    // Outputs
    output logic [SRAM_W-1:0]           o_outdata

);

// ----------
// SIGNALS
// ----------

logic [SRAM_W-1:0] mem [(2**ADR_W)-1:0];

`ifdef POWER_ACTIVITY
integer power_debug_events = 0;
`endif

// ----------
// RAM
// ----------

always @(posedge i_clk) begin: ram
    
    // Active-low Chip Enable
    if (!i_cen) begin

`ifdef POWER_ACTIVITY
        if (power_debug_events < 8) begin
            if (!i_rdwen)
                $display("SRAM_MODEL_WRITE module=ram_inferred addr=%0d mask=%0h data=%0h", i_addr, i_wmask, i_indata);
            else
                $display("SRAM_MODEL_READ module=ram_inferred addr=%0d data=%0h", i_addr, mem[i_addr]);
            power_debug_events = power_debug_events + 1;
        end
`endif

        // Write (active low)
        if (!i_rdwen) begin
            
            // Bitwise mask
            for (integer i=0; i < SRAM_W; i += 8) begin
                if (i_wmask[i]) begin
                    mem[i_addr][i +: 8] <= i_indata[i +: 8];
                end
            end

        // Read
        end else begin
            o_outdata <= mem[i_addr];
        end
    end
end

endmodule 
