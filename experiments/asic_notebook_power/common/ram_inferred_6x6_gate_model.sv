// Functional model for the parameter-specialized SRAM cells in the 6x6
// mapped netlist. All three SAURIA SRAM banks have 96-bit words; the widest
// address port is 11 bits (2048 words). SRAM C drives only 10 address bits.
module ram_inferred_0 (
    input  logic         i_clk,
    input  logic         i_rstn,
    input  logic         i_cen,
    input  logic         i_rdwen,
    input  logic [10:0]  i_addr,
    input  logic [95:0]  i_indata,
    input  logic [95:0]  i_wmask,
    output logic [95:0]  o_outdata
);
    logic [95:0] mem [0:2047];
    integer power_debug_events = 0;

    always_ff @(posedge i_clk) begin
        if (!i_cen) begin
            if (power_debug_events < 8) begin
                if (!i_rdwen)
                    $display("SRAM_MODEL_WRITE module=ram_inferred_0 addr=%0d mask=%0h data=%0h", i_addr, i_wmask, i_indata);
                else
                    $display("SRAM_MODEL_READ module=ram_inferred_0 addr=%0d data=%0h", i_addr, mem[i_addr]);
                power_debug_events <= power_debug_events + 1;
            end
            if (!i_rdwen) begin
                for (integer bit_idx = 0; bit_idx < 96; bit_idx += 8) begin
                    if (i_wmask[bit_idx])
                        mem[i_addr][bit_idx +: 8] <= i_indata[bit_idx +: 8];
                end
            end else begin
                o_outdata <= mem[i_addr];
            end
        end
    end
endmodule
