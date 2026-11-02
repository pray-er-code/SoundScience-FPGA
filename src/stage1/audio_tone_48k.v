`timescale 1ns/1ps

// 48 kHz 测试音源
module audio_tone_48k #(
    parameter integer CLOCK_HZ   = 74242424,
    parameter integer SAMPLE_HZ  = 48000
)(
    input  wire        clk,
    input  wire        reset,
    output reg         sample_valid,
    output wire [23:0] sample_left,
    output wire [23:0] sample_right
);
    reg [31:0] sample_accumulator;
    reg [5:0]  tone_phase;

    function [23:0] triangle_pcm;
        input [5:0] phase;
        reg [5:0] magnitude;
        reg signed [23:0] scaled;
        begin
            if (phase < 12) begin
                magnitude = phase;
                scaled = $signed({1'b0, magnitude, 17'b0});
            end else if (phase < 24) begin
                magnitude = 6'd24 - phase;
                scaled = $signed({1'b0, magnitude, 17'b0});
            end else if (phase < 36) begin
                magnitude = phase - 6'd24;
                scaled = -$signed({1'b0, magnitude, 17'b0});
            end else begin
                magnitude = 6'd48 - phase;
                scaled = -$signed({1'b0, magnitude, 17'b0});
            end
            triangle_pcm = scaled;
        end
    endfunction

    assign sample_left  = triangle_pcm(tone_phase);
    assign sample_right = triangle_pcm(tone_phase);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sample_accumulator <= 32'd0;
            sample_valid       <= 1'b0;
            tone_phase         <= 6'd0;
        end else begin
            sample_valid <= 1'b0;
            if (sample_accumulator >= CLOCK_HZ-SAMPLE_HZ) begin
                sample_accumulator <= sample_accumulator - (CLOCK_HZ-SAMPLE_HZ);
                sample_valid       <= 1'b1;
                if (tone_phase == 47)
                    tone_phase <= 6'd0;
                else
                    tone_phase <= tone_phase + 6'd1;
            end else begin
                sample_accumulator <= sample_accumulator + SAMPLE_HZ;
            end
        end
    end
endmodule
