`timescale 1ns/1ps

// HDMI 音频时钟恢复参数生成
module acr_generator #(
    parameter integer ACR_N = 6144
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        sample_valid,
    output reg         acr_valid,
    output reg  [19:0] acr_cts,
    output reg  [19:0] acr_n
);
    localparam integer SAMPLES_PER_ACR = ACR_N >> 7;

    reg [7:0]  sample_count;
    reg [19:0] pixel_count;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sample_count <= 8'd0;
            pixel_count  <= 20'd0;
            acr_valid    <= 1'b0;
            acr_cts      <= 20'd0;
            acr_n        <= ACR_N;
        end else begin
            acr_valid <= 1'b0;
            pixel_count <= pixel_count + 20'd1;
            if (sample_valid) begin
                if (sample_count == SAMPLES_PER_ACR-1) begin
                    sample_count <= 8'd0;
                    pixel_count  <= 20'd0;
                    acr_valid    <= 1'b1;
                    acr_cts      <= pixel_count + 20'd1;
                    acr_n        <= ACR_N;
                end else begin
                    sample_count <= sample_count + 8'd1;
                end
            end
        end
    end
endmodule
