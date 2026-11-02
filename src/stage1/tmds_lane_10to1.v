`timescale 1ns/1ps

// 单通道 TMDS 串行化
module tmds_lane_10to1 (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       pixel_reset,
    input  wire       serial_reset,
    input  wire [9:0] parallel_data,
    output wire       serial_data
);
    reg [9:0] pixel_word;
    reg       pixel_toggle;
    reg       toggle_sync1;
    reg       toggle_sync2;
    reg       load_pulse;
    reg       load_delay1;
    reg       load_delay2;
    reg [9:0] shift_data;
    reg [1:0] oddr_data;

    // 像素下降沿锁存并行字，再同步到串行域，保留半周期时序路径。
    always @(negedge pixel_clk) begin
        if (pixel_reset) begin
            pixel_word   <= 10'd0;
            pixel_toggle <= 1'b0;
        end else begin
            pixel_word   <= parallel_data;
            pixel_toggle <= ~pixel_toggle;
        end
    end

    always @(posedge serial_clk) begin
        if (serial_reset) begin
            toggle_sync1 <= 1'b0;
            toggle_sync2 <= 1'b0;
            load_pulse   <= 1'b0;
            load_delay1  <= 1'b0;
            load_delay2  <= 1'b0;
            shift_data   <= 10'd0;
            oddr_data    <= 2'd0;
        end else begin
            toggle_sync1 <= pixel_toggle;
            toggle_sync2 <= toggle_sync1;
            load_pulse   <= toggle_sync1 ^ toggle_sync2;
            load_delay1  <= load_pulse;
            load_delay2  <= load_delay1;

            if (load_delay2)
                shift_data <= pixel_word;
            else
                shift_data <= shift_data << 2;

            oddr_data <= shift_data[9:8];
        end
    end

    EG_LOGIC_ODDR u_oddr (
        .clk (serial_clk),
        .rst (1'b0),
        .d1  (oddr_data[0]),
        .d0  (oddr_data[1]),
        .q   (serial_data)
    );
endmodule
