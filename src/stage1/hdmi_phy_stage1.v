`timescale 1ns/1ps

// HDMI 物理输出封装
module hdmi_phy_stage1 (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       pixel_reset,
    input  wire       serial_reset,
    input  wire [9:0] channel0,
    input  wire [9:0] channel1,
    input  wire [9:0] channel2,
    input  wire [9:0] channel_clock,
    output wire       tmds_d0_p,
    output wire       tmds_d1_p,
    output wire       tmds_d2_p,
    output wire       tmds_clk_p
);
    function [9:0] reverse10;
        input [9:0] value;
        begin
            reverse10 = {value[0], value[1], value[2], value[3], value[4],
                         value[5], value[6], value[7], value[8], value[9]};
        end
    endfunction

    tmds_lane_10to1 u_lane0 (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .pixel_reset(pixel_reset), .serial_reset(serial_reset),
        .parallel_data(reverse10(channel0)), .serial_data(tmds_d0_p)
    );
    tmds_lane_10to1 u_lane1 (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .pixel_reset(pixel_reset), .serial_reset(serial_reset),
        .parallel_data(reverse10(channel1)), .serial_data(tmds_d1_p)
    );
    tmds_lane_10to1 u_lane2 (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .pixel_reset(pixel_reset), .serial_reset(serial_reset),
        .parallel_data(reverse10(channel2)), .serial_data(tmds_d2_p)
    );
    tmds_lane_10to1 u_lane_clock (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .pixel_reset(pixel_reset), .serial_reset(serial_reset),
        .parallel_data(reverse10(channel_clock)), .serial_data(tmds_clk_p)
    );
endmodule
