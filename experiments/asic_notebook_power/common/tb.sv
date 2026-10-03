`timescale 1ns/1ps

module tb;
    localparam int CFG_W = 32;
    localparam int MEM_W = 128;
    localparam int ADDR_W = 32;
    localparam int ARRAY_X = `X;
    localparam int ARRAY_Y = `Y;
    localparam int IA_W = `IA_W;
    localparam int IB_W = `IB_W;
    localparam int OC_W = `OC_W;
    localparam int SRAMA_W = ARRAY_Y * IA_W;
    localparam int SRAMB_W = ARRAY_X * IB_W;
    localparam int SRAMC_W = ARRAY_Y * OC_W;
    localparam int MAX_SRAM_WORD_W = (SRAMC_W > SRAMB_W) ? ((SRAMC_W > SRAMA_W) ? SRAMC_W : SRAMA_W) : ((SRAMB_W > SRAMA_W) ? SRAMB_W : SRAMA_W);
    localparam int MAX_VECTOR_WORDS = 16384;
    localparam int MAX_OUTPUT_VALUES = 262144;
    localparam int MAX_CONFIG_WORDS = 128;
    localparam int MEM_BYTE_SHIFT = 4;

    // Extended experimental map: upper address bits choose a bank, while
    // lower address bits span its full configured depth.
    localparam logic [31:0] SRAMA_BASE = 32'h0000_0000;
    localparam logic [31:0] SRAMB_BASE = 32'h4000_0000;
    localparam logic [31:0] SRAMC_BASE = 32'h8000_0000;

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

    logic [63:0] config_words [0:MAX_CONFIG_WORDS-1];
    logic [MAX_SRAM_WORD_W-1:0] ifmap_words [0:MAX_VECTOR_WORDS-1];
    logic [MAX_SRAM_WORD_W-1:0] weight_words [0:MAX_VECTOR_WORDS-1];
    logic [MAX_SRAM_WORD_W-1:0] psum_words [0:MAX_VECTOR_WORDS-1];
    logic [OC_W-1:0] golden [0:MAX_OUTPUT_VALUES-1];

    integer config_count;
    integer ifmap_count;
    integer weight_count;
    integer output_word_count;
    integer output_value_count;
    integer idx;
    integer part;
    integer cycles;
    integer errors;
    integer fd;
    integer scan_result;
    integer lane;
    integer byte_idx;
    integer max_cycles;
    logic [MAX_SRAM_WORD_W-1:0] read_word;
    logic [OC_W-1:0] actual;
    logic [63:0] checksum;
    realtime layer_start_ns;
    realtime layer_end_ns;

    always #1ns clk = ~clk;

    sauria_asic_top #(
        .CFG_W(CFG_W), .CFG_ADDR_W(32), .MEM_W(MEM_W), .MEM_ADDR_W(ADDR_W)
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

    task automatic write_local_word(
        input logic [31:0] base,
        input integer word_index,
        input integer sram_bits,
        input logic [MAX_SRAM_WORD_W-1:0] value
    );
        integer chunks;
        integer chunk;
        begin
            chunks = (sram_bits + MEM_W - 1) / MEM_W;
            for (chunk = 0; chunk < chunks; chunk = chunk + 1) begin
                @(negedge clk);
                mem_addr = base | ((word_index*chunks + chunk) << MEM_BYTE_SHIFT);
                mem_data = value >> (chunk*MEM_W);
                mem_wren = 1'b1;
                @(negedge clk);
                mem_wren = 1'b0;
            end
        end
    endtask

    task automatic read_local_word(
        input logic [31:0] base,
        input integer word_index,
        input integer sram_bits,
        output logic [MAX_SRAM_WORD_W-1:0] value
    );
        integer chunks;
        integer chunk;
        begin
            chunks = (sram_bits + MEM_W - 1) / MEM_W;
            value = '0;
            for (chunk = 0; chunk < chunks; chunk = chunk + 1) begin
                @(negedge clk);
                mem_addr = base | ((word_index*chunks + chunk) << MEM_BYTE_SHIFT);
                mem_rden = 1'b1;
                @(negedge clk);
                @(negedge clk);
                mem_rden = 1'b0;
                value[chunk*MEM_W +: MEM_W] = mem_rdata;
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("IFMAP_WORDS=%d", ifmap_count)) $fatal(1, "missing IFMAP_WORDS");
        if (!$value$plusargs("WEIGHT_WORDS=%d", weight_count)) $fatal(1, "missing WEIGHT_WORDS");
        if (!$value$plusargs("OUTPUT_WORDS=%d", output_word_count)) $fatal(1, "missing OUTPUT_WORDS");
        if (!$value$plusargs("OUTPUT_VALUES=%d", output_value_count)) $fatal(1, "missing OUTPUT_VALUES");
        if (!$value$plusargs("MAX_LAYER_CYCLES=%d", max_cycles)) max_cycles = 20000000;
        if (ifmap_count > MAX_VECTOR_WORDS || weight_count > MAX_VECTOR_WORDS || output_word_count > MAX_VECTOR_WORDS || output_value_count > MAX_OUTPUT_VALUES)
            $fatal(1, "generated workload exceeds testbench capacity");

        $readmemh("vectors/ifmap.mem", ifmap_words);
        $readmemh("vectors/weights.mem", weight_words);
        $readmemh("vectors/psum_init.mem", psum_words);
        $readmemh("vectors/golden.mem", golden);
        fd = $fopen("vectors/config.mem", "r");
        if (fd == 0) $fatal(1, "cannot open vectors/config.mem");
        config_count = 0;
        while (!$feof(fd) && config_count < MAX_CONFIG_WORDS) begin
            scan_result = $fscanf(fd, "%h", config_words[config_count]);
            if (scan_result == 1) config_count = config_count + 1;
        end
        $fclose(fd);
        if (config_count == 0 || config_count == MAX_CONFIG_WORDS)
            $fatal(1, "configuration register count is invalid: %0d", config_count);

        repeat (10) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;
        repeat (4) @(posedge clk);

        // Host loading is outside the measured layer window; compute-side SRAM
        // reads, feeder stalls, systolic execution and output commits stay inside.
        for (idx = 0; idx < ifmap_count; idx = idx + 1)
            write_local_word(SRAMA_BASE, idx, SRAMA_W, ifmap_words[idx]);
        for (idx = 0; idx < weight_count; idx = idx + 1)
            write_local_word(SRAMB_BASE, idx, SRAMB_W, weight_words[idx]);
        for (idx = 0; idx < output_word_count; idx = idx + 1)
            write_local_word(SRAMC_BASE, idx, SRAMC_W, psum_words[idx]);

`ifndef POWER_ACTIVITY
        read_local_word(SRAMA_BASE, 0, SRAMA_W, read_word);
        if (read_word[SRAMA_W-1:0] !== ifmap_words[0][SRAMA_W-1:0])
            $fatal(1, "IFMAP SRAM host round-trip failed");
        read_local_word(SRAMB_BASE, 0, SRAMB_W, read_word);
        if (read_word[SRAMB_W-1:0] !== weight_words[0][SRAMB_W-1:0])
            $fatal(1, "weight SRAM host round-trip failed");
        read_local_word(SRAMC_BASE, 0, SRAMC_W, read_word);
        if (read_word[SRAMC_W-1:0] !== psum_words[0][SRAMC_W-1:0])
            $fatal(1, "output SRAM host round-trip failed");
`endif

        for (idx = 0; idx < config_count; idx = idx + 1)
            write_cfg(config_words[idx][63:32], config_words[idx][31:0]);
        write_cfg(32'h5000_0004, 32'h0000_0001);
        write_cfg(32'h5000_0008, 32'h0000_0001);

        @(negedge clk);
        cfg_addr = 32'h5000_0000;
        cfg_data = 32'h0000_0001;
        cfg_wren = 1'b1;
        @(posedge clk);
        layer_start_ns = $realtime;
        fd = $fopen("layer_window.txt", "w");
        if (fd == 0) $fatal(1, "cannot create layer_window.txt");
        $fdisplay(fd, "%0.3f", layer_start_ns);
        $fclose(fd);
        $display("LAYER_START_NS=%0.3f", layer_start_ns);
        @(negedge clk);
        cfg_wren = 1'b0;
        cfg_addr = '0;
        cfg_data = '0;

        cycles = 0;
        while ((doneintr !== 1'b1) && (cycles < max_cycles)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (doneintr !== 1'b1) begin
            $display("DEBUG_TIMEOUT doneintr=%b mc_start=%b cg_done=%b ctx_status=%b feed_status=%b",
                doneintr, dut.sauria_logic_i.mc_start, dut.sauria_logic_i.cg_done,
                dut.sauria_logic_i.cg_ctx_status, dut.sauria_logic_i.cg_feed_status);
            $display("DEBUG_ACT done=%b til_done=%b fifo_empty=%b fifo_full=%b stall=%b feeder_en=%b rden=%b addr=%0d",
                dut.sauria_logic_i.mc_act_done, dut.sauria_logic_i.mc_act_til_done,
                dut.sauria_logic_i.mc_act_fifo_empty, dut.sauria_logic_i.mc_act_fifo_full,
                dut.sauria_logic_i.mc_act_stall, dut.sauria_logic_i.af_act_feeder_en,
                dut.sauria_logic_i.af_act_feeder_i.o_srama_rden,
                dut.sauria_logic_i.af_act_feeder_i.o_srama_addr);
            $display("DEBUG_WEI done=%b til_done=%b fifo_empty=%b fifo_full=%b stall=%b feeder_en=%b rden=%b addr=%0d",
                dut.sauria_logic_i.mc_wei_done, dut.sauria_logic_i.mc_wei_til_done,
                dut.sauria_logic_i.mc_wei_fifo_empty, dut.sauria_logic_i.mc_wei_fifo_full,
                dut.sauria_logic_i.mc_wei_stall, dut.sauria_logic_i.wf_wei_feeder_en,
                dut.sauria_logic_i.weight_feeder_i.o_sramb_rden,
                dut.sauria_logic_i.weight_feeder_i.o_sramb_addr);
            $display("DEBUG_CTRL ctx_state=%0d feed_state=%0d start=%b pipeline_en=%b outbuf_done=%b shift_done=%b",
                dut.sauria_logic_i.main_controller_i.context_fsm_i.main_state_q,
                dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q,
                dut.sauria_logic_i.mc_start, dut.sauria_logic_i.sa_pipeline_en,
                dut.sauria_logic_i.mc_outbuf_done, dut.sauria_logic_i.mc_shift_done);
            $fatal(1, "layer timed out after %0d cycles", cycles);
        end
        layer_end_ns = $realtime;
        $display("LAYER_END_NS=%0.3f", layer_end_ns);
        $display("LAYER_CYCLES=%0d", cycles);

`ifndef POWER_ACTIVITY
        write_cfg(32'h5000_0000, 32'h0000_0000);
        write_cfg(32'h5000_0000, 32'h0001_0000);
        repeat (5) @(posedge clk);
        errors = 0;
        checksum = 64'hcbf29ce484222325;
        fd = $fopen("output-readback.mem", "w");
        if (fd == 0) $fatal(1, "cannot create output-readback.mem");
        for (idx = 0; idx < output_word_count; idx = idx + 1) begin
            read_local_word(SRAMC_BASE, idx, SRAMC_W, read_word);
            $fdisplay(fd, "%h", read_word[SRAMC_W-1:0]);
            for (lane = 0; lane < `Y; lane = lane + 1) begin
                if ((idx*`Y + lane) < output_value_count) begin
                    actual = (read_word >> (lane*OC_W));
                    if (actual !== golden[idx*`Y + lane]) begin
                        if (errors < 10)
                            $display("MISMATCH[%0d]: got %h expected %h", idx*`Y + lane, actual, golden[idx*`Y + lane]);
                        errors = errors + 1;
                    end
                    for (byte_idx = 0; byte_idx < ((OC_W+7)/8); byte_idx = byte_idx + 1)
                        checksum = (checksum ^ ((actual >> (8*byte_idx)) & 8'hff)) * 64'h100000001b3;
                end
            end
        end
        $fclose(fd);
        if (errors != 0) $fatal(1, "golden mismatch: %0d outputs", errors);
        $display("OUTPUTS_CHECKED=%0d", output_value_count);
        $display("OUTPUT_FNV1A64=%016x", checksum);
`endif
        $finish;
    end
endmodule
