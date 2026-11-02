`timescale 1ns/1ps

// 上电延时单次触发
module startup_pulse #(
    parameter integer COUNT_MAX = 100000
)(
    input  wire clk,
    input  wire reset,
    output reg  pulse
);
    reg [19:0] count;
    reg        sent;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            count <= 20'd0;
            sent  <= 1'b0;
            pulse <= 1'b0;
        end else begin
            pulse <= 1'b0;
            if (!sent) begin
                if (count == COUNT_MAX-1) begin
                    sent  <= 1'b1;
                    pulse <= 1'b1;
                end else begin
                    count <= count + 20'd1;
                end
            end
        end
    end
endmodule
