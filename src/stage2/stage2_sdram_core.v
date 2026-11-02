`timescale 1ns / 1ps

// 官方 SDRAM 控制器封装
module stage2_sdram_core (
    input             clk,
    input             clk_sft,
    input             rst,
    input             app_ref_req,
    output            sdr_init_done,
    output            sdr_init_ref_vld,
    output            sdr_busy,
    input             app_wr_en,
    input [20:0]      app_wr_addr,
    input [3:0]       app_wr_dm,
    input [31:0]      app_wr_din,
    input             app_rd_en,
    input [20:0]      app_rd_addr,
    output            sdr_rd_en,
    output [31:0]     sdr_rd_dout
);
    wire sdram_clk;
    wire sdram_ras_n;
    wire sdram_cas_n;
    wire sdram_we_n;
    wire [1:0] sdram_ba;
    wire [10:0] sdram_addr;
    wire [3:0] sdram_dm;
    wire [31:0] sdram_dq;

    sdr_as_ram #(.self_refresh_open(1'b0)) official_controller (
        .Sdr_clk(clk),
        .Sdr_clk_sft(clk_sft),
        .Rst(rst),
        .Sdr_init_done(sdr_init_done),
        .Sdr_init_ref_vld(sdr_init_ref_vld),
        .Sdr_busy(sdr_busy),
        .App_ref_req(app_ref_req),
        .App_wr_en(app_wr_en),
        .App_wr_addr(app_wr_addr),
        .App_wr_dm(app_wr_dm),
        .App_wr_din(app_wr_din),
        .App_rd_en(app_rd_en),
        .App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdr_rd_en),
        .Sdr_rd_dout(sdr_rd_dout),
        .SDRAM_CLK(sdram_clk),
        .SDR_RAS(sdram_ras_n),
        .SDR_CAS(sdram_cas_n),
        .SDR_WE(sdram_we_n),
        .SDR_BA(sdram_ba),
        .SDR_ADDR(sdram_addr),
        .SDR_DM(sdram_dm),
        .SDR_DQ(sdram_dq)
    );

    EG_PHY_SDRAM_2M_32 memory_primitive (
        .clk(sdram_clk),
        .ras_n(sdram_ras_n),
        .cas_n(sdram_cas_n),
        .we_n(sdram_we_n),
        .addr(sdram_addr),
        .ba(sdram_ba),
        .dq(sdram_dq),
        .cs_n(1'b0),
        .dm0(sdram_dm[0]),
        .dm1(sdram_dm[1]),
        .dm2(sdram_dm[2]),
        .dm3(sdram_dm[3]),
        .cke(1'b1)
    );
endmodule
