`timescale 1ns/1ps

module tb;
    localparam int CFG_W = 32;
    localparam int MEM_W = 100;
    localparam int SRAM_W = 120;
    localparam int LANES = 6;
    localparam int WORD_BITS = 20;
    localparam int CFG_WORDS = 22;
    localparam int IFMAP_WORDS = (16*34*34 + LANES - 1) / LANES;
    localparam int WEIGHT_WORDS = (16*16*3*3 + LANES - 1) / LANES;
    localparam int OUTPUT_WORDS = (16*32*32 + LANES - 1) / LANES;
    localparam int OUTPUT_VALUES = 16*32*32;
    localparam int MAX_LAYER_CYCLES = 2000000;

    logic clk = 1'b0;
    logic rstn = 1'b0;
    logic [CFG_W-1:0] cfg_data = '0;
    logic [31:0] cfg_addr = '0;
    logic cfg_wren = 1'b0;
    logic cfg_rden = 1'b0;
    logic [CFG_W-1:0] cfg_wmask = '1;
    wire [CFG_W-1:0] cfg_rdata;
    logic [MEM_W-1:0] mem_data = '0;
    logic [31:0] mem_addr = '0;
    logic mem_wren = 1'b0;
    logic mem_rden = 1'b0;
    logic [MEM_W-1:0] mem_wmask = '1;
    wire [MEM_W-1:0] mem_rdata;
    wire doneintr;

    logic [63:0] config_words [0:CFG_WORDS-1];
    logic [SRAM_W-1:0] ifmap_words [0:IFMAP_WORDS-1];
    logic [SRAM_W-1:0] weight_words [0:WEIGHT_WORDS-1];
    logic [SRAM_W-1:0] psum_words [0:OUTPUT_WORDS-1];
    logic [WORD_BITS-1:0] golden [0:OUTPUT_VALUES-1];

    integer idx;
    integer cycles;
    integer fd;
    integer errors;
    logic [SRAM_W-1:0] read_word;
    logic [WORD_BITS-1:0] actual;
    logic [63:0] checksum;
    realtime layer_start_ns;

    always #1ns clk = ~clk;

    // Trace the first output-SRAM commits to verify the PSM's lane mapping on
    // the non-power-of-two 6x6 configuration.
    always @(posedge clk) begin
        if (rstn && dut.sauria_logic_i.o_sramc_wren &&
            (dut.sauria_logic_i.o_sramc_addr < 12)) begin
            $display("PSM_WRITE addr=%0d mask=%b rows_active=%b cols_active=%b array=%030x fifo=%030x mask_q=%b wdata=%030x",
                dut.sauria_logic_i.o_sramc_addr,
                dut.sauria_logic_i.o_sramc_wmask,
                dut.sauria_logic_i.af_rows_active,
                dut.sauria_logic_i.wf_cols_active,
                dut.sauria_logic_i.ob_c_arr,
                dut.sauria_logic_i.psm_top_i.buff_dout,
                dut.sauria_logic_i.psm_top_i.mask,
                dut.sauria_logic_i.o_sramc_wdata);
        end
    end

    sauria_asic_top #(
        .CFG_W(CFG_W), .CFG_ADDR_W(32), .MEM_W(MEM_W), .MEM_ADDR_W(32)
    ) dut (
        .i_clk(clk), .i_rstn(rstn),
        .i_cfg_data(cfg_data), .i_cfg_addr(cfg_addr),
        .i_cfg_wren(cfg_wren), .i_cfg_rden(cfg_rden),
        .i_cfg_wmask(cfg_wmask), .o_cfg_data(cfg_rdata),
        .i_mem_data(mem_data), .i_mem_addr(mem_addr),
        .i_mem_wren(mem_wren), .i_mem_rden(mem_rden),
        .i_mem_wmask(mem_wmask), .o_mem_data(mem_rdata),
        .o_doneintr(doneintr)
    );

`ifdef XRUN
    initial begin
        $shm_open("dut.shm");
        $shm_probe(tb.dut, "ASM");
    end
`endif

    task automatic write_cfg(input logic [31:0] address, input logic [31:0] value);
        begin
            @(negedge clk);
            cfg_addr = address;
            cfg_data = value;
            cfg_wren = 1'b1;
            @(negedge clk);
            cfg_wren = 1'b0;
            cfg_addr = '0;
            cfg_data = '0;
        end
    endtask

    task automatic write_sram_word(
        input logic [31:0] base,
        input integer word_index,
        input logic [SRAM_W-1:0] value
    );
        integer part;
        begin
            for (part = 0; part < 2; part = part + 1) begin
                @(negedge clk);
                mem_addr = base | ((word_index*2 + part) << 4);
                mem_data = '0;
                if (part == 0) mem_data = value[99:0];
                else            mem_data = value[119:100];
                mem_wren = 1'b1;
                @(negedge clk);
                mem_wren = 1'b0;
                if (word_index == 0 && base == 32'h0004_0000) begin
                    $display("HOST_WRITE base=%08x part=%0d addr=%08x local=%08x select=%b chunk=%b phys_addr=%08x phys_data=%030x phys_wmask=%030x bank0=%030x bank1=%030x",
                        base, part, mem_addr,
                        dut.sram_top_i.host_local_address,
                        dut.sram_top_i.SRAMA_i.host_word_sel,
                        dut.sram_top_i.SRAMA_i.i_select,
                        dut.sram_top_i.SRAMA_i.host_phys_addr,
                        dut.sram_top_i.SRAMA_i.host_phys_data,
                        dut.sram_top_i.SRAMA_i.host_phys_wmask,
                        dut.sram_top_i.SRAMA_i.sram_0_i.mem[0],
                        dut.sram_top_i.SRAMA_i.sram_1_i.mem[0]);
                end
            end
        end
    endtask

    task automatic read_sram_word(
        input logic [31:0] base,
        input integer word_index,
        output logic [SRAM_W-1:0] value
    );
        logic [MEM_W-1:0] low_part;
        logic [MEM_W-1:0] high_part;
        integer part;
        begin
            low_part = '0;
            high_part = '0;
            for (part = 0; part < 2; part = part + 1) begin
                @(negedge clk);
                mem_addr = base | ((word_index*2 + part) << 4);
                mem_rden = 1'b1;
                @(negedge clk);
                // SRAM output and sram_top's host output are both registered.
                @(negedge clk);
                mem_rden = 1'b0;
                if (part == 0) low_part = mem_rdata;
                else            high_part = mem_rdata;
            end
            value = {high_part[19:0], low_part[99:0]};
        end
    endtask

    initial begin
        $readmemh("vectors/config.mem", config_words);
        $readmemh("vectors/ifmap.mem", ifmap_words);
        $readmemh("vectors/weights.mem", weight_words);
        $readmemh("vectors/psum_init.mem", psum_words);
        $readmemh("vectors/golden.mem", golden);

        repeat (10) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;
        repeat (4) @(posedge clk);

        // Load local SRAMs through the shared 100-bit host port. The 120-bit
        // SRAM words are transferred as a 100-bit low part plus a 20-bit tail.
        for (idx = 0; idx < IFMAP_WORDS; idx = idx + 1)
            write_sram_word(32'h0004_0000, idx, ifmap_words[idx]);
        for (idx = 0; idx < WEIGHT_WORDS; idx = idx + 1)
            write_sram_word(32'h0008_0000, idx, weight_words[idx]);
        for (idx = 0; idx < OUTPUT_WORDS; idx = idx + 1)
            write_sram_word(32'h000C_0000, idx, psum_words[idx]);

        read_sram_word(32'h0004_0000, 0, read_word);
        $display("HOST_READBACK_IFMAP=%030x EXPECTED=%030x", read_word, ifmap_words[0]);
        if (read_word !== ifmap_words[0]) $fatal(1, "IFMAP SRAM host round-trip failed");
        read_sram_word(32'h0008_0000, 0, read_word);
        $display("HOST_READBACK_WEIGHTS=%030x EXPECTED=%030x", read_word, weight_words[0]);
        if (read_word !== weight_words[0]) $fatal(1, "weights SRAM host round-trip failed");
        read_sram_word(32'h000C_0000, 0, read_word);
        $display("HOST_READBACK_OUTPUT=%030x EXPECTED=%030x", read_word, psum_words[0]);
        if (read_word !== psum_words[0]) $fatal(1, "output SRAM host round-trip failed");

        for (idx = 0; idx < CFG_WORDS; idx = idx + 1)
            write_cfg(config_words[idx][63:32], config_words[idx][31:0]);

        $display("CONFIG_ACTIVE rows=%b cols=%b cxlim=%0d cxstep=%0d ck_lim=%0d ckstep=%0d ncontexts=%0d",
            dut.sauria_logic_i.af_rows_active,
            dut.sauria_logic_i.wf_cols_active,
            dut.sauria_logic_i.ob_cxlim,
            dut.sauria_logic_i.ob_cxstep,
            dut.sauria_logic_i.ob_cklim,
            dut.sauria_logic_i.ob_ckstep,
            dut.sauria_logic_i.ob_ncontexts);

        // The top-level done interrupt is gated by both interrupt enables.
        write_cfg(32'h5000_0004, 32'h0000_0001);
        write_cfg(32'h5000_0008, 32'h0000_0001);

        // Configuration and SRAM preload are complete before the layer window.
        @(negedge clk);
        cfg_addr = 32'h5000_0000;
        cfg_data = 32'h0000_0001;
        cfg_wren = 1'b1;
        @(posedge clk);
        layer_start_ns = $realtime;
        $display("LAYER_START_NS=%0.3f", layer_start_ns);
        fd = $fopen("layer_window.txt", "w");
        if (fd == 0) $fatal(1, "cannot create layer_window.txt");
        $fdisplay(fd, "%0.3f", layer_start_ns);
        $fclose(fd);
        @(negedge clk);
        cfg_wren = 1'b0;
        cfg_addr = '0;
        cfg_data = '0;

        cycles = 0;
        while ((doneintr !== 1'b1) && (cycles < MAX_LAYER_CYCLES)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (doneintr !== 1'b1) $fatal(1, "layer timed out after %0d cycles", cycles);
        $display("LAYER_END_NS=%0.3f", $realtime);
        $display("LAYER_CYCLES=%0d", cycles);

`ifndef POWER_ACTIVITY
        $display("SRAM_SELECT=%b", dut.sauria_logic_i.o_sram_select);
        $display("IFMAP bank0[0]=%030x bank1[0]=%030x expected=%030x",
            dut.sram_top_i.SRAMA_i.sram_0_i.mem[0],
            dut.sram_top_i.SRAMA_i.sram_1_i.mem[0], ifmap_words[0]);
        $display("WEIGHTS bank0[0]=%030x bank1[0]=%030x expected=%030x",
            dut.sram_top_i.SRAMB_i.sram_0_i.mem[0],
            dut.sram_top_i.SRAMB_i.sram_1_i.mem[0], weight_words[0]);
        $display("OUTPUT bank0[0]=%030x bank1[0]=%030x",
            dut.sram_top_i.SRAMC_i.sram_0_i.mem[0],
            dut.sram_top_i.SRAMC_i.sram_1_i.mem[0]);

        // Switch the output SRAM back to the host side and verify every value.
        write_cfg(32'h5000_0000, 32'h0000_0000);
        write_cfg(32'h5000_0000, 32'h0001_0000);
        repeat (5) @(posedge clk);
        errors = 0;
        checksum = 64'hcbf29ce484222325;
        fd = $fopen("run_artifacts/rtl-ac1d170-output-readback.mem", "w");
        if (fd == 0) $fatal(1, "cannot create output readback dump");
        for (idx = 0; idx < OUTPUT_WORDS; idx = idx + 1) begin
            read_sram_word(32'h000C_0000, idx, read_word);
            $fdisplay(fd, "%030x", read_word);
            for (integer lane = 0; lane < LANES; lane = lane + 1) begin
                integer out_idx;
                out_idx = idx*LANES + lane;
                if (out_idx < OUTPUT_VALUES) begin
                    actual = read_word[lane*WORD_BITS +: WORD_BITS];
                    if (actual !== golden[out_idx]) begin
                        if (errors < 10)
                            $display("MISMATCH[%0d]: got %05x expected %05x", out_idx, actual, golden[out_idx]);
                        errors = errors + 1;
                    end
                    for (integer byte_idx = 0; byte_idx < 3; byte_idx = byte_idx + 1)
                        checksum = (checksum ^ ((actual >> (8*byte_idx)) & 8'hff)) * 64'h100000001b3;
                end
            end
        end
        $fclose(fd);
        if (errors != 0) $fatal(1, "direct-convolution golden mismatch: %0d outputs", errors);
        $display("OUTPUTS_CHECKED=%0d", OUTPUT_VALUES);
        $display("OUTPUT_FNV1A64=%016x", checksum);
`endif

        $finish;
    end
endmodule
