// Functional gate-simulation models for Genus-specialized inferred SRAMs.
// The RAM wrapper packs logical SA words into the 128-bit host interface, so
// the physical width is lcm(128, 16*array_size). The square INT16 profiles use
// the same lane count for activation, weight, and partial-sum memories.
package sauria_gate_ram_math;
    function automatic integer gcd(input integer lhs, input integer rhs);
        integer a, b, remainder;
        begin
            a = lhs;
            b = rhs;
            while (b != 0) begin
                remainder = a % b;
                a = b;
                b = remainder;
            end
            return a;
        end
    endfunction

    function automatic integer lcm(input integer lhs, input integer rhs);
        return (lhs / gcd(lhs, rhs)) * rhs;
    endfunction

    function automatic integer clog2(input integer value);
        integer v;
        begin
            v = value - 1;
            clog2 = 0;
            while (v > 0) begin
                clog2++;
                v >>= 1;
            end
            if (clog2 == 0) clog2 = 1;
        end
    endfunction
endpackage

module ram_inferred #(
    parameter integer SRAM_W = sauria_gate_ram_math::lcm(128, 16*`X),
    parameter integer ADR_W = sauria_gate_ram_math::clog2(
        (2048 + (SRAM_W/(16*`X)) - 1) / (SRAM_W/(16*`X)))
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
    logic [SRAM_W-1:0] mem [0:(1<<ADR_W)-1];

    always @(posedge i_clk) begin
        if (!i_cen) begin
            if (!i_rdwen) begin
                for (integer bit_idx = 0; bit_idx < SRAM_W; bit_idx += 8) begin
                    if (i_wmask[bit_idx])
                        mem[i_addr][bit_idx +: 8] <= i_indata[bit_idx +: 8];
                end
            end else begin
                o_outdata <= mem[i_addr];
            end
        end
    end
endmodule

module ram_inferred_0 #(
    parameter integer SRAM_W = sauria_gate_ram_math::lcm(128, 16*`X),
    parameter integer ADR_W = sauria_gate_ram_math::clog2(
        (1024 + (SRAM_W/(16*`X)) - 1) / (SRAM_W/(16*`X)))
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
    logic [SRAM_W-1:0] mem [0:(1<<ADR_W)-1];

    always @(posedge i_clk) begin
        if (!i_cen) begin
            if (!i_rdwen) begin
                for (integer bit_idx = 0; bit_idx < SRAM_W; bit_idx += 8) begin
                    if (i_wmask[bit_idx])
                        mem[i_addr][bit_idx +: 8] <= i_indata[bit_idx +: 8];
                end
            end else begin
                o_outdata <= mem[i_addr];
            end
        end
    end
endmodule
