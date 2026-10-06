// Simulation models for the SRAM specializations emitted in the int16 6x6
// gate netlist. The two SAURIA SRAM interface widths are 96 bits, but the
// adapter packs four words into a 384-bit physical SRAM row.

// SRAMA and SRAMB: 11-bit logical addresses / 4 words per physical row.
// The synthesized physical address is 9 bits (512 rows).
module ram_inferred (
    input  logic         i_clk,
    input  logic         i_rstn,
    input  logic         i_cen,
    input  logic         i_rdwen,
    input  logic [8:0]   i_addr,
    input  logic [383:0] i_indata,
    input  logic [383:0] i_wmask,
    output logic [383:0] o_outdata
);
    logic [383:0] mem [0:511];

    always @(posedge i_clk) begin
        if (!i_cen) begin
            if (!i_rdwen) begin
                for (integer bit_idx = 0; bit_idx < 384; bit_idx += 8) begin
                    if (i_wmask[bit_idx])
                        mem[i_addr][bit_idx +: 8] <= i_indata[bit_idx +: 8];
                end
            end else begin
                o_outdata <= mem[i_addr];
            end
        end
    end
endmodule

// SRAMC: 10-bit logical addresses / 4 words per physical row.
// The synthesized physical address is 8 bits (256 rows).
module ram_inferred_0 (
    input  logic         i_clk,
    input  logic         i_rstn,
    input  logic         i_cen,
    input  logic         i_rdwen,
    input  logic [7:0]   i_addr,
    input  logic [383:0] i_indata,
    input  logic [383:0] i_wmask,
    output logic [383:0] o_outdata
);
    logic [383:0] mem [0:255];

    always @(posedge i_clk) begin
        if (!i_cen) begin
            if (!i_rdwen) begin
                for (integer bit_idx = 0; bit_idx < 384; bit_idx += 8) begin
                    if (i_wmask[bit_idx])
                        mem[i_addr][bit_idx +: 8] <= i_indata[bit_idx +: 8];
                end
            end else begin
                o_outdata <= mem[i_addr];
            end
        end
    end
endmodule
