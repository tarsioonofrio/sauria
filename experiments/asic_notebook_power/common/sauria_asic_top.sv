// Experimental System + Convolution boundary for SAURIA notebook workloads.
//
// The dataflow controller and SAURIA compute core are inside the measured
// boundary. The uDMA, external DRAM, and platform AXI fabric are outside; the
// testbench services the controller's DMA command port and moves real tile
// data through the SRAM host port.
module sauria_asic_top #(
    parameter CFG_W = 32,
    parameter CFG_ADDR_W = 32,
    parameter MEM_W = 128,
    parameter MEM_ADDR_W = 32,
    parameter EXTENDED_HOST_MAP = 0
) (
    input  logic                    i_clk,
    input  logic                    i_rstn,

    // AXI-Lite host port for the SAURIA dataflow controller.
    input  logic                    i_ctrl_aw_valid,
    input  logic [31:0]             i_ctrl_aw_addr,
    input  logic [2:0]              i_ctrl_aw_prot,
    output logic                    o_ctrl_aw_ready,
    input  logic                    i_ctrl_w_valid,
    input  logic [31:0]             i_ctrl_w_data,
    input  logic [3:0]              i_ctrl_w_strb,
    output logic                    o_ctrl_w_ready,
    output logic                    o_ctrl_b_valid,
    output logic [1:0]              o_ctrl_b_resp,
    input  logic                    i_ctrl_b_ready,

    // AXI-Lite DMA command port. The testbench implements the uDMA command
    // registers and transfers BTT bytes between external memory and local SRAM.
    output logic                    o_dma_aw_valid,
    output logic [31:0]             o_dma_aw_addr,
    output logic [2:0]              o_dma_aw_prot,
    input  logic                    i_dma_aw_ready,
    output logic                    o_dma_w_valid,
    output logic [31:0]             o_dma_w_data,
    output logic [3:0]              o_dma_w_strb,
    input  logic                    i_dma_w_ready,
    input  logic                    i_dma_b_valid,
    input  logic [1:0]              i_dma_b_resp,
    output logic                    o_dma_b_ready,
    input  logic                    i_dma_reader_interrupt,
    input  logic                    i_dma_writer_interrupt,

    // Shared testbench host access to the original local SRAM banks.
    input  logic [MEM_W-1:0]        i_mem_data,
    input  logic [MEM_ADDR_W-1:0]   i_mem_addr,
    input  logic                    i_mem_wren,
    input  logic                    i_mem_rden,
    input  logic [MEM_W-1:0]        i_mem_wmask,
    output logic [MEM_W-1:0]        o_mem_data,

    output logic                    o_sauria_done,
    output logic                    o_layer_done
);

    AXI_LITE #(.AXI_ADDR_WIDTH(CFG_ADDR_W), .AXI_DATA_WIDTH(CFG_W)) ctrl_cfg_bus();
    AXI_LITE #(.AXI_ADDR_WIDTH(CFG_ADDR_W), .AXI_DATA_WIDTH(CFG_W)) ctrl_sauria_bus();
    AXI_LITE #(.AXI_ADDR_WIDTH(CFG_ADDR_W), .AXI_DATA_WIDTH(CFG_W)) ctrl_dma_bus();

    assign ctrl_cfg_bus.aw_valid = i_ctrl_aw_valid;
    assign ctrl_cfg_bus.aw_addr  = i_ctrl_aw_addr;
    assign ctrl_cfg_bus.aw_prot  = i_ctrl_aw_prot;
    assign o_ctrl_aw_ready       = ctrl_cfg_bus.aw_ready;
    assign ctrl_cfg_bus.w_valid  = i_ctrl_w_valid;
    assign ctrl_cfg_bus.w_data   = i_ctrl_w_data;
    assign ctrl_cfg_bus.w_strb   = i_ctrl_w_strb;
    assign o_ctrl_w_ready        = ctrl_cfg_bus.w_ready;
    assign o_ctrl_b_valid        = ctrl_cfg_bus.b_valid;
    assign o_ctrl_b_resp         = ctrl_cfg_bus.b_resp;
    assign ctrl_cfg_bus.b_ready  = i_ctrl_b_ready;
    assign ctrl_cfg_bus.ar_valid = 1'b0;
    assign ctrl_cfg_bus.ar_addr  = '0;
    assign ctrl_cfg_bus.ar_prot  = '0;
    assign ctrl_cfg_bus.r_ready  = 1'b1;

    assign o_dma_aw_valid = ctrl_dma_bus.aw_valid;
    assign o_dma_aw_addr  = ctrl_dma_bus.aw_addr;
    assign o_dma_aw_prot  = ctrl_dma_bus.aw_prot;
    assign ctrl_dma_bus.aw_ready = i_dma_aw_ready;
    assign o_dma_w_valid  = ctrl_dma_bus.w_valid;
    assign o_dma_w_data   = ctrl_dma_bus.w_data;
    assign o_dma_w_strb   = ctrl_dma_bus.w_strb;
    assign ctrl_dma_bus.w_ready = i_dma_w_ready;
    assign ctrl_dma_bus.b_valid = i_dma_b_valid;
    assign ctrl_dma_bus.b_resp  = i_dma_b_resp;
    assign o_dma_b_ready  = ctrl_dma_bus.b_ready;
    assign ctrl_dma_bus.ar_ready = 1'b1;
    assign ctrl_dma_bus.r_valid  = 1'b0;
    assign ctrl_dma_bus.r_data   = '0;
    assign ctrl_dma_bus.r_resp   = '0;

    logic [CFG_ADDR_W-1:0]         cfg_addr;
    logic [CFG_W-1:0]              cfg_data;
    logic [CFG_W-1:0]              cfg_wmask;
    logic                          cfg_wren;
    logic                          cfg_rden;
    logic [CFG_W-1:0]              cfg_rdata;

    sauria_cfg_axil_to_logic #(
        .ADDR_W(CFG_ADDR_W),
        .DATA_W(CFG_W)
    ) core_cfg_adapter_i (
        .clk       (i_clk),
        .rstn      (i_rstn),
        .axi       (ctrl_sauria_bus),
        .address   (cfg_addr),
        .data_in   (cfg_data),
        .wmask     (cfg_wmask),
        .wren      (cfg_wren),
        .rden      (cfg_rden),
        .data_out  (cfg_rdata)
    );

    logic [sauria_pkg::SRAMA_W-1:0] srama_data;
    logic [sauria_pkg::ADRA_W-1:0]  srama_addr;
    logic                           srama_rden;
    logic [sauria_pkg::SRAMB_W-1:0] sramb_data;
    logic [sauria_pkg::ADRB_W-1:0]  sramb_addr;
    logic                           sramb_rden;
    logic [sauria_pkg::SRAMC_W-1:0] sramc_rdata;
    logic [sauria_pkg::SRAMC_W-1:0] sramc_wdata;
    logic [sauria_pkg::ADRC_W-1:0]  sramc_addr;
    logic [0:sauria_pkg::SRAMC_N-1] sramc_wmask;
    logic                           sramc_wren;
    logic                           sramc_rden;
    logic [0:2]                     sram_select;
    logic                           sram_deepsleep;
    logic                           sram_powergate;

    sauria_logic #(
        .IF_W       (CFG_W),
        .IF_ADR_W   (CFG_ADDR_W),
        .ADRA_W     (sauria_pkg::ADRA_W),
        .SRAMA_W    (sauria_pkg::SRAMA_W),
        .ADRB_W     (sauria_pkg::ADRB_W),
        .SRAMB_W    (sauria_pkg::SRAMB_W),
        .ADRC_W     (sauria_pkg::ADRC_W),
        .SRAMC_W    (sauria_pkg::SRAMC_W),
        .SRAMC_N    (sauria_pkg::SRAMC_N)
    ) sauria_logic_i (
        .i_clk              (i_clk),
        .i_rstn             (i_rstn),
        .i_data_in          (cfg_data),
        .i_address          (cfg_addr),
        .i_wren             (cfg_wren),
        .i_rden             (cfg_rden),
        .i_wmask            (cfg_wmask),
        .o_data_out         (cfg_rdata),
        .i_srama_data       (srama_data),
        .o_srama_addr       (srama_addr),
        .o_srama_rden       (srama_rden),
        .i_sramb_data       (sramb_data),
        .o_sramb_addr       (sramb_addr),
        .o_sramb_rden       (sramb_rden),
        .i_sramc_rdata      (sramc_rdata),
        .o_sramc_addr       (sramc_addr),
        .o_sramc_rden       (sramc_rden),
        .o_sramc_wren       (sramc_wren),
        .o_sramc_wmask      (sramc_wmask),
        .o_sramc_wdata      (sramc_wdata),
        .o_sram_select      (sram_select),
        .o_sram_deepsleep   (sram_deepsleep),
        .o_sram_powergate   (sram_powergate),
        .o_doneintr         (o_sauria_done)
    );

    sram_top #(
        .IF_W       (MEM_W),
        .IF_ADR_W   (MEM_ADDR_W),
        .ADRA_W     (sauria_pkg::ADRA_W),
        .SRAMA_W    (sauria_pkg::SRAMA_W),
        .RF_A       (sauria_pkg::RF_A),
        .ADRB_W     (sauria_pkg::ADRB_W),
        .SRAMB_W    (sauria_pkg::SRAMB_W),
        .RF_B       (sauria_pkg::RF_B),
        .ADRC_W     (sauria_pkg::ADRC_W),
        .SRAMC_W    (sauria_pkg::SRAMC_W),
        .RF_C       (sauria_pkg::RF_C),
        .SRAMC_N    (sauria_pkg::SRAMC_N),
        .EXTENDED_HOST_MAP (EXTENDED_HOST_MAP)
    ) sram_top_i (
        .i_clk              (i_clk),
        .i_rstn             (i_rstn),
        .i_deepsleep        (sram_deepsleep),
        .i_powergate        (sram_powergate),
        .i_select           (sram_select),
        .i_data             (i_mem_data),
        .i_address          (i_mem_addr),
        .i_wren             (i_mem_wren),
        .i_wmask            (i_mem_wmask),
        .i_rden             (i_mem_rden),
        .o_data_out         (o_mem_data),
        .i_srama_addr       (srama_addr),
        .i_srama_rden       (srama_rden),
        .o_srama_data       (srama_data),
        .i_sramb_addr       (sramb_addr),
        .i_sramb_rden       (sramb_rden),
        .o_sramb_data       (sramb_data),
        .i_sramc_data       (sramc_wdata),
        .i_sramc_addr       (sramc_addr),
        .i_sramc_wmask      (sramc_wmask),
        .i_sramc_wren       (sramc_wren),
        .i_sramc_rden       (sramc_rden),
        .o_sramc_data       (sramc_rdata)
    );

    df_controller_top #(
        .AXI_LITE_DATA_WIDTH (CFG_W),
        .AXI_LITE_ADDR_WIDTH (CFG_ADDR_W)
    ) df_controller_i (
        .clk                          (i_clk),
        .rst                          (!i_rstn),
        .sauria_interrupt_in          (o_sauria_done),
        .fwd_sauria_interrupt_out     (),
        .dma_reader_interrupt_in      (i_dma_reader_interrupt),
        .fwd_dma_reader_interrupt_out (),
        .dma_writer_interrupt_in      (i_dma_writer_interrupt),
        .fwd_dma_writer_interrupt_out (),
        .cfg_slv                      (ctrl_cfg_bus),
        .sauria_mst                   (ctrl_sauria_bus),
        .dma_mst                      (ctrl_dma_bus),
        .control_interrput_out        (o_layer_done)
    );

endmodule

module sauria_cfg_axil_to_logic #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32
) (
    input logic clk,
    input logic rstn,
    AXI_LITE.Slave axi,
    output logic [ADDR_W-1:0] address,
    output logic [DATA_W-1:0] data_in,
    output logic [DATA_W-1:0] wmask,
    output logic wren,
    output logic rden,
    input logic [DATA_W-1:0] data_out
);
    typedef logic [ADDR_W-1:0] addr_lite_t;
    typedef logic [DATA_W-1:0] data_lite_t;
    typedef logic [DATA_W/8-1:0] strb_lite_t;
    `AXI_LITE_TYPEDEF_AW_CHAN_T(aw_chan_lite_t, addr_lite_t)
    `AXI_LITE_TYPEDEF_W_CHAN_T(w_chan_lite_t, data_lite_t, strb_lite_t)
    `AXI_LITE_TYPEDEF_B_CHAN_T(b_chan_lite_t)
    `AXI_LITE_TYPEDEF_AR_CHAN_T(ar_chan_lite_t, addr_lite_t)
    `AXI_LITE_TYPEDEF_R_CHAN_T(r_chan_lite_t, data_lite_t)
    `AXI_LITE_TYPEDEF_REQ_T(cfg_req_lite_t, aw_chan_lite_t, w_chan_lite_t, ar_chan_lite_t)
    `AXI_LITE_TYPEDEF_RESP_T(cfg_resp_lite_t, b_chan_lite_t, r_chan_lite_t)

    cfg_req_lite_t cfg_req;
    cfg_resp_lite_t cfg_resp;

    // This experimental core wrapper adapts the controller's independent
    // AXI-Lite AW/W sequencing to axi_lite_2ram, whose write target accepts
    // the two channels together. Hold one payload from each channel until a
    // complete pair is available, then keep the target BREADY asserted while
    // a one-entry response slot is free. The controller may consume B later.
    logic aw_pending_q;
    logic w_pending_q;
    logic b_pending_q;
    aw_chan_lite_t aw_payload_q;
    w_chan_lite_t w_payload_q;
    axi_pkg::resp_t b_resp_q;

    always_comb begin
        cfg_req = '0;
        cfg_req.aw_valid = aw_pending_q;
        cfg_req.aw = aw_payload_q;
        cfg_req.w_valid = w_pending_q;
        cfg_req.w = w_payload_q;
        cfg_req.b_ready = !b_pending_q;
        cfg_req.ar_valid = axi.ar_valid;
        cfg_req.ar.addr = axi.ar_addr;
        cfg_req.ar.prot = axi.ar_prot;
        cfg_req.r_ready = axi.r_ready;

        axi.aw_ready = !aw_pending_q && !b_pending_q;
        axi.w_ready = !w_pending_q && !b_pending_q;
        axi.b_valid = b_pending_q;
        axi.b_resp = b_resp_q;
        axi.ar_ready = cfg_resp.ar_ready;
        axi.r_valid = cfg_resp.r_valid;
        axi.r_data = cfg_resp.r.data;
        axi.r_resp = cfg_resp.r.resp;
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            aw_pending_q <= 1'b0;
            w_pending_q <= 1'b0;
            b_pending_q <= 1'b0;
            aw_payload_q <= '0;
            w_payload_q <= '0;
            b_resp_q <= axi_pkg::RESP_OKAY;
        end else begin
            if (axi.aw_valid && axi.aw_ready) begin
                aw_payload_q.addr <= axi.aw_addr;
                aw_payload_q.prot <= axi.aw_prot;
                aw_pending_q <= 1'b1;
            end
            if (axi.w_valid && axi.w_ready) begin
                w_payload_q.data <= axi.w_data;
                w_payload_q.strb <= axi.w_strb;
                w_pending_q <= 1'b1;
            end
            if (cfg_req.aw_valid && cfg_resp.aw_ready) aw_pending_q <= 1'b0;
            if (cfg_req.w_valid && cfg_resp.w_ready) w_pending_q <= 1'b0;

            if (cfg_resp.b_valid && cfg_req.b_ready) begin
                b_resp_q <= cfg_resp.b.resp;
                b_pending_q <= 1'b1;
            end
            if (axi.b_valid && axi.b_ready) b_pending_q <= 1'b0;
        end
    end

    axi_lite_2ram #(
        .AxiAddrWidth (ADDR_W),
        .AxiDataWidth (DATA_W),
        .READ_LATENCY (1),
        .PrivProtOnly (1'b0),
        .SecuProtOnly (1'b0),
        .req_lite_t   (cfg_req_lite_t),
        .resp_lite_t  (cfg_resp_lite_t)
    ) cfg_adapter_i (
        .clk_i       (clk),
        .rst_ni      (rstn),
        .axi_req_i   (cfg_req),
        .axi_resp_o  (cfg_resp),
        .ram_addr_o  (address),
        .ram_din_o   (data_in),
        .ram_wmask_o (wmask),
        .ram_wren_o  (wren),
        .ram_rden_o  (rden),
        .ram_dout_i  (data_out)
    );
endmodule
