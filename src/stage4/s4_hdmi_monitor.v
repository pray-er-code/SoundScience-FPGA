`timescale 1ns/1ps

// HDMI 编码输出诊断
module s4_hdmi_monitor (
    input  wire        clk,
    input  wire        reset,
    input  wire [9:0]  channel0,
    input  wire [9:0]  channel1,
    input  wire [9:0]  channel2,
    output reg  [31:0] audio_packet_count,
    output reg  [31:0] nonzero_audio_count,
    output reg  [31:0] acr_packet_count,
    output reg  [31:0] avi_packet_count,
    output reg  [31:0] decode_error_count,
    output reg  [19:0] last_cts,
    output reg [31:0] audio_infoframe_count,
    output reg [7:0] first_error,
    output reg  [19:0] last_n
);
    localparam SEARCH  = 2'd0;
    localparam GUARD   = 2'd1;
    localparam PAYLOAD = 2'd2;

    reg [1:0]  state;
    reg [3:0]  preamble_count;
    reg [1:0]  guard_count;
    reg        reverse_bits;
    reg [5:0]  symbol_count;
    reg [31:0] header;
    reg [63:0] payload0;
    // 子包零保留完整数据，以提取音频时钟恢复参数 N/CTS。
    reg payload1_nonzero, payload2_nonzero, payload3_nonzero;
    reg [4:0] packet_event;

    function [9:0] bit_reverse10;
        input [9:0] value;
        begin
            bit_reverse10 = {value[0], value[1], value[2], value[3], value[4],
                             value[5], value[6], value[7], value[8], value[9]};
        end
    endfunction

    function [4:0] decode_terc4;
        input [9:0] code;
        begin
            case (code)
                10'h29c: decode_terc4 = 5'h10;
                10'h263: decode_terc4 = 5'h11;
                10'h2e4: decode_terc4 = 5'h12;
                10'h2e2: decode_terc4 = 5'h13;
                10'h171: decode_terc4 = 5'h14;
                10'h11e: decode_terc4 = 5'h15;
                10'h18e: decode_terc4 = 5'h16;
                10'h13c: decode_terc4 = 5'h17;
                10'h2cc: decode_terc4 = 5'h18;
                10'h139: decode_terc4 = 5'h19;
                10'h19c: decode_terc4 = 5'h1a;
                10'h2c6: decode_terc4 = 5'h1b;
                10'h28e: decode_terc4 = 5'h1c;
                10'h271: decode_terc4 = 5'h1d;
                10'h163: decode_terc4 = 5'h1e;
                10'h2c3: decode_terc4 = 5'h1f;
                default: decode_terc4 = 5'h00;
            endcase
        end
    endfunction

    wire normal_preamble = (channel1 == 10'h0ab) && (channel2 == 10'h0ab);
    wire reverse_preamble = (channel1 == 10'h354) && (channel2 == 10'h354);
    wire normal_guard = (channel1 == 10'h133) && (channel2 == 10'h133);
    wire reverse_guard = (channel1 == 10'h332) && (channel2 == 10'h332);

    wire [9:0] ordered0 = reverse_bits ? bit_reverse10(channel0) : channel0;
    wire [9:0] ordered1 = reverse_bits ? bit_reverse10(channel1) : channel1;
    wire [9:0] ordered2 = reverse_bits ? bit_reverse10(channel2) : channel2;
    wire [4:0] nibble0 = decode_terc4(ordered0);
    wire [4:0] nibble1 = decode_terc4(ordered1);
    wire [4:0] nibble2 = decode_terc4(ordered2);
    wire all_terc4 = nibble0[4] && nibble1[4] && nibble2[4];

    wire [31:0] next_header  = {nibble0[2], header[31:1]};
    wire [63:0] next_payload0 = {nibble2[0], nibble1[0], payload0[63:2]};

    wire guard_matches = reverse_bits ? reverse_guard : normal_guard;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state               <= SEARCH;
            preamble_count      <= 4'd0;
            guard_count         <= 2'd0;
            reverse_bits        <= 1'b0;
            symbol_count        <= 6'd0;
            header              <= 32'd0;
            payload0            <= 64'd0;
            payload1_nonzero    <= 1'b0;
            payload2_nonzero    <= 1'b0;
            payload3_nonzero    <= 1'b0;
            audio_packet_count  <= 16'd0;
            nonzero_audio_count <= 16'd0;
            acr_packet_count    <= 16'd0;
            avi_packet_count    <= 16'd0;
            decode_error_count  <= 16'd0;
            last_cts            <= 20'd0;
            last_n              <= 20'd0;
            audio_infoframe_count<=0;first_error<=0;
            packet_event<=0;
        end else begin
            packet_event<=0;
            // 计数达到上限后保持，输出高位补零。
            if(packet_event[0]&&acr_packet_count!=32'h00ffffff)acr_packet_count<={8'd0,acr_packet_count[23:0]+24'd1};
            if(packet_event[1]&&audio_packet_count!=32'h00ffffff)audio_packet_count<={8'd0,audio_packet_count[23:0]+24'd1};
            if(packet_event[2]&&nonzero_audio_count!=32'h00ffffff)nonzero_audio_count<={8'd0,nonzero_audio_count[23:0]+24'd1};
            if(packet_event[3]&&audio_infoframe_count!=32'h00ffffff)audio_infoframe_count<={8'd0,audio_infoframe_count[23:0]+24'd1};
            if(packet_event[4]&&avi_packet_count!=32'h00ffffff)avi_packet_count<={8'd0,avi_packet_count[23:0]+24'd1};
            case (state)
                SEARCH: begin
                    guard_count <= 2'd0;
                    if (normal_preamble) begin
                        reverse_bits <= 1'b0;
                        if (preamble_count < 4'd8)
                            preamble_count <= preamble_count + 4'd1;
                    end else if (reverse_preamble) begin
                        reverse_bits <= 1'b1;
                        if (preamble_count < 4'd8)
                            preamble_count <= preamble_count + 4'd1;
                    end else if ((preamble_count >= 4'd8) && guard_matches) begin
                        state          <= GUARD;
                        guard_count    <= 2'd1;
                        preamble_count <= 4'd0;
                    end else begin
                        preamble_count <= 4'd0;
                    end
                end

                GUARD: begin
                    if (guard_matches) begin
                        if (guard_count == 2'd1) begin
                            state        <= PAYLOAD;
                            symbol_count <= 6'd0;
                            header       <= 32'd0;
                            payload0     <= 64'd0;
                            payload1_nonzero <= 1'b0;
                            payload2_nonzero <= 1'b0;
                            payload3_nonzero <= 1'b0;
                        end else begin
                            guard_count <= guard_count + 2'd1;
                        end
                    end else begin
                        state <= SEARCH;
                        preamble_count <= 4'd0;
                    end
                end

                PAYLOAD: begin
                    if (!all_terc4) begin
                        state <= SEARCH;
                        preamble_count <= 4'd0;
                        if ((symbol_count != 0) && (decode_error_count != 32'h00ffffff))
                            begin decode_error_count <= {8'd0,decode_error_count[23:0]+24'd1};if(first_error==0)first_error<=1;end
                    end else begin
                        header   <= next_header;
                        payload0 <= next_payload0;
                        if(symbol_count<24)begin
                            payload1_nonzero<=payload1_nonzero|nibble2[1]|nibble1[1];
                            payload2_nonzero<=payload2_nonzero|nibble2[2]|nibble1[2];
                            payload3_nonzero<=payload3_nonzero|nibble2[3]|nibble1[3];
                        end

                        if (symbol_count == 6'd31) begin
                            // 同一数据岛可能包含多个连续数据包。
                            symbol_count <= 6'd0;
                            header       <= 32'd0;
                            payload0     <= 64'd0;
                            payload1_nonzero <= 1'b0;
                            payload2_nonzero <= 1'b0;
                            payload3_nonzero <= 1'b0;
                            case (next_header[7:0])
                                8'h01: begin
                                    packet_event[0]<=1;
                                    last_cts <= {next_payload0[11:8],
                                                 next_payload0[23:16],
                                                 next_payload0[31:24]};
                                    last_n <= {next_payload0[35:32],
                                               next_payload0[47:40],
                                               next_payload0[55:48]};
                                end
                                8'h02: begin
                                    packet_event[1]<=1;
                                    if (((next_header[8]  && (next_payload0[47:0] != 48'd0))) ||
                                        ((next_header[9]  && payload1_nonzero)) ||
                                        ((next_header[10] && payload2_nonzero)) ||
                                        ((next_header[11] && payload3_nonzero)))
                                        packet_event[2]<=1;
                                end
                                8'h84: packet_event[3]<=1;
                                8'h82: packet_event[4]<=1;
                                default: begin end
                            endcase
                        end else begin
                            symbol_count <= symbol_count + 6'd1;
                        end
                    end
                end

                default: state <= SEARCH;
            endcase
        end
    end
endmodule

