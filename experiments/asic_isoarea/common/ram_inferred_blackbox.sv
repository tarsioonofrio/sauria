// Synthesis-only abstract view of SAURIA's inferred local SRAM.
// Functional simulation must use RTL/src/sauria_core/sram/ram_inferred.sv.
(* black_box = "true" *)
module ram_inferred #(
    parameter ADR_W = 10,
    parameter SRAM_W = 128
)(
    input  logic                 i_clk,
    input  logic                 i_rstn,
    input  logic                 i_cen,
    input  logic                 i_rdwen,
    input  logic [ADR_W-1:0]     i_addr,
    input  logic [SRAM_W-1:0]    i_indata,
    input  logic [SRAM_W-1:0]    i_wmask,
    output logic [SRAM_W-1:0]    o_outdata
);
endmodule
