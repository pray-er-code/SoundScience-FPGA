`timescale 1ns/1ps

// SDRAM 读数据对齐
module stage2_sdram_read_align #(
    parameter integer DELAY_CYCLES = 1
) (
    input clk, rst,
    input raw_valid,
    input [31:0] raw_data,
    output aligned_valid,
    output [31:0] aligned_data
);
    // 只延迟返回数据，保留原有效信号；延迟参数须与控制器时序匹配。
    reg [31:0] previous_data;
    always @(posedge clk) begin
        if (rst) previous_data <= 32'd0;
        else previous_data <= raw_data;
    end
    assign aligned_valid = raw_valid;
    assign aligned_data = (DELAY_CYCLES == 1) ? previous_data : raw_data;
endmodule
