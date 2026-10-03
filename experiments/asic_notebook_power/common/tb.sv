`timescale 1ns/1ps

module tb;
    localparam int MEM_W = `AXI_NOC_DATA_WIDTH;
    localparam int MEM_BYTES = MEM_W / 8;
    localparam int MAX_CONFIG_WORDS = 128;
    localparam int MAX_DRAM_BYTES = 2_000_000;
    localparam int MAX_OUTPUT_VALUES = 262_144;
    localparam int DMA_CFG_CTRL = 32'h00;
    localparam int DMA_CFG_IRQ_MASK = 32'h04;
    localparam int DMA_CFG_IRQ_STATUS = 32'h0c;
    localparam int DMA_CFG_READER_ADDR = 32'h10;
    localparam int DMA_CFG_WRITER_ADDR = 32'h20;
    localparam int DMA_CFG_BTT = 32'h30;
    localparam logic [31:0] SAURIA_DMA_REGION = 32'hd000_0000;

    logic clk = 1'b0;
    logic rstn = 1'b0;

    logic ctrl_aw_valid = 1'b0;
    logic [31:0] ctrl_aw_addr = '0;
    logic [2:0] ctrl_aw_prot = '0;
    wire ctrl_aw_ready;
    logic ctrl_w_valid = 1'b0;
    logic [31:0] ctrl_w_data = '0;
    logic [3:0] ctrl_w_strb = 4'hf;
    wire ctrl_w_ready;
    wire ctrl_b_valid;
    wire [1:0] ctrl_b_resp;
    logic ctrl_b_ready = 1'b1;

    wire dma_aw_valid;
    wire [31:0] dma_aw_addr;
    wire [2:0] dma_aw_prot;
    logic dma_aw_ready;
    wire dma_w_valid;
    wire [31:0] dma_w_data;
    wire [3:0] dma_w_strb;
    logic dma_w_ready;
    logic dma_b_valid = 1'b0;
    logic [1:0] dma_b_resp = 2'b00;
    wire dma_b_ready;
    logic dma_reader_interrupt;
    logic dma_writer_interrupt;

    logic [MEM_W-1:0] mem_data = '0;
    logic [31:0] mem_addr = '0;
    logic mem_wren = 1'b0;
    logic mem_rden = 1'b0;
    logic [MEM_W-1:0] mem_wmask = '0;
    wire [MEM_W-1:0] mem_rdata;
    wire sauria_done;
    wire layer_done;

    logic [63:0] controller_words [0:MAX_CONFIG_WORDS-1];
    logic [7:0] dram [0:MAX_DRAM_BYTES-1];
    logic [7:0] dram_gold [0:MAX_DRAM_BYTES-1];
    logic [31:0] golden [0:MAX_OUTPUT_VALUES-1];

    logic [31:0] dram_bytes;
    logic [31:0] controller_word_count;
    logic [31:0] output_values;
    logic [31:0] dram_a_offset;
    logic [31:0] dram_b_offset;
    logic [31:0] dram_c_offset;
    logic [31:0] output_bytes;
    logic [31:0] max_layer_cycles;

    logic dma_aw_pending = 1'b0;
    logic dma_w_pending = 1'b0;
    logic [31:0] dma_aw_addr_q = '0;
    logic [31:0] dma_w_data_q = '0;
    logic [3:0] dma_w_strb_q = '0;
    logic [31:0] dma_reader_addr_q = '0;
    logic [31:0] dma_writer_addr_q = '0;
    logic [31:0] dma_btt_q = '0;
    logic [31:0] dma_irq_mask_q = '0;
    logic [1:0] dma_irq_pending_q = '0;
    logic dma_job_start = 1'b0;
    logic [1:0] dma_irq_set = '0;
    logic measure_active = 1'b0;

    integer dma_jobs = 0;
    integer dma_ext_read_bytes = 0;
    integer dma_ext_write_bytes = 0;
    integer dma_ifmap_read_bytes = 0;
    integer dma_weight_read_bytes = 0;
    integer dma_psum_read_bytes = 0;
    integer output_bytes_arg;
    integer initial_output_mismatches;
    integer dma_service_cycles = 0;
    integer layer_cycles = 0;
    integer errors = 0;
    integer fd;
    integer idx;
    integer byte_idx;
    integer beat_idx;
    integer valid_bytes;
    integer latency_cycles;
    integer scan_result;
    integer controller_count_arg;
    integer dram_bytes_arg;
    integer output_values_arg;
    integer dram_a_arg;
    integer dram_b_arg;
    integer dram_c_arg;
    integer max_cycles_arg;
    integer unsigned config_addr;
    integer unsigned config_data;
    string vector_dir;
    string artifact_dir;
    logic [31:0] checksum;
    logic [MEM_W-1:0] beat_data;
    logic [MEM_W-1:0] beat_mask;
    logic [31:0] local_addr;
    logic [31:0] external_addr;
    logic copy_from_dram;
    realtime layer_start_ns;
    realtime layer_end_ns;

    always #1ns clk = ~clk;

    assign dma_aw_ready = !dma_aw_pending && !dma_b_valid;
    assign dma_w_ready = !dma_w_pending && !dma_b_valid;
    assign dma_reader_interrupt = dma_irq_pending_q[0] && dma_irq_mask_q[0];
    assign dma_writer_interrupt = dma_irq_pending_q[1] && dma_irq_mask_q[1];

    sauria_asic_top #(
        .CFG_W(32),
        .CFG_ADDR_W(32),
        .MEM_W(MEM_W),
        .MEM_ADDR_W(32),
        .EXTENDED_HOST_MAP(0)
    ) dut (
        .i_clk(clk),
        .i_rstn(rstn),
        .i_ctrl_aw_valid(ctrl_aw_valid),
        .i_ctrl_aw_addr(ctrl_aw_addr),
        .i_ctrl_aw_prot(ctrl_aw_prot),
        .o_ctrl_aw_ready(ctrl_aw_ready),
        .i_ctrl_w_valid(ctrl_w_valid),
        .i_ctrl_w_data(ctrl_w_data),
        .i_ctrl_w_strb(ctrl_w_strb),
        .o_ctrl_w_ready(ctrl_w_ready),
        .o_ctrl_b_valid(ctrl_b_valid),
        .o_ctrl_b_resp(ctrl_b_resp),
        .i_ctrl_b_ready(ctrl_b_ready),
        .o_dma_aw_valid(dma_aw_valid),
        .o_dma_aw_addr(dma_aw_addr),
        .o_dma_aw_prot(dma_aw_prot),
        .i_dma_aw_ready(dma_aw_ready),
        .o_dma_w_valid(dma_w_valid),
        .o_dma_w_data(dma_w_data),
        .o_dma_w_strb(dma_w_strb),
        .i_dma_w_ready(dma_w_ready),
        .i_dma_b_valid(dma_b_valid),
        .i_dma_b_resp(dma_b_resp),
        .o_dma_b_ready(dma_b_ready),
        .i_dma_reader_interrupt(dma_reader_interrupt),
        .i_dma_writer_interrupt(dma_writer_interrupt),
        .i_mem_data(mem_data),
        .i_mem_addr(mem_addr),
        .i_mem_wren(mem_wren),
        .i_mem_rden(mem_rden),
        .i_mem_wmask(mem_wmask),
        .o_mem_data(mem_rdata),
        .o_sauria_done(sauria_done),
        .o_layer_done(layer_done)
    );

`ifdef XRUN
    initial begin
        // Xcelium 23.03 requires a literal argument to $shm_open. The RTL and
        // gate runners use separate per-stage working directories.
        $shm_open("dut.shm");
        $shm_probe(tb.dut, "ASM");
    end
`endif

    task automatic controller_write(input logic [31:0] address, input logic [31:0] value);
        integer aw_accepted;
        integer w_accepted;
        begin
            aw_accepted = 0;
            w_accepted = 0;
            @(negedge clk);
            ctrl_aw_addr = address;
            ctrl_w_data = value;
            ctrl_aw_valid = 1'b1;
            ctrl_w_valid = 1'b1;
            while (!aw_accepted || !w_accepted) begin
                @(posedge clk);
                if (ctrl_aw_valid && ctrl_aw_ready) aw_accepted = 1;
                if (ctrl_w_valid && ctrl_w_ready) w_accepted = 1;
                @(negedge clk);
                ctrl_aw_valid = !aw_accepted;
                ctrl_w_valid = !w_accepted;
            end
            do @(posedge clk); while (!ctrl_b_valid);
            if (ctrl_b_resp != 2'b00) $fatal(1, "controller AXI-Lite write error at %08x", address);
            @(negedge clk);
            ctrl_aw_valid = 1'b0;
            ctrl_w_valid = 1'b0;
            ctrl_aw_addr = '0;
            ctrl_w_data = '0;
        end
    endtask

    task automatic dma_transfer(input logic [31:0] reader_addr,
                                input logic [31:0] writer_addr,
                                input logic [31:0] byte_count);
        integer offset;
        integer lane;
        integer dram_beats;
        integer beat_cycles;
        begin
            if (byte_count == 0) $fatal(1, "DMA command has zero BTT");
            copy_from_dram = ((reader_addr & 32'hf000_0000) != SAURIA_DMA_REGION);
            if (copy_from_dram == ((writer_addr & 32'hf000_0000) != SAURIA_DMA_REGION))
                $fatal(1, "DMA command must connect one external and one local address: AR=%08x AW=%08x", reader_addr, writer_addr);
            if (copy_from_dram) begin
                external_addr = reader_addr;
                local_addr = writer_addr;
            end else begin
                local_addr = reader_addr;
                external_addr = writer_addr;
            end
            if ((external_addr & (MEM_BYTES-1)) != 0 || (local_addr & (MEM_BYTES-1)) != 0)
                $fatal(1, "notebook DMA transfer is not %0d-byte aligned: external=%08x local=%08x", MEM_BYTES, external_addr, local_addr);
            if (external_addr + byte_count > dram_bytes)
                $fatal(1, "DMA external range outside DRAM image: %08x + %0d > %0d", external_addr, byte_count, dram_bytes);
            if (copy_from_dram) begin
                if (external_addr < dram_b_offset && external_addr + byte_count > dram_b_offset)
                    $fatal(1, "IFMAP DMA crosses into weight region");
                if (external_addr >= dram_b_offset && external_addr < dram_c_offset && external_addr + byte_count > dram_c_offset)
                    $fatal(1, "weight DMA crosses into output/partial-sum region");
            end else if (external_addr < dram_c_offset) begin
                $fatal(1, "DMA writes outside external output/partial-sum region: %08x", external_addr);
            end

            // DRAM_BANDWIDTH is one shared external budget. The DMA has one
            // active command at a time, so reads and writes cannot each claim
            // a separate 128-bit/cycle channel.
            if (`DRAM_BANDWIDTH <= 0 || `DRAM_BANDWIDTH > MEM_W)
                $fatal(1, "unsupported shared DRAM bandwidth %0d for %0d-bit port", `DRAM_BANDWIDTH, MEM_W);
            beat_cycles = (MEM_W + `DRAM_BANDWIDTH - 1) / `DRAM_BANDWIDTH;
            // The modeled SRAM host read has two registered stages. Its
            // transfer rate is an additional limit for local-to-DRAM writes.
            if (!copy_from_dram && beat_cycles < 2) beat_cycles = 2;
            dram_beats = (byte_count + MEM_BYTES - 1) / MEM_BYTES;
            latency_cycles = `DRAM_LATENCY;
            repeat (latency_cycles) @(posedge clk);
            dma_service_cycles = dma_service_cycles + latency_cycles + dram_beats * beat_cycles + (copy_from_dram ? 0 : 2);

            if (copy_from_dram) begin
                for (offset = 0; offset < byte_count; offset = offset + MEM_BYTES) begin
                    valid_bytes = ((byte_count - offset) < MEM_BYTES) ? (byte_count - offset) : MEM_BYTES;
                    beat_data = '0;
                    beat_mask = '0;
                    for (lane = 0; lane < valid_bytes; lane = lane + 1) begin
                        beat_mask[lane*8 +: 8] = 8'hff;
                        beat_data[lane*8 +: 8] = dram[external_addr + offset + lane];
                    end
                    @(negedge clk);
                    mem_addr = local_addr + offset;
                    mem_data = beat_data;
                    mem_wmask = beat_mask;
                    mem_wren = 1'b1;
                    @(posedge clk);
                    #1ps;
                    mem_wren = 1'b0;
                    mem_wmask = '0;
                    for (lane = 0; lane < valid_bytes; lane = lane + 1)
                        begin
                            dma_ext_read_bytes = dma_ext_read_bytes + 1;
                            if (external_addr + offset + lane >= dram_a_offset && external_addr + offset + lane < dram_b_offset)
                                dma_ifmap_read_bytes = dma_ifmap_read_bytes + 1;
                            else if (external_addr + offset + lane >= dram_b_offset && external_addr + offset + lane < dram_c_offset)
                                dma_weight_read_bytes = dma_weight_read_bytes + 1;
                            else if (external_addr + offset + lane >= dram_c_offset)
                                dma_psum_read_bytes = dma_psum_read_bytes + 1;
                        end
                    repeat (beat_cycles - 1) @(posedge clk);
                end
            end else begin
                // sram_top's host read has two registered stages. The model
                // holds one local read in flight and honors that response
                // latency before returning the corresponding DRAM write.
                for (offset = 0; offset < byte_count; offset = offset + MEM_BYTES) begin
                    valid_bytes = ((byte_count - offset) < MEM_BYTES) ? (byte_count - offset) : MEM_BYTES;
                    @(negedge clk);
                    mem_addr = local_addr + offset;
                    mem_rden = 1'b1;
                    @(posedge clk);
                    #1ps;
                    mem_rden = 1'b0;
                    repeat (beat_cycles - 1) @(posedge clk);
                    #1ps;
                    beat_data = mem_rdata;
                    for (lane = 0; lane < valid_bytes; lane = lane + 1)
                        dram[external_addr + offset + lane] = beat_data[lane*8 +: 8];
                    dma_ext_write_bytes = dma_ext_write_bytes + valid_bytes;
                end
            end

            dma_jobs = dma_jobs + 1;
            $display("DMA_JOB=%0d AR=%08x AW=%08x BTT=%0d DIR=%s", dma_jobs,
                     reader_addr, writer_addr, byte_count,
                     copy_from_dram ? "DRAM_TO_SRAM" : "SRAM_TO_DRAM");
            @(negedge clk);
        end
    endtask

    // AXI-Lite register target standing in for the excluded uDMA. This
    // responds to the native command sequence and launches a byte-accurate
    // transfer; it does not preload whole layers or assert completion early.
    always @(posedge clk or negedge rstn) begin : dma_command_slave
        logic aw_fire;
        logic w_fire;
        logic write_complete;
        logic [31:0] write_addr;
        logic [31:0] write_data;
        logic [3:0] write_strb;
        if (!rstn) begin
            dma_aw_pending <= 1'b0;
            dma_w_pending <= 1'b0;
            dma_aw_addr_q <= '0;
            dma_w_data_q <= '0;
            dma_w_strb_q <= '0;
            dma_reader_addr_q <= '0;
            dma_writer_addr_q <= '0;
            dma_btt_q <= '0;
            dma_irq_mask_q <= '0;
            dma_irq_pending_q <= '0;
            dma_b_valid <= 1'b0;
            dma_job_start <= 1'b0;
        end else begin
            dma_job_start <= 1'b0;
            aw_fire = dma_aw_valid && dma_aw_ready;
            w_fire = dma_w_valid && dma_w_ready;
            write_complete = (dma_aw_pending || aw_fire) && (dma_w_pending || w_fire) && !dma_b_valid;
            write_addr = dma_aw_pending ? dma_aw_addr_q : dma_aw_addr;
            write_data = dma_w_pending ? dma_w_data_q : dma_w_data;
            write_strb = dma_w_pending ? dma_w_strb_q : dma_w_strb;

            if (dma_b_valid && dma_b_ready) dma_b_valid <= 1'b0;
            if (aw_fire) begin
                dma_aw_pending <= 1'b1;
                dma_aw_addr_q <= dma_aw_addr;
            end
            if (w_fire) begin
                dma_w_pending <= 1'b1;
                dma_w_data_q <= dma_w_data;
                dma_w_strb_q <= dma_w_strb;
            end

            if (write_complete) begin
                dma_aw_pending <= 1'b0;
                dma_w_pending <= 1'b0;
                dma_b_valid <= 1'b1;
                dma_b_resp <= 2'b00;
                case (write_addr[7:0])
                    DMA_CFG_IRQ_MASK: dma_irq_mask_q <= write_data;
                    DMA_CFG_IRQ_STATUS: begin
                        if (write_strb[0]) dma_irq_pending_q <= dma_irq_pending_q & ~write_data[1:0];
                    end
                    DMA_CFG_READER_ADDR: dma_reader_addr_q <= write_data;
                    DMA_CFG_WRITER_ADDR: dma_writer_addr_q <= write_data;
                    DMA_CFG_BTT: dma_btt_q <= write_data;
                    DMA_CFG_CTRL: begin
                        if (write_data[0] && write_data[1]) dma_job_start <= 1'b1;
                    end
                    default: begin
                    end
                endcase
            end

            if (dma_irq_set != 2'b00)
                dma_irq_pending_q <= dma_irq_pending_q | dma_irq_set;
        end
    end

    // The controller expects independently visible completion interrupts and
    // clears them by writing DMA_CFG_IRQ_STATUS. Keep them asserted until then.
    always begin : dma_worker
        @(posedge dma_job_start);
        @(negedge clk);
        dma_transfer(dma_reader_addr_q, dma_writer_addr_q, dma_btt_q);
        @(negedge clk);
        dma_irq_set = 2'b11;
        @(negedge clk);
        dma_irq_set = '0;
    end

    initial begin : layer_test
        if (!$value$plusargs("CONTROLLER_CONFIG_WORDS=%d", controller_count_arg)) $fatal(1, "missing CONTROLLER_CONFIG_WORDS");
        if (!$value$plusargs("DRAM_BYTES=%d", dram_bytes_arg)) $fatal(1, "missing DRAM_BYTES");
        if (!$value$plusargs("OUTPUT_VALUES=%d", output_values_arg)) $fatal(1, "missing OUTPUT_VALUES");
        if (!$value$plusargs("DRAM_A_OFFSET=%d", dram_a_arg)) $fatal(1, "missing DRAM_A_OFFSET");
        if (!$value$plusargs("DRAM_B_OFFSET=%d", dram_b_arg)) $fatal(1, "missing DRAM_B_OFFSET");
        if (!$value$plusargs("DRAM_C_OFFSET=%d", dram_c_arg)) $fatal(1, "missing DRAM_C_OFFSET");
        if (!$value$plusargs("OUTPUT_BYTES=%d", output_bytes_arg)) $fatal(1, "missing OUTPUT_BYTES");
        if (!$value$plusargs("VECTOR_DIR=%s", vector_dir)) $fatal(1, "missing VECTOR_DIR");
        if (!$value$plusargs("ARTIFACT_DIR=%s", artifact_dir)) $fatal(1, "missing ARTIFACT_DIR");
        if (!$value$plusargs("MAX_LAYER_CYCLES=%d", max_cycles_arg)) max_cycles_arg = 20_000_000;
        if (controller_count_arg > MAX_CONFIG_WORDS || dram_bytes_arg > MAX_DRAM_BYTES || output_values_arg > MAX_OUTPUT_VALUES)
            $fatal(1, "generated workload exceeds testbench capacity");
        controller_word_count = controller_count_arg;
        dram_bytes = dram_bytes_arg;
        output_values = output_values_arg;
        dram_a_offset = dram_a_arg;
        dram_b_offset = dram_b_arg;
        dram_c_offset = dram_c_arg;
        output_bytes = output_bytes_arg;

        $readmemh({vector_dir, "/controller_config.mem"}, controller_words);
        $readmemh({vector_dir, "/dram.mem"}, dram);
        $readmemh({vector_dir, "/dram_gold.mem"}, dram_gold);
        $readmemh({vector_dir, "/golden.mem"}, golden);
        initial_output_mismatches = 0;
        for (byte_idx = dram_c_offset; byte_idx < dram_bytes; byte_idx = byte_idx + 1)
            if (dram[byte_idx] !== dram_gold[byte_idx]) initial_output_mismatches = initial_output_mismatches + 1;
        if (initial_output_mismatches == 0)
            $fatal(1, "DRAM output region already equals golden; output DMA could be skipped");
        if (output_bytes != dram_bytes - dram_c_offset)
            $fatal(1, "output byte range mismatch: expected=%0d C-region=%0d", output_bytes, dram_bytes - dram_c_offset);
        repeat (10) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        for (idx = 0; idx < controller_word_count; idx = idx + 1) begin
            config_addr = controller_words[idx][63:32];
            config_data = controller_words[idx][31:0];
            controller_write(config_addr, config_data);
        end

        repeat (4) @(posedge clk);
        layer_cycles = 0;
        measure_active = 1'b1;
        @(negedge clk);
        layer_start_ns = $realtime;
        fd = $fopen({artifact_dir, "/layer_window.txt"}, "w");
        if (fd == 0) $fatal(1, "cannot create layer window file");
        $fdisplay(fd, "%0.3f", layer_start_ns);
        $fclose(fd);
        $display("LAYER_START_NS=%0.3f", layer_start_ns);
        controller_write(32'h4000_0000, 32'h0000_0001);

        while ((layer_done !== 1'b1) && (layer_cycles < max_cycles_arg)) @(posedge clk);
        if (layer_done !== 1'b1) $fatal(1, "layer timed out after %0d cycles; DMA jobs=%0d", layer_cycles, dma_jobs);
        measure_active = 1'b0;
        // layer_done is asserted only after the controller has completed its
        // final external write. End the activity window here, before golden
        // readback and reporting work in the testbench.
        layer_end_ns = $realtime;
        $display("LAYER_END_NS=%0.3f", layer_end_ns);
        fd = $fopen({artifact_dir, "/layer_window.txt"}, "a");
        if (fd == 0) $fatal(1, "cannot append layer window file at layer completion");
        $fdisplay(fd, "%0.3f", layer_end_ns);
        $fclose(fd);
        $display("LAYER_CYCLES=%0d", layer_cycles);
        $display("DMA_JOBS=%0d", dma_jobs);
        $display("DRAM_READ_BYTES=%0d", dma_ext_read_bytes);
        $display("IFMAP_READ_BYTES=%0d", dma_ifmap_read_bytes);
        $display("WEIGHT_READ_BYTES=%0d", dma_weight_read_bytes);
        $display("PSUM_READ_BYTES=%0d", dma_psum_read_bytes);
        $display("DRAM_WRITE_BYTES=%0d", dma_ext_write_bytes);
        $display("DRAM_SERVICE_CYCLES=%0d", dma_service_cycles);
        $display("DRAM_TOTAL_BYTES=%0d", dma_ext_read_bytes + dma_ext_write_bytes);

        errors = 0;
        checksum = 32'h811c9dc5;
        for (byte_idx = dram_c_offset; byte_idx < dram_bytes; byte_idx = byte_idx + 1) begin
            if (dram[byte_idx] !== dram_gold[byte_idx]) begin
                if (errors < 10)
                    $display("DRAM_GOLDEN_MISMATCH byte=%0d got=%02x expected=%02x", byte_idx, dram[byte_idx], dram_gold[byte_idx]);
                errors = errors + 1;
            end
            checksum = (checksum ^ dram[byte_idx]) * 32'h01000193;
        end
        if (errors != 0) $fatal(1, "full-layer golden mismatch: %0d output bytes", errors);
        if (dma_jobs == 0 || dma_ext_read_bytes == 0 || dma_ext_write_bytes == 0)
            $fatal(1, "layer did not exercise both external DRAM directions");
        if (dma_ext_write_bytes != output_bytes)
            $fatal(1, "external output writes do not cover the full layer: wrote=%0d expected=%0d", dma_ext_write_bytes, output_bytes);
        $display("OUTPUTS_CHECKED=%0d", output_values);
        $display("OUTPUT_BYTES_CHECKED=%0d", dram_bytes - dram_c_offset);
        $display("OUTPUT_CHECKSUM=%08x", checksum);
        $display("NOTEBOOK_LAYER_PASS");
        $finish;
    end

    always @(posedge clk) begin
        if (rstn && measure_active && layer_cycles < max_cycles_arg)
            layer_cycles = layer_cycles + 1;
    end
endmodule
