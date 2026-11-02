`timescale 1ns/1ps

// 相关时钟域复位桥
module reset_bridge #(
    parameter integer STAGES = 4
)(
    input  wire clk,
    input  wire async_reset,
    output wire reset_out
);
    reg              request_latched;
    reg              request_sync;
    reg [STAGES-1:0] sync_pipe;

    // 目标域下降沿先采样复位请求，为相关时钟留出时序裕量。
    always @(negedge clk)
        request_latched <= async_reset;

    always @(posedge clk) begin
        request_sync <= request_latched;
        if (request_sync)
            sync_pipe <= {STAGES{1'b1}};
        else
            sync_pipe <= {sync_pipe[STAGES-2:0], 1'b0};
    end

    assign reset_out = sync_pipe[STAGES-1];
endmodule
