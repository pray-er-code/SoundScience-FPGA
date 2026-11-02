`timescale 1ns/1ps

// 复位延时释放
module reset_release #(
    parameter integer HOLD_BITS = 20
)(
    input  wire clk,
    input  wire async_reset,
    output reg  reset_out
);
    reg [HOLD_BITS-1:0] hold_count;

    always @(posedge clk or posedge async_reset) begin
        if (async_reset) begin
            hold_count <= {HOLD_BITS{1'b0}};
            reset_out  <= 1'b1;
        end else if (!(&hold_count)) begin
            hold_count <= hold_count + {{(HOLD_BITS-1){1'b0}}, 1'b1};
            reset_out  <= 1'b1;
        end else begin
            hold_count <= hold_count;
            reset_out  <= 1'b0;
        end
    end
endmodule
