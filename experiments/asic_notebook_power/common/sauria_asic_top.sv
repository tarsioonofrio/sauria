// Experimental ASIC boundary for SAURIA system + convolution.
//
// This wrapper keeps the original SAURIA logic, feeders, systolic array,
// partial-sum manager, and local SRAMs while leaving CPU, DMA, and AXI
// infrastructure outside the synthesis boundary.
module sauria_asic_top #(
    parameter CFG_W = 32,
    parameter CFG_ADDR_W = 32,
    parameter MEM_W = 128,
    parameter MEM_ADDR_W = 32,
    parameter EXTENDED_HOST_MAP = 1
) (
    input  logic                    i_clk,
    input  logic                    i_rstn,

    // Direct configuration-register access.
    input  logic [CFG_W-1:0]         i_cfg_data,
    input  logic [CFG_ADDR_W-1:0]    i_cfg_addr,
    input  logic                    i_cfg_wren,
    input  logic                    i_cfg_rden,
    input  logic [CFG_W-1:0]         i_cfg_wmask,
    output logic [CFG_W-1:0]         o_cfg_data,

    // Shared host-side port for loading activations/weights and reading
    // outputs. Bandwidth throttling is a simulation concern, not an AXI width.
    input  logic [MEM_W-1:0]         i_mem_data,
    input  logic [MEM_ADDR_W-1:0]    i_mem_addr,
    input  logic                    i_mem_wren,
    input  logic                    i_mem_rden,
    input  logic [MEM_W-1:0]         i_mem_wmask,
    output logic [MEM_W-1:0]         o_mem_data,

    output logic                    o_doneintr
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

    logic [0:2] sram_select;
    logic       sram_deepsleep;
    logic       sram_powergate;

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
        .i_data_in          (i_cfg_data),
        .i_address          (i_cfg_addr),
        .i_wren             (i_cfg_wren),
        .i_rden             (i_cfg_rden),
        .i_wmask            (i_cfg_wmask),
        .o_data_out         (o_cfg_data),
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
        .o_doneintr         (o_doneintr)
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

endmodule
