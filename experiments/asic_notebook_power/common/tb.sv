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
    logic dma_reader_start_pending_q = 1'b0;
    logic dma_writer_start_pending_q = 1'b0;
    logic [31:0] dma_reader_start_addr_q = '0;
    logic [31:0] dma_reader_start_btt_q = '0;
    logic [31:0] dma_writer_start_addr_q = '0;
    logic [31:0] dma_writer_start_btt_q = '0;
    logic [31:0] dma_job_reader_addr_q = '0;
    logic [31:0] dma_job_writer_addr_q = '0;
    logic [31:0] dma_job_btt_q = '0;
    logic dma_job_start = 1'b0;
    logic [1:0] dma_irq_set = '0;
    logic measure_active = 1'b0;
    logic debug_trace_valid_q = 1'b0;
    logic [4:0] debug_feed_state_q = '0;
    logic debug_core_started_q = 1'b0;
    logic debug_core_done_q = 1'b0;

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
    integer psm_trace_fd = 0;
    integer psm_trace_count = 0;
    integer sramc_host_trace_fd = 0;
    integer sramc_host_read_count = 0;
    integer sramc_dump_fd = 0;
    integer sram_read_trace_fd = 0;
    integer ifmap_push_trace_fd = 0;
    integer sram_trace_cycle = 0;
    integer srama_read_req_id = 0;
    integer sramb_read_req_id = 0;
    integer srama_pending_req_id = 0;
    integer sramb_pending_req_id = 0;
    integer srama_pending_valid = 0;
    integer sramb_pending_valid = 0;
    logic srama_pending_select = 1'b0;
    logic sramb_pending_select = 1'b0;
    logic [sauria_pkg::ADRA_W-1:0] srama_pending_addr = '0;
    logic [sauria_pkg::ADRB_W-1:0] sramb_pending_addr = '0;
    logic [sauria_pkg::ADRA_W-1:0] srama_pending_bank0_addr = '0;
    logic [sauria_pkg::ADRA_W-1:0] srama_pending_bank1_addr = '0;
    logic [sauria_pkg::ADRB_W-1:0] sramb_pending_bank0_addr = '0;
    logic [sauria_pkg::ADRB_W-1:0] sramb_pending_bank1_addr = '0;
    integer dma_c_read_debug_count = 0;
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

    always @(posedge clk) begin
        if (measure_active && dut.sauria_logic_i.psm_top_i.o_sramc_wren && psm_trace_fd != 0) begin
            psm_trace_count = psm_trace_count + 1;
            $fdisplay(psm_trace_fd,
                "PSM_C_WRITE cycle=%0d index=%0d addr=%0d mask=%b data=%0h ctx=%0d scan=%0d select=%b bank0_addr=%0d bank0_wren=%b bank1_addr=%0d bank1_wren=%b",
                layer_cycles, psm_trace_count,
                dut.sauria_logic_i.psm_top_i.o_sramc_addr,
                dut.sauria_logic_i.psm_top_i.o_sramc_wmask,
                dut.sauria_logic_i.psm_top_i.o_sramc_wdata,
                dut.sauria_logic_i.psm_top_i.psm_shift_fsm_i.ctx_cnt,
                dut.sauria_logic_i.psm_top_i.psm_shift_fsm_i.scan_cnt,
                dut.sram_top_i.i_select[2],
                dut.sram_top_i.SRAMC_i.addr_0,
                dut.sram_top_i.SRAMC_i.wren_0,
                dut.sram_top_i.SRAMC_i.addr_1,
                dut.sram_top_i.SRAMC_i.wren_1);
            $fdisplay(psm_trace_fd,
                "PSM_C_PHYSICAL cycle=%0d bank0_addr=%0d bank0_wren=%b bank0_cen=%b bank0_rdwen=%b bank0_data=%0h bank0_wmask=%0h bank1_addr=%0d bank1_wren=%b bank1_cen=%b bank1_rdwen=%b bank1_data=%0h bank1_wmask=%0h",
                layer_cycles,
                dut.sram_top_i.SRAMC_i.addr_0,
                dut.sram_top_i.SRAMC_i.wren_0,
                dut.sram_top_i.SRAMC_i.cen_0,
                dut.sram_top_i.SRAMC_i.rdwen_0,
                dut.sram_top_i.SRAMC_i.indata_0,
                dut.sram_top_i.SRAMC_i.wmask_0,
                dut.sram_top_i.SRAMC_i.addr_1,
                dut.sram_top_i.SRAMC_i.wren_1,
                dut.sram_top_i.SRAMC_i.cen_1,
                dut.sram_top_i.SRAMC_i.rdwen_1,
                dut.sram_top_i.SRAMC_i.indata_1,
                dut.sram_top_i.SRAMC_i.wmask_1);
        end
    end

    always @(negedge clk) begin
        if (measure_active) sram_trace_cycle = sram_trace_cycle + 1;
        else sram_trace_cycle = 0;
    end

    // Record accepted accelerator SRAM reads and pair each response with the
    // request sampled on the previous edge. The inferred SRAM updates its
    // output after the request edge, so this pre-NBA snapshot is the response
    // to the pending request, not to a request sampled at this edge.
    always @(posedge clk) begin
        if (!measure_active) begin
            srama_pending_valid = 0;
            sramb_pending_valid = 0;
        end else begin
            if (sram_read_trace_fd != 0) begin
                if (srama_pending_valid) begin
                    $fdisplay(sram_read_trace_fd,
                        "SRAM_READ_RSP cycle=%0d mem=A req_id=%0d req_select=%b req_addr=%0d req_bank0_addr=%0d req_bank1_addr=%0d raw_bank0=%0h raw_bank1=%0h raw_req_bank=%0h accel_mux_current=%0h top_q_current=%0h core_data_current=%0h",
                        sram_trace_cycle, srama_pending_req_id, srama_pending_select,
                        srama_pending_addr,
                        srama_pending_bank0_addr,
                        srama_pending_bank1_addr,
                        dut.sram_top_i.SRAMA_i.outdata_0,
                        dut.sram_top_i.SRAMA_i.outdata_1,
                        srama_pending_select ? dut.sram_top_i.SRAMA_i.outdata_0 : dut.sram_top_i.SRAMA_i.outdata_1,
                        dut.sram_top_i.SRAMA_i.accel_outdata_sel,
                        dut.sram_top_i.srama_output_q,
                        dut.sauria_logic_i.i_srama_data);
                    srama_pending_valid = 0;
                end
                if (sramb_pending_valid) begin
                    $fdisplay(sram_read_trace_fd,
                        "SRAM_READ_RSP cycle=%0d mem=B req_id=%0d req_select=%b req_addr=%0d req_bank0_addr=%0d req_bank1_addr=%0d raw_bank0=%0h raw_bank1=%0h raw_req_bank=%0h accel_mux_current=%0h top_q_current=%0h core_data_current=%0h",
                        sram_trace_cycle, sramb_pending_req_id, sramb_pending_select,
                        sramb_pending_addr,
                        sramb_pending_bank0_addr,
                        sramb_pending_bank1_addr,
                        dut.sram_top_i.SRAMB_i.outdata_0,
                        dut.sram_top_i.SRAMB_i.outdata_1,
                        sramb_pending_select ? dut.sram_top_i.SRAMB_i.outdata_0 : dut.sram_top_i.SRAMB_i.outdata_1,
                        dut.sram_top_i.SRAMB_i.accel_outdata_sel,
                        dut.sram_top_i.sramb_output_q,
                        dut.sauria_logic_i.i_sramb_data);
                    sramb_pending_valid = 0;
                end

                if ((dut.sram_top_i.SRAMA_i.rden_0 && !dut.sram_top_i.SRAMA_i.cen_0 && dut.sram_top_i.SRAMA_i.rdwen_0) ||
                    (dut.sram_top_i.SRAMA_i.rden_1 && !dut.sram_top_i.SRAMA_i.cen_1 && dut.sram_top_i.SRAMA_i.rdwen_1)) begin
                    srama_read_req_id = srama_read_req_id + 1;
                    $fdisplay(sram_read_trace_fd,
                        "SRAM_READ_REQ cycle=%0d mem=A req_id=%0d core_rden=%b core_addr=%0d select=%b rden0=%b cen0=%b rdwen0=%b addr0=%0d rden1=%b cen1=%b rdwen1=%b addr1=%0d raw0_pre=%0h raw1_pre=%0h accel_mux_pre=%0h top_q_pre=%0h core_data_pre=%0h",
                        sram_trace_cycle, srama_read_req_id,
                        dut.sauria_logic_i.o_srama_rden,
                        dut.sauria_logic_i.o_srama_addr,
                        dut.sram_top_i.i_select[0],
                        dut.sram_top_i.SRAMA_i.rden_0,
                        dut.sram_top_i.SRAMA_i.cen_0,
                        dut.sram_top_i.SRAMA_i.rdwen_0,
                        dut.sram_top_i.SRAMA_i.addr_0,
                        dut.sram_top_i.SRAMA_i.rden_1,
                        dut.sram_top_i.SRAMA_i.cen_1,
                        dut.sram_top_i.SRAMA_i.rdwen_1,
                        dut.sram_top_i.SRAMA_i.addr_1,
                        dut.sram_top_i.SRAMA_i.outdata_0,
                        dut.sram_top_i.SRAMA_i.outdata_1,
                        dut.sram_top_i.SRAMA_i.accel_outdata_sel,
                        dut.sram_top_i.srama_output_q,
                        dut.sauria_logic_i.i_srama_data);
                    srama_pending_valid = 1;
                    srama_pending_req_id = srama_read_req_id;
                    srama_pending_select = dut.sram_top_i.i_select[0];
                    srama_pending_addr = dut.sauria_logic_i.o_srama_addr;
                    srama_pending_bank0_addr = dut.sram_top_i.SRAMA_i.addr_0;
                    srama_pending_bank1_addr = dut.sram_top_i.SRAMA_i.addr_1;
                end
                if ((dut.sram_top_i.SRAMB_i.rden_0 && !dut.sram_top_i.SRAMB_i.cen_0 && dut.sram_top_i.SRAMB_i.rdwen_0) ||
                    (dut.sram_top_i.SRAMB_i.rden_1 && !dut.sram_top_i.SRAMB_i.cen_1 && dut.sram_top_i.SRAMB_i.rdwen_1)) begin
                    sramb_read_req_id = sramb_read_req_id + 1;
                    $fdisplay(sram_read_trace_fd,
                        "SRAM_READ_REQ cycle=%0d mem=B req_id=%0d core_rden=%b core_addr=%0d select=%b rden0=%b cen0=%b rdwen0=%b addr0=%0d rden1=%b cen1=%b rdwen1=%b addr1=%0d raw0_pre=%0h raw1_pre=%0h accel_mux_pre=%0h top_q_pre=%0h core_data_pre=%0h",
                        sram_trace_cycle, sramb_read_req_id,
                        dut.sauria_logic_i.o_sramb_rden,
                        dut.sauria_logic_i.o_sramb_addr,
                        dut.sram_top_i.i_select[1],
                        dut.sram_top_i.SRAMB_i.rden_0,
                        dut.sram_top_i.SRAMB_i.cen_0,
                        dut.sram_top_i.SRAMB_i.rdwen_0,
                        dut.sram_top_i.SRAMB_i.addr_0,
                        dut.sram_top_i.SRAMB_i.rden_1,
                        dut.sram_top_i.SRAMB_i.cen_1,
                        dut.sram_top_i.SRAMB_i.rdwen_1,
                        dut.sram_top_i.SRAMB_i.addr_1,
                        dut.sram_top_i.SRAMB_i.outdata_0,
                        dut.sram_top_i.SRAMB_i.outdata_1,
                        dut.sram_top_i.SRAMB_i.accel_outdata_sel,
                        dut.sram_top_i.sramb_output_q,
                        dut.sauria_logic_i.i_sramb_data);
                    sramb_pending_valid = 1;
                    sramb_pending_req_id = sramb_read_req_id;
                    sramb_pending_select = dut.sram_top_i.i_select[1];
                    sramb_pending_addr = dut.sauria_logic_i.o_sramb_addr;
                    sramb_pending_bank0_addr = dut.sram_top_i.SRAMB_i.addr_0;
                    sramb_pending_bank1_addr = dut.sram_top_i.SRAMB_i.addr_1;
                end

                if (dut.sauria_logic_i.ifmap_feeder_i.pipeline_regs_en) begin
                    $fdisplay(sram_read_trace_fd,
                        "IFMAP_FEED_SAMPLE cycle=%0d addr=%0d core_data_sampled=%0h data_q_pre=%0h feeder_mux_pre=%0h x=%0d y=%0d ch=%0d til_x=%0d til_y=%0d sram_idx=%0d glob_woffs=%0d xov=%b valid=%b finalpush=%b full=%b stall=%b update=%b",
                        sram_trace_cycle,
                        dut.sauria_logic_i.o_srama_addr,
                        dut.sauria_logic_i.i_srama_data,
                        dut.sauria_logic_i.ifmap_feeder_i.sram_data_q,
                        dut.sauria_logic_i.ifmap_feeder_i.srama_data_mux,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.x_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.y_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.ch_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.til_x_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.til_y_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.sram_idx_q,
                        dut.sauria_logic_i.ifmap_feeder_i.glob_woffs,
                        dut.sauria_logic_i.ifmap_feeder_i.x_transition_flag,
                        dut.sauria_logic_i.ifmap_feeder_i.valid_data,
                        dut.sauria_logic_i.ifmap_feeder_i.i_finalpush,
                        dut.sauria_logic_i.ifmap_feeder_i.fifo_full_any,
                        dut.sauria_logic_i.ifmap_feeder_i.stall_any,
                        dut.sauria_logic_i.ifmap_feeder_i.feeders_update);
                end
            end
        end
    end

    // One event record per lane on an accepted FIFO push (or attempted push
    // while full). This exposes ordering and state without dumping idle cycles.
    genvar trace_lane;
    generate
        for (trace_lane = 0; trace_lane < sauria_pkg::Y; trace_lane = trace_lane + 1) begin : ifmap_push_trace
            always @(posedge clk) begin
                if (measure_active && ifmap_push_trace_fd != 0 &&
                    (dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.feed_data_manager_i.fifo_push ||
                     (dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.feed_data_manager_i.n_free_regs == 0 &&
                      dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.i_feeder_en))) begin
                    $fdisplay(ifmap_push_trace_fd,
                        "IFMAP_FIFO_PUSH cycle=%0d lane=%0d accepted=%b full=%b lane_en=%b update=%b valid=%b finalpush=%b outbounds=%b x=%0d y=%0d ch=%0d til_x=%0d til_y=%0d sram_idx=%0d glob_woffs=%0d loc_woffs=%0d offset=%0d shift_idx=%0d read_ptr=%0d regs_active=%0h mux=%0h din=%0h stall=%b feeder_full=%b fifo_full=%b",
                        sram_trace_cycle, trace_lane,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.feed_data_manager_i.fifo_push &&
                            !dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.fifo_full,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.fifo_full,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.i_feeder_en,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.i_update,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.i_valid_data,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.i_finalpush,
                        dut.sauria_logic_i.ifmap_feeder_i.outbounds,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.x_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.y_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.ch_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.til_x_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.til_y_idx,
                        dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.sram_idx_q,
                        dut.sauria_logic_i.ifmap_feeder_i.glob_woffs,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.i_loc_woffs,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.feed_data_manager_i.woffs_init_q,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.feed_data_manager_i.shift_idx_cnt_q,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.feed_data_manager_i.read_ptr_q,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.feed_data_manager_i.regs_active_q,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.feed_data_manager_i.mux_control_array,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.fifo_din,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.o_stall,
                        dut.sauria_logic_i.ifmap_feeder_i.fifo_full_any,
                        dut.sauria_logic_i.ifmap_feeder_i.y_axis[trace_lane].ifmap_feeder_i.fifo_full);
                end
            end
        end
    endgenerate

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

    task automatic pulse_dma_irq(input logic [1:0] irq_bits);
        begin
            @(negedge clk);
            dma_irq_set = irq_bits;
            @(negedge clk);
            dma_irq_set = '0;
        end
    endtask

    task automatic dma_transfer(input logic [31:0] reader_addr,
                                input logic [31:0] writer_addr,
                                input logic [31:0] byte_count);
        integer offset;
        integer lane;
        integer lane_offset;
        integer chunk_bytes;
        integer dram_beats;
        integer sram_beats;
        integer beat_cycles;
        integer trace_c_read;
        integer pending_offset;
        integer pending_lane_offset;
        integer pending_chunk_bytes;
        logic [31:0] pending_bank;
        logic pending_read_valid;
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
            dram_beats = ((external_addr & (MEM_BYTES-1)) + byte_count + MEM_BYTES - 1) / MEM_BYTES;
            sram_beats = ((local_addr & (MEM_BYTES-1)) + byte_count + MEM_BYTES - 1) / MEM_BYTES;
            latency_cycles = `DRAM_LATENCY;
            repeat (latency_cycles) @(posedge clk);
            dma_service_cycles = dma_service_cycles + latency_cycles + dram_beats * beat_cycles +
                                 (copy_from_dram ? 0 : (sram_beats * 2 + beat_cycles));

            if (copy_from_dram) begin
                // The realigner accepts byte offsets on both sides. Build each
                // SRAM host-port word at its aligned address and place the
                // stream bytes into the lanes selected by the local offset.
                for (offset = 0; offset < byte_count; offset = offset + chunk_bytes) begin
                    lane_offset = (local_addr + offset) & (MEM_BYTES-1);
                    chunk_bytes = ((byte_count - offset) < (MEM_BYTES - lane_offset)) ?
                                  (byte_count - offset) : (MEM_BYTES - lane_offset);
                    beat_data = '0;
                    beat_mask = '0;
                    for (lane = 0; lane < chunk_bytes; lane = lane + 1) begin
                        beat_mask[(lane_offset+lane)*8 +: 8] = 8'hff;
                        beat_data[(lane_offset+lane)*8 +: 8] = dram[external_addr + offset + lane];
                    end
                    // The realigner can finish producing the final word while
                    // that word is still held in its downstream FIFO. Model
                    // that one-beat separation instead of asserting both DMA
                    // interrupts together at command completion.
                    if (offset + MEM_BYTES >= byte_count) pulse_dma_irq(2'b01);
                    @(negedge clk);
                    mem_addr = (local_addr + offset) & ~(MEM_BYTES-1);
                    mem_data = beat_data;
                    mem_wmask = beat_mask;
                    mem_wren = 1'b1;
                    @(posedge clk);
                    #1ps;
                    mem_wren = 1'b0;
                    mem_wmask = '0;
                    for (lane = 0; lane < chunk_bytes; lane = lane + 1)
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
                // sram_top's host output register captures the prior host
                // read response when i_rden is asserted. Keep a response tag
                // in flight so each returned word is written to the DRAM
                // offset belonging to its request, rather than the current
                // request's offset.
                pending_read_valid = 1'b0;
                pending_offset = 0;
                pending_lane_offset = 0;
                pending_chunk_bytes = 0;
                pending_bank = '0;
                for (offset = 0; offset < byte_count; offset = offset + chunk_bytes) begin
                    lane_offset = (local_addr + offset) & (MEM_BYTES-1);
                    chunk_bytes = ((byte_count - offset) < (MEM_BYTES - lane_offset)) ?
                                  (byte_count - offset) : (MEM_BYTES - lane_offset);
                    @(negedge clk);
                    mem_addr = (local_addr + offset) & ~(MEM_BYTES-1);
                    mem_rden = 1'b1;
                    trace_c_read = ((local_addr & 32'hffff_0000) == 32'hd00c_0000) &&
                                   (dma_c_read_debug_count < 3);
                    if (trace_c_read) begin
                        dma_c_read_debug_count = dma_c_read_debug_count + 1;
                        $display("DMA_C_READ_REQ n=%0d dram_addr=%08x mem_addr=%08x local=%08x bank_d=%08x bank_q=%08x local_addr=%08x select=%b c_addr0=%08x c_addr1=%08x", dma_c_read_debug_count, external_addr+offset, mem_addr, local_addr+offset, dut.sram_top_i.host_sram_select_d, dut.sram_top_i.host_sram_select_q, dut.sram_top_i.host_local_address, dut.sram_top_i.i_select[2], dut.sram_top_i.SRAMC_i.addr_0, dut.sram_top_i.SRAMC_i.addr_1);
                    end
                    @(posedge clk);
                    #1ps;
                    beat_data = mem_rdata;
                    if (((local_addr & 32'hffff_0000) == 32'hd00c_0000) &&
                        sramc_host_trace_fd != 0) begin
                        sramc_host_read_count = sramc_host_read_count + 1;
                        $fdisplay(sramc_host_trace_fd,
                            "SRAMC_HOST_EDGE cycle=%0d request_index=%0d request_local_byte=%08x request_external_byte=%08x request_bank_d=%08x response_bank=%08x request_bank_q=%08x select=%b host_local=%08x host_phys=%08x host_word_sel=%0d host_word_sel_q=%0d port_rden=%b bank0_addr=%0d bank0_rden=%b bank0_cen=%b bank0_rdwen=%b bank0_raw=%0h bank1_addr=%0d bank1_rden=%b bank1_cen=%b bank1_rdwen=%b bank1_raw=%0h raw_host=%0h host_mux=%0h host_q=%0h mem_rdata=%0h pending_valid=%b response_offset=%0d response_lane=%0d response_bytes=%0d response_external=%08x",
                            layer_cycles,
                            sramc_host_read_count,
                            local_addr+offset,
                            external_addr+offset,
                            dut.sram_top_i.host_sram_select_d,
                            pending_bank,
                            dut.sram_top_i.host_sram_select_q,
                            dut.sram_top_i.i_select[2],
                            dut.sram_top_i.host_local_address,
                            dut.sram_top_i.SRAMC_i.host_phys_addr,
                            dut.sram_top_i.SRAMC_i.host_word_sel,
                            dut.sram_top_i.SRAMC_i.host_word_sel_shim_q,
                            dut.sram_top_i.host_sramc_rden,
                            dut.sram_top_i.SRAMC_i.addr_0,
                            dut.sram_top_i.SRAMC_i.rden_0,
                            dut.sram_top_i.SRAMC_i.cen_0,
                            dut.sram_top_i.SRAMC_i.rdwen_0,
                            dut.sram_top_i.SRAMC_i.outdata_0,
                            dut.sram_top_i.SRAMC_i.addr_1,
                            dut.sram_top_i.SRAMC_i.rden_1,
                            dut.sram_top_i.SRAMC_i.cen_1,
                            dut.sram_top_i.SRAMC_i.rdwen_1,
                            dut.sram_top_i.SRAMC_i.outdata_1,
                            dut.sram_top_i.host_sramc_data,
                            dut.sram_top_i.host_sram_output,
                            dut.sram_top_i.host_sram_output_q,
                            beat_data,
                            pending_read_valid,
                            pending_offset,
                            pending_lane_offset,
                            pending_chunk_bytes,
                            external_addr+pending_offset);
                    end
                    if (pending_read_valid) begin
                        if (pending_lane_offset + pending_chunk_bytes > MEM_BYTES)
                            $fatal(1, "pending SRAM response exceeds host word: lane=%0d bytes=%0d", pending_lane_offset, pending_chunk_bytes);
                        if (pending_offset < 0 || pending_offset + pending_chunk_bytes > byte_count)
                            $fatal(1, "pending SRAM response exceeds DMA transfer: offset=%0d bytes=%0d BTT=%0d", pending_offset, pending_chunk_bytes, byte_count);
                        for (lane = 0; lane < pending_chunk_bytes; lane = lane + 1)
                            dram[external_addr + pending_offset + lane] =
                                beat_data[(pending_lane_offset+lane)*8 +: 8];
                        dma_ext_write_bytes = dma_ext_write_bytes + pending_chunk_bytes;
                    end
                    if (trace_c_read)
                        $display("DMA_C_READ_RESPONSE n=%0d response_offset=%0d dram_addr=%08x lane_offset=%0d bytes=%0d rdata=%0h c_host=%0h host_out=%0h bank_q=%08x select=%b",
                                 dma_c_read_debug_count,
                                 pending_offset,
                                 external_addr+pending_offset,
                                 pending_lane_offset,
                                 pending_chunk_bytes,
                                 beat_data,
                                 dut.sram_top_i.host_sramc_data,
                                 dut.sram_top_i.host_sram_output,
                                 dut.sram_top_i.host_sram_select_q,
                                 dut.sram_top_i.i_select[2]);
                    pending_offset = offset;
                    pending_lane_offset = lane_offset;
                    pending_chunk_bytes = chunk_bytes;
                    pending_bank = dut.sram_top_i.host_sram_select_d;
                    pending_read_valid = 1'b1;
                    mem_rden = 1'b0;
                    if (trace_c_read)
                        $display("DMA_C_READ_EDGE n=%0d rdata=%0h c_host=%0h bank_d=%08x bank_q=%08x select=%b", dma_c_read_debug_count, mem_rdata, dut.sram_top_i.host_sramc_data, dut.sram_top_i.host_sram_select_d, dut.sram_top_i.host_sram_select_q, dut.sram_top_i.i_select[2]);
                    repeat (beat_cycles - 1) @(posedge clk);
                end
                if (!pending_read_valid)
                    $fatal(1, "SRAM-to-DRAM transfer ended without a pending host response");

                // One tagged drain advances the host output register for the
                // final real request. The drain itself has no DRAM destination
                // tag and must not create an extra output beat.
                @(negedge clk);
                mem_addr = (local_addr + pending_offset) & ~(MEM_BYTES-1);
                mem_rden = 1'b1;
                @(posedge clk);
                #1ps;
                beat_data = mem_rdata;
                if (((local_addr & 32'hffff_0000) == 32'hd00c_0000) &&
                    sramc_host_trace_fd != 0)
                    $fdisplay(sramc_host_trace_fd,
                        "SRAMC_HOST_DRAIN cycle=%0d request_local_byte=%08x request_bank_d=%08x response_bank=%08x request_bank_q=%08x select=%b host_local=%08x host_phys=%08x host_word_sel=%0d host_word_sel_q=%0d port_rden=%b bank0_addr=%0d bank0_rden=%b bank0_cen=%b bank0_rdwen=%b bank0_raw=%0h bank1_addr=%0d bank1_rden=%b bank1_cen=%b bank1_rdwen=%b bank1_raw=%0h raw_host=%0h host_mux=%0h host_q=%0h mem_rdata=%0h response_offset=%0d response_lane=%0d response_bytes=%0d response_external=%08x",
                        layer_cycles,
                        mem_addr,
                        dut.sram_top_i.host_sram_select_d,
                        pending_bank,
                        dut.sram_top_i.host_sram_select_q,
                        dut.sram_top_i.i_select[2],
                        dut.sram_top_i.host_local_address,
                        dut.sram_top_i.SRAMC_i.host_phys_addr,
                        dut.sram_top_i.SRAMC_i.host_word_sel,
                        dut.sram_top_i.SRAMC_i.host_word_sel_shim_q,
                        dut.sram_top_i.host_sramc_rden,
                        dut.sram_top_i.SRAMC_i.addr_0,
                        dut.sram_top_i.SRAMC_i.rden_0,
                        dut.sram_top_i.SRAMC_i.cen_0,
                        dut.sram_top_i.SRAMC_i.rdwen_0,
                        dut.sram_top_i.SRAMC_i.outdata_0,
                        dut.sram_top_i.SRAMC_i.addr_1,
                        dut.sram_top_i.SRAMC_i.rden_1,
                        dut.sram_top_i.SRAMC_i.cen_1,
                        dut.sram_top_i.SRAMC_i.rdwen_1,
                        dut.sram_top_i.SRAMC_i.outdata_1,
                        dut.sram_top_i.host_sramc_data,
                        dut.sram_top_i.host_sram_output,
                        dut.sram_top_i.host_sram_output_q,
                        beat_data,
                        pending_offset,
                        pending_lane_offset,
                        pending_chunk_bytes,
                        external_addr+pending_offset);
                if (pending_lane_offset + pending_chunk_bytes > MEM_BYTES ||
                    pending_offset + pending_chunk_bytes > byte_count)
                    $fatal(1, "final SRAM response tag is outside its transfer bounds");
                for (lane = 0; lane < pending_chunk_bytes; lane = lane + 1)
                    dram[external_addr + pending_offset + lane] =
                        beat_data[(pending_lane_offset+lane)*8 +: 8];
                dma_ext_write_bytes = dma_ext_write_bytes + pending_chunk_bytes;
                if (((local_addr & 32'hffff_0000) == 32'hd00c_0000) &&
                    dma_c_read_debug_count < 3)
                    $display("DMA_C_READ_DRAIN response_offset=%0d dram_addr=%08x bytes=%0d rdata=%0h",
                             pending_offset, external_addr+pending_offset,
                             pending_chunk_bytes, beat_data);
                pending_read_valid = 1'b0;
                mem_rden = 1'b0;
                pulse_dma_irq(2'b01);
                if (pending_read_valid)
                    $fatal(1, "SRAM response tag remained valid after drain");
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
        logic [1:0] irq_clear;
        logic reader_seen;
        logic writer_seen;
        logic [31:0] reader_addr_snapshot;
        logic [31:0] reader_btt_snapshot;
        logic [31:0] writer_addr_snapshot;
        logic [31:0] writer_btt_snapshot;
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
            dma_reader_start_pending_q <= 1'b0;
            dma_writer_start_pending_q <= 1'b0;
            dma_reader_start_addr_q <= '0;
            dma_reader_start_btt_q <= '0;
            dma_writer_start_addr_q <= '0;
            dma_writer_start_btt_q <= '0;
            dma_job_reader_addr_q <= '0;
            dma_job_writer_addr_q <= '0;
            dma_job_btt_q <= '0;
            dma_b_valid <= 1'b0;
            dma_job_start <= 1'b0;
        end else begin
            dma_job_start <= 1'b0;
            irq_clear = '0;
            aw_fire = dma_aw_valid && dma_aw_ready;
            w_fire = dma_w_valid && dma_w_ready;
            write_complete = (dma_aw_pending || aw_fire) && (dma_w_pending || w_fire) && !dma_b_valid;
            write_addr = dma_aw_pending ? dma_aw_addr_q : dma_aw_addr;
            write_data = dma_w_pending ? dma_w_data_q : dma_w_data;
            write_strb = dma_w_pending ? dma_w_strb_q : dma_w_strb;
            reader_seen = dma_reader_start_pending_q;
            writer_seen = dma_writer_start_pending_q;
            reader_addr_snapshot = dma_reader_start_addr_q;
            reader_btt_snapshot = dma_reader_start_btt_q;
            writer_addr_snapshot = dma_writer_start_addr_q;
            writer_btt_snapshot = dma_writer_start_btt_q;

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
                $display("DMA_AXI_WRITE addr=%08x data=%08x strb=%x aw_from_pending=%b w_from_pending=%b bready=%b irq_pending=%b", write_addr, write_data, write_strb, dma_aw_pending, dma_w_pending, dma_b_ready, dma_irq_pending_q);
                case (write_addr[7:0])
                    DMA_CFG_IRQ_MASK: dma_irq_mask_q <= write_data;
                    DMA_CFG_IRQ_STATUS: begin
                        if (write_strb[0]) irq_clear = write_data[1:0];
                    end
                    DMA_CFG_READER_ADDR: dma_reader_addr_q <= write_data;
                    DMA_CFG_WRITER_ADDR: dma_writer_addr_q <= write_data;
                    DMA_CFG_BTT: dma_btt_q <= write_data;
                    DMA_CFG_CTRL: begin
                        if (write_strb[0] && write_data[0]) begin
                            if (dma_reader_start_pending_q)
                                $fatal(1, "reader start repeated before it paired with a writer start");
                            reader_seen = 1'b1;
                            reader_addr_snapshot = dma_reader_addr_q;
                            reader_btt_snapshot = dma_btt_q;
                            dma_reader_start_pending_q <= 1'b1;
                            dma_reader_start_addr_q <= dma_reader_addr_q;
                            dma_reader_start_btt_q <= dma_btt_q;
                            $display("DMA_READER_START addr=%08x btt=%0d paired_before=%b", dma_reader_addr_q, dma_btt_q, dma_writer_start_pending_q);
                        end
                        if (write_strb[0] && write_data[1]) begin
                            if (dma_writer_start_pending_q)
                                $fatal(1, "writer start repeated before it paired with a reader start");
                            writer_seen = 1'b1;
                            writer_addr_snapshot = dma_writer_addr_q;
                            writer_btt_snapshot = dma_btt_q;
                            dma_writer_start_pending_q <= 1'b1;
                            dma_writer_start_addr_q <= dma_writer_addr_q;
                            dma_writer_start_btt_q <= dma_btt_q;
                            $display("DMA_WRITER_START addr=%08x btt=%0d paired_before=%b", dma_writer_addr_q, dma_btt_q, dma_reader_start_pending_q);
                        end
                        if (reader_seen && writer_seen) begin
                            if (reader_btt_snapshot != writer_btt_snapshot)
                                $fatal(1, "reader/writer starts paired different BTT values: reader=%0d writer=%0d", reader_btt_snapshot, writer_btt_snapshot);
                            dma_job_reader_addr_q <= reader_addr_snapshot;
                            dma_job_writer_addr_q <= writer_addr_snapshot;
                            dma_job_btt_q <= reader_btt_snapshot;
                            dma_job_start <= 1'b1;
                            dma_reader_start_pending_q <= 1'b0;
                            dma_writer_start_pending_q <= 1'b0;
                            $display("DMA_CHANNELS_PAIRED AR=%08x AW=%08x BTT=%0d", reader_addr_snapshot, writer_addr_snapshot, reader_btt_snapshot);
                        end
                    end
                    default: begin
                    end
                endcase
            end

            if (dma_irq_set != 2'b00 || irq_clear != 2'b00)
                dma_irq_pending_q <= (dma_irq_pending_q & ~irq_clear) | dma_irq_set;
            if (dma_irq_set != 2'b00)
                $display("DMA_IRQ_SET set=%b mask=%08x pending_before=%b", dma_irq_set, dma_irq_mask_q, dma_irq_pending_q);
            if (irq_clear != 2'b00)
                $display("DMA_IRQ_CLEAR clear=%b pending_before=%b set_same_cycle=%b", irq_clear, dma_irq_pending_q, dma_irq_set);
            if (dma_b_valid && dma_b_ready)
                $display("DMA_AXI_B_HANDSHAKE resp=%b irq_pending=%b", dma_b_resp, dma_irq_pending_q);
        end
    end

    // The reader interrupt marks the final source beat entering the one-beat
    // staging slot. The writer interrupt follows only after that final beat is
    // committed to its destination. Each sticky bit is independently W1C.
    always begin : dma_worker
        @(posedge dma_job_start);
        @(negedge clk);
        dma_transfer(dma_job_reader_addr_q, dma_job_writer_addr_q, dma_job_btt_q);
        pulse_dma_irq(2'b10);
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
        sram_trace_cycle = 0;
        measure_active = 1'b1;
        @(negedge clk);
        layer_start_ns = $realtime;
        srama_read_req_id = 0;
        sramb_read_req_id = 0;
        srama_pending_valid = 0;
        sramb_pending_valid = 0;
        psm_trace_fd = $fopen({artifact_dir, "/sramc-write-trace.txt"}, "w");
        if (psm_trace_fd == 0) $fatal(1, "cannot create SRAM C write trace");
        $fdisplay(psm_trace_fd, "# PSM_C_WRITE cycle=<n> index=<n> addr=<n> mask=<bits> data=<hex> ctx=<n> scan=<n>");
        sramc_host_trace_fd = $fopen({artifact_dir, "/sramc-host-read-trace.txt"}, "w");
        if (sramc_host_trace_fd == 0) $fatal(1, "cannot create SRAM C host read trace");
        sram_read_trace_fd = $fopen({artifact_dir, "/accelerator-sram-read-trace.txt"}, "w");
        if (sram_read_trace_fd == 0) $fatal(1, "cannot create accelerator SRAM read trace");
        ifmap_push_trace_fd = $fopen({artifact_dir, "/ifmap-fifo-push-trace.txt"}, "w");
        if (ifmap_push_trace_fd == 0) $fatal(1, "cannot create IFMAP FIFO push trace");
        fd = $fopen({artifact_dir, "/layer_window.txt"}, "w");
        if (fd == 0) $fatal(1, "cannot create layer window file");
        $fdisplay(fd, "%0.3f", layer_start_ns);
        $fclose(fd);
        $display("LAYER_START_NS=%0.3f", layer_start_ns);
        controller_write(32'h4000_0000, 32'h0000_0001);

        while ((layer_done !== 1'b1) && (layer_cycles < max_cycles_arg)) @(posedge clk);
        if (layer_done !== 1'b1) begin
            $display("TIMEOUT_DEBUG ctrl_start=%b ctrl_ready=%b ctrl_done=%b if_state=%0d dma_state=%0d dma_sub_state=%0d first_dma=%b goto_sauria=%b dma_irq_inputs=%b%b irq_mask=%08x irq_pending=%b dma_bvalid=%b dma_bready=%b dma_aw_pending=%b dma_w_pending=%b", dut.df_controller_i.start_q, dut.df_controller_i.ready_q, dut.df_controller_i.done_q, dut.df_controller_i.sauria_interface_I.state, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.state, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.sub_state, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.first_dma_iter, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.goto_sync_sauria, dma_reader_interrupt, dma_writer_interrupt, dma_irq_mask_q, dma_irq_pending_q, dma_b_valid, dma_b_ready, dma_aw_pending, dma_w_pending);
            $display("DMA_START_PENDING reader=%b addr=%08x btt=%0d writer=%b addr=%08x btt=%0d", dma_reader_start_pending_q, dma_reader_start_addr_q, dma_reader_start_btt_q, dma_writer_start_pending_q, dma_writer_start_addr_q, dma_writer_start_btt_q);
            $display("SAURIA_IF_DEBUG state=%0d addr=%08x region=%0d reg_idx=%0d count=%0d addr_sent=%b data_sent=%b start=%b wresp_sync=%b wresp_count=%0d dma_sync=%b core_irq=%b awvalid=%b awready=%b awaddr=%08x wvalid=%b wready=%b wdata=%08x bvalid=%b bready=%b", dut.df_controller_i.sauria_interface_I.state, dut.df_controller_i.sauria_interface_I.addr, dut.df_controller_i.sauria_interface_I.current_addr_region, dut.df_controller_i.sauria_interface_I.sauria_reg_idx, dut.df_controller_i.sauria_interface_I.count, dut.df_controller_i.sauria_interface_I.addr_sent, dut.df_controller_i.sauria_interface_I.data_sent, dut.df_controller_i.sauria_interface_I.start, dut.df_controller_i.sauria_interface_I.wresp_sync_state, dut.df_controller_i.sauria_interface_I.wresp_count, dut.df_controller_i.sauria_interface_I.dma_sync, sauria_done, dut.ctrl_sauria_bus.aw_valid, dut.ctrl_sauria_bus.aw_ready, dut.ctrl_sauria_bus.aw_addr, dut.ctrl_sauria_bus.w_valid, dut.ctrl_sauria_bus.w_ready, dut.ctrl_sauria_bus.w_data, dut.ctrl_sauria_bus.b_valid, dut.ctrl_sauria_bus.b_ready);
            $display("CORE_CFG_DEBUG start_q=%b start_edge=%b ready_q=%b idle_q=%b done_q=%b done_intr_q=%b global_ien_q=%b done_ien_q=%b raw_done=%b doneintr=%b incntlim=%0d act_reps=%0d wei_reps=%0d ncontexts=%0d", dut.sauria_logic_i.config_regs_i.start_q, dut.sauria_logic_i.config_regs_i.start_edge, dut.sauria_logic_i.config_regs_i.ready_q, dut.sauria_logic_i.config_regs_i.idle_q, dut.sauria_logic_i.config_regs_i.done_q, dut.sauria_logic_i.config_regs_i.done_intr_q, dut.sauria_logic_i.config_regs_i.global_ien_q, dut.sauria_logic_i.config_regs_i.done_ien_q, dut.sauria_logic_i.cg_done, sauria_done, dut.sauria_logic_i.mc_incntlim, dut.sauria_logic_i.mc_act_reps, dut.sauria_logic_i.mc_wei_reps, dut.sauria_logic_i.ob_ncontexts);
            $display("CORE_CTX_DEBUG state=%0d stall_state=%0d status=%0d pipeline_gate=%b pipeline_en=%b pop_gate=%b cdone=%b cdone_hold=%b cswitch_done=%b incnt=%0d incntlim=%0d feeders_done=%b outbuf_done=%b shift_done=%b finalwrite=%b", dut.sauria_logic_i.main_controller_i.context_fsm_i.main_state_q, dut.sauria_logic_i.main_controller_i.context_fsm_i.stall_state_q, dut.sauria_logic_i.cg_ctx_status, dut.sauria_logic_i.main_controller_i.pipeline_gate, dut.sauria_logic_i.sa_pipeline_en, dut.sauria_logic_i.main_controller_i.pop_gate, dut.sauria_logic_i.main_controller_i.cdone, dut.sauria_logic_i.main_controller_i.context_switch_controller_i.cdone_hold, dut.sauria_logic_i.main_controller_i.cswitch_done, dut.sauria_logic_i.main_controller_i.context_switch_controller_i.incnt_q, dut.sauria_logic_i.mc_incntlim, dut.sauria_logic_i.main_controller_i.feeders_done, dut.sauria_logic_i.mc_outbuf_done, dut.sauria_logic_i.mc_shift_done, dut.sauria_logic_i.mc_finalwrite);
            $display("CORE_FEED_DEBUG state=%0d status=%0d act_rep=%0d/%0d act_hold=%b act_cnt=%0d act_done=%b act_til_done=%b act_empty=%b act_full=%b act_stall=%b wei_rep=%0d/%0d wei_hold=%b wei_cnt=%0d wei_done=%b wei_til_done=%b wei_empty=%b wei_full=%b wei_stall=%b act_deadlock=%b wei_deadlock=%b feed_deadlock=%b", dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q, dut.sauria_logic_i.cg_feed_status, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_rep_cnt_q, dut.sauria_logic_i.mc_act_reps, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_cnt_hold_q, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.a_cnt, dut.sauria_logic_i.mc_act_done, dut.sauria_logic_i.mc_act_til_done, dut.sauria_logic_i.mc_act_fifo_empty, dut.sauria_logic_i.mc_act_fifo_full, dut.sauria_logic_i.mc_act_stall, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_rep_cnt_q, dut.sauria_logic_i.mc_wei_reps, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_cnt_hold_q, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.b_cnt, dut.sauria_logic_i.mc_wei_done, dut.sauria_logic_i.mc_wei_til_done, dut.sauria_logic_i.mc_wei_fifo_empty, dut.sauria_logic_i.mc_wei_fifo_full, dut.sauria_logic_i.mc_wei_stall, dut.sauria_logic_i.cg_act_deadlock, dut.sauria_logic_i.cg_wei_deadlock, dut.sauria_logic_i.cg_feed_deadlock);
            $display("CORE_CSWITCH_DEBUG cscnt=%0d cscnt_flag=%b cdone_force=%b/%b pop_shim=%b/%b", dut.sauria_logic_i.main_controller_i.context_switch_controller_i.cscnt_q, dut.sauria_logic_i.main_controller_i.context_switch_controller_i.cscnt_flag, dut.sauria_logic_i.main_controller_i.context_switch_controller_i.cdone_force_q1, dut.sauria_logic_i.main_controller_i.context_switch_controller_i.cdone_force_q2, dut.sauria_logic_i.main_controller_i.context_switch_controller_i.pop_shim_init_q, dut.sauria_logic_i.main_controller_i.context_switch_controller_i.pop_shim_q2);
            $display("CORE_PSM_DEBUG state=%0d status=%0d ctx=%0d/%0d scan=%0d pipeline_en=%b cnt_done=%b cnt_til_done=%b fifo_data=%b sram_wren=%b sram_addr=%08x sram_wmask=%x", dut.sauria_logic_i.psm_top_i.psm_shift_fsm_i.main_state_q, dut.sauria_logic_i.cg_out_status, dut.sauria_logic_i.psm_top_i.psm_shift_fsm_i.ctx_cnt, dut.sauria_logic_i.ob_ncontexts, dut.sauria_logic_i.psm_top_i.psm_shift_fsm_i.scan_cnt, dut.sauria_logic_i.sa_pipeline_en, dut.sauria_logic_i.psm_top_i.cnt_done, dut.sauria_logic_i.psm_top_i.cnt_til_done, dut.sauria_logic_i.psm_top_i.fifo_data_flag, dut.sauria_logic_i.psm_top_i.o_sramc_wren, dut.sauria_logic_i.psm_top_i.o_sramc_addr, dut.sauria_logic_i.psm_top_i.o_sramc_wmask);
            $display("CORE_MEM_DEBUG act_rden=%b act_addr=%08x act_data=%08x wei_rden=%b wei_addr=%08x wei_data=%08x", dut.sauria_logic_i.o_srama_rden, dut.sauria_logic_i.o_srama_addr, dut.sauria_logic_i.i_srama_data, dut.sauria_logic_i.o_sramb_rden, dut.sauria_logic_i.o_sramb_addr, dut.sauria_logic_i.i_sramb_data);
            $display("DMA_FSM_DEBUG next=%0d first_tile=%b addr=%08x wdata=%08x addr_sent=%b data_sent=%b start=%b start_wresp_sync=%b wresp_sync=%b wresp_count=%0d btt=%0d local_addr=%08x y=%0d/%0d z=%0d/%0d ycounter=%0d zcounter=%0d last_iter=%b ifmaps_change=%b weights_change=%b psums_change=%b", dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.next_action, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.first_tile, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.addr, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.wdata, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.addr_sent, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.data_sent, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.start, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.start_wresp_sync, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.wresp_sync_state, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.wresp_counter, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.btt, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.local_SRAM_addr, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.y, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.ylim, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.z, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.zlim, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.ycounter, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.zcounter, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.last_iter_sig, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.ifmaps_change, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.weights_change, dut.df_controller_i.sauria_interface_I.sauria_dma_controller_I.psums_change);
            $fatal(1, "layer timed out after %0d cycles; DMA jobs=%0d", layer_cycles, dma_jobs);
        end
        measure_active = 1'b0;
        $fclose(psm_trace_fd);
        $fclose(sramc_host_trace_fd);
        $fclose(sram_read_trace_fd);
        $fclose(ifmap_push_trace_fd);
        sram_read_trace_fd = 0;
        ifmap_push_trace_fd = 0;
        sramc_host_trace_fd = 0;
        sramc_dump_fd = $fopen({artifact_dir, "/srama-bank0-final.mem"}, "w");
        if (sramc_dump_fd == 0) $fatal(1, "cannot create SRAM A bank 0 dump");
        for (idx = 0; idx < sauria_pkg::SRAMA_DEPTH; idx = idx + 1)
            $fdisplay(sramc_dump_fd, "%0h", dut.sram_top_i.SRAMA_i.sram_0_i.mem[idx]);
        $fclose(sramc_dump_fd);
        sramc_dump_fd = $fopen({artifact_dir, "/srama-bank1-final.mem"}, "w");
        if (sramc_dump_fd == 0) $fatal(1, "cannot create SRAM A bank 1 dump");
        for (idx = 0; idx < sauria_pkg::SRAMA_DEPTH; idx = idx + 1)
            $fdisplay(sramc_dump_fd, "%0h", dut.sram_top_i.SRAMA_i.sram_1_i.mem[idx]);
        $fclose(sramc_dump_fd);
        sramc_dump_fd = $fopen({artifact_dir, "/sramb-bank0-final.mem"}, "w");
        if (sramc_dump_fd == 0) $fatal(1, "cannot create SRAM B bank 0 dump");
        for (idx = 0; idx < sauria_pkg::SRAMB_DEPTH; idx = idx + 1)
            $fdisplay(sramc_dump_fd, "%0h", dut.sram_top_i.SRAMB_i.sram_0_i.mem[idx]);
        $fclose(sramc_dump_fd);
        sramc_dump_fd = $fopen({artifact_dir, "/sramb-bank1-final.mem"}, "w");
        if (sramc_dump_fd == 0) $fatal(1, "cannot create SRAM B bank 1 dump");
        for (idx = 0; idx < sauria_pkg::SRAMB_DEPTH; idx = idx + 1)
            $fdisplay(sramc_dump_fd, "%0h", dut.sram_top_i.SRAMB_i.sram_1_i.mem[idx]);
        $fclose(sramc_dump_fd);
        sramc_dump_fd = $fopen({artifact_dir, "/sramc-bank0-final.mem"}, "w");
        if (sramc_dump_fd == 0) $fatal(1, "cannot create SRAM C bank 0 dump");
        for (idx = 0; idx < sauria_pkg::SRAMC_DEPTH; idx = idx + 1)
            $fdisplay(sramc_dump_fd, "%0h", dut.sram_top_i.SRAMC_i.sram_0_i.mem[idx]);
        $fclose(sramc_dump_fd);
        sramc_dump_fd = $fopen({artifact_dir, "/sramc-bank1-final.mem"}, "w");
        if (sramc_dump_fd == 0) $fatal(1, "cannot create SRAM C bank 1 dump");
        for (idx = 0; idx < sauria_pkg::SRAMC_DEPTH; idx = idx + 1)
            $fdisplay(sramc_dump_fd, "%0h", dut.sram_top_i.SRAMC_i.sram_1_i.mem[idx]);
        $fclose(sramc_dump_fd);
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

    generate
        for (genvar debug_lane = 0; debug_lane < 8; debug_lane++) begin : gen_act_drain_trace
            always @(posedge clk) begin
                if (rstn && measure_active && layer_cycles >= 11670 && layer_cycles <= 11710 &&
                    dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q == 5'd7)
                    $display("FEED_ACT_LANE cycle=%0d lane=%0d ptr=%0d offset=%0d empty=%b full=%b stall=%b push=%b pop=%b pop_en_q=%b valid=%b update=%b feeder_en=%b", layer_cycles, debug_lane, dut.sauria_logic_i.ifmap_feeder_i.y_axis[debug_lane].ifmap_feeder_i.fifo_i.ptr_q, dut.sauria_logic_i.ifmap_feeder_i.y_axis[debug_lane].ifmap_feeder_i.fifo_i.out_woffs, dut.sauria_logic_i.ifmap_feeder_i.fifo_empty[debug_lane], dut.sauria_logic_i.ifmap_feeder_i.fifo_full[debug_lane], dut.sauria_logic_i.ifmap_feeder_i.stall[debug_lane], dut.sauria_logic_i.ifmap_feeder_i.y_axis[debug_lane].ifmap_feeder_i.fifo_push, dut.sauria_logic_i.ifmap_feeder_i.y_axis[debug_lane].ifmap_feeder_i.fifo_pop, dut.sauria_logic_i.ifmap_feeder_i.y_axis[debug_lane].ifmap_feeder_i.pop_en_q, dut.sauria_logic_i.ifmap_feeder_i.valid_data, dut.sauria_logic_i.ifmap_feeder_i.feeders_update, dut.sauria_logic_i.ifmap_feeder_i.y_axis[debug_lane].ifmap_feeder_i.i_feeder_en);
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (rstn && measure_active && layer_cycles < max_cycles_arg)
            layer_cycles = layer_cycles + 1;

        if (rstn && dut.sauria_logic_i.config_regs_i.start_edge)
            $display("CORE_START_EDGE cycle=%0d ready=%b start_q=%b done_q=%b global_ien=%b done_ien=%b", layer_cycles, dut.sauria_logic_i.config_regs_i.ready_q, dut.sauria_logic_i.config_regs_i.start_q, dut.sauria_logic_i.config_regs_i.done_q, dut.sauria_logic_i.config_regs_i.global_ien_q, dut.sauria_logic_i.config_regs_i.done_ien_q);
        if (rstn && dut.sauria_logic_i.cg_done)
        if (rstn && debug_core_started_q && dut.sauria_logic_i.cg_done && !debug_core_done_q)
            $display("CORE_DONE_EDGE cycle=%0d ctx_status=%0d feed_status=%0d out_status=%0d done_intr_q=%b doneintr=%b", layer_cycles, dut.sauria_logic_i.cg_ctx_status, dut.sauria_logic_i.cg_feed_status, dut.sauria_logic_i.cg_out_status, dut.sauria_logic_i.config_regs_i.done_intr_q, sauria_done);

        if (!rstn) begin
            debug_trace_valid_q <= 1'b0;
            debug_feed_state_q <= '0;
            debug_core_started_q <= 1'b0;
            debug_core_done_q <= 1'b0;
        end else begin
            if (measure_active && (!debug_trace_valid_q ||
                dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q != debug_feed_state_q)) begin
                $display("FEED_TRACE cycle=%0d ctx=%0d feed_state=%0d feed_state_d=%0d pre_feeding=%b feed_deadlock=%b pipeline_gate=%b feeders_pipe=%b sa_pipe=%b pop_gate=%b", layer_cycles, dut.sauria_logic_i.cg_ctx_status, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.pre_feeding_flag, dut.sauria_logic_i.cg_feed_deadlock, dut.sauria_logic_i.main_controller_i.pipeline_gate, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.pipeline_en, dut.sauria_logic_i.sa_pipeline_en, dut.sauria_logic_i.main_controller_i.pop_gate);
                $display("FEED_TRACE_ACT rep=%0d/%0d rep_d=%0d ov=%b ov_shim=%b til_raw=%b til_q=%b til_shim=%b hold_d=%b hold_q=%b cnt_en=%b fifo_empty=%b fifo_full=%b stall=%b lane_empty=%b lane_full=%b lane_stall=%b rows_active=%b idx_done=%b x_ov=%b y_ov=%b ch_ov=%b rden=%b addr=%08x", dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_rep_cnt_q, dut.sauria_logic_i.mc_act_reps, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_rep_cnt_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_ov_flag, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_ov_flag_shim, dut.sauria_logic_i.mc_act_til_done, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_til_done_q, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_til_done_shim, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_cnt_hold_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_cnt_hold_q, dut.sauria_logic_i.main_controller_i.o_act_cnt_en, dut.sauria_logic_i.mc_act_fifo_empty, dut.sauria_logic_i.mc_act_fifo_full, dut.sauria_logic_i.mc_act_stall, dut.sauria_logic_i.ifmap_feeder_i.fifo_empty, dut.sauria_logic_i.ifmap_feeder_i.fifo_full, dut.sauria_logic_i.ifmap_feeder_i.stall, dut.sauria_logic_i.af_rows_active, dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.o_done, dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.x_ov_flag, dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.y_ov_flag, dut.sauria_logic_i.ifmap_feeder_i.ifmap_idxcnt_i.ch_ov_flag, dut.sauria_logic_i.o_srama_rden, dut.sauria_logic_i.o_srama_addr);
                $display("FEED_TRACE_WEI rep=%0d/%0d rep_d=%0d ov=%b ov_shim=%b done_raw=%b done_q=%b til_raw=%b til_q=%b til_shim=%b hold_d=%b hold_q=%b cnt_en=%b fifo_empty=%b fifo_full=%b stall=%b lane_empty=%b lane_full=%b lane_stall=%b cols_active=%b idx_done=%b w_ov=%b aux_ov=%b k_ov=%b rden=%b addr=%08x", dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_rep_cnt_q, dut.sauria_logic_i.mc_wei_reps, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_rep_cnt_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_ov_flag, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_ov_flag_shim, dut.sauria_logic_i.mc_wei_done, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_done_q, dut.sauria_logic_i.mc_wei_til_done, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_til_done_q, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_til_done_shim, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_cnt_hold_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.wei_cnt_hold_q, dut.sauria_logic_i.main_controller_i.o_wei_cnt_en, dut.sauria_logic_i.mc_wei_fifo_empty, dut.sauria_logic_i.mc_wei_fifo_full, dut.sauria_logic_i.mc_wei_stall, dut.sauria_logic_i.weight_feeder_i.fifo_empty, dut.sauria_logic_i.weight_feeder_i.fifo_full, dut.sauria_logic_i.weight_feeder_i.stall, dut.sauria_logic_i.wf_cols_active, dut.sauria_logic_i.weight_feeder_i.wei_idxcnt_i.o_done, dut.sauria_logic_i.weight_feeder_i.wei_idxcnt_i.w_ov_flag, dut.sauria_logic_i.weight_feeder_i.wei_idxcnt_i.aux_ov_flag, dut.sauria_logic_i.weight_feeder_i.wei_idxcnt_i.til_k_ov_flag, dut.sauria_logic_i.o_sramb_rden, dut.sauria_logic_i.o_sramb_addr);
                debug_trace_valid_q <= 1'b1;
                debug_feed_state_q <= dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q;
            end
            if (measure_active &&
                dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q == 5'd6 &&
                dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_d == 5'd7)
                $display("FEED_TERMINAL_ACT cycle=%0d q=%0d d=%0d pre_feeding=%b raw_til_done=%b til_q=%b til_shim=%b rep_q=%0d rep_d=%0d ov=%b ov_shim=%b hold_d=%b hold_q=%b cnt_en=%b fifo_empty=%b fifo_full=%b stall=%b lane_empty=%b lane_full=%b lane_stall=%b rows_active=%b act_done=%b sa_pipe=%b", layer_cycles, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.pre_feeding_flag, dut.sauria_logic_i.mc_act_til_done, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_til_done_q, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_til_done_shim, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_rep_cnt_q, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_rep_cnt_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_ov_flag, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_ov_flag_shim, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_cnt_hold_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_cnt_hold_q, dut.sauria_logic_i.main_controller_i.o_act_cnt_en, dut.sauria_logic_i.mc_act_fifo_empty, dut.sauria_logic_i.mc_act_fifo_full, dut.sauria_logic_i.mc_act_stall, dut.sauria_logic_i.ifmap_feeder_i.fifo_empty, dut.sauria_logic_i.ifmap_feeder_i.fifo_full, dut.sauria_logic_i.ifmap_feeder_i.stall, dut.sauria_logic_i.af_rows_active, dut.sauria_logic_i.mc_act_done, dut.sauria_logic_i.sa_pipeline_en);
            if (measure_active && layer_cycles >= 11670 && layer_cycles <= 11710 &&
                dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q == 5'd7)
                $display("FEED_ACT_DRAIN cycle=%0d state=%0d state_d=%0d pre_feeding=%b terminal=%b/%b hold=%b/%b cnt_en=%b fifo_empty=%b fifo_full=%b stall=%b lane_empty=%b lane_full=%b lane_stall=%b feeders_update=%b pipeline_gate=%b sa_pipe=%b pop_gate=%b", layer_cycles, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_q, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.main_state_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.pre_feeding_flag, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_til_done_shim, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_ov_flag_shim, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_cnt_hold_d, dut.sauria_logic_i.main_controller_i.feeders_fsm_i.act_cnt_hold_q, dut.sauria_logic_i.main_controller_i.o_act_cnt_en, dut.sauria_logic_i.mc_act_fifo_empty, dut.sauria_logic_i.mc_act_fifo_full, dut.sauria_logic_i.mc_act_stall, dut.sauria_logic_i.ifmap_feeder_i.fifo_empty, dut.sauria_logic_i.ifmap_feeder_i.fifo_full, dut.sauria_logic_i.ifmap_feeder_i.stall, dut.sauria_logic_i.ifmap_feeder_i.feeders_update, dut.sauria_logic_i.main_controller_i.pipeline_gate, dut.sauria_logic_i.sa_pipeline_en, dut.sauria_logic_i.main_controller_i.pop_gate);
            if (dut.sauria_logic_i.config_regs_i.start_edge)
                debug_core_started_q <= 1'b1;
            debug_core_done_q <= dut.sauria_logic_i.cg_done;
        end

        if (rstn && measure_active) begin
            if ((dut.df_controller_i.sauria_interface_I.state == 5'd4 ||
                 dut.df_controller_i.sauria_interface_I.state == 5'd5) &&
                dut.ctrl_sauria_bus.aw_valid && dut.ctrl_sauria_bus.aw_ready)
                $display("SAURIA_AXI_AW addr=%08x", dut.ctrl_sauria_bus.aw_addr);
            if (dut.df_controller_i.sauria_interface_I.state == 5'd5 &&
                dut.ctrl_sauria_bus.w_valid && dut.ctrl_sauria_bus.w_ready)
                $display("SAURIA_AXI_W data=%08x strb=%x", dut.ctrl_sauria_bus.w_data, dut.ctrl_sauria_bus.w_strb);
            if (dut.df_controller_i.sauria_interface_I.state == 5'd6 &&
                dut.ctrl_sauria_bus.b_valid && dut.ctrl_sauria_bus.b_ready)
                $display("SAURIA_AXI_B resp=%b", dut.ctrl_sauria_bus.b_resp);
        end
    end
endmodule
