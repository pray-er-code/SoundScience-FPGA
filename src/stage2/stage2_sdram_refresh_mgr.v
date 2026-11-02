`timescale 1ns / 1ps

// SDRAM 周期刷新调度
module stage2_sdram_refresh_mgr #(
    parameter integer REFRESH_PERIOD_CYCLES = 3906,
    parameter integer REFRESH_MARGIN_CYCLES = 128,
    parameter integer ACK_TIMEOUT_CYCLES = 64,
    parameter integer RECOVERY_CYCLES = 8
) (
    input             clk,
    input             rst,
    input             init_done,
    input             refresh_valid,
    input             sdr_busy,
    input             client_busy,
    output reg         app_ref_req,
    output wire        block_requests,
    output reg         refresh_fault,
    output reg [31:0]  request_count,
    output reg [31:0]  ack_count,
    output reg [2:0]   state_code
);

    localparam [2:0] ST_IDLE       = 3'd0;
    localparam [2:0] ST_WAIT_READY = 3'd1;
    localparam [2:0] ST_WAIT_ACK   = 3'd2;
    localparam [2:0] ST_WAIT_LOW   = 3'd3;
    localparam [2:0] ST_RECOVER    = 3'd4;
    localparam [2:0] ST_FAULT      = 3'd5;

    localparam integer REQUEST_CYCLE = (REFRESH_PERIOD_CYCLES > REFRESH_MARGIN_CYCLES) ?
                                       (REFRESH_PERIOD_CYCLES - REFRESH_MARGIN_CYCLES) : 1;

    reg [31:0] cycle_count;
    reg [31:0] ack_wait_count;
    reg [31:0] deadline_count;

    // 只在当前数据事务结束后发起刷新，收到确认并完成恢复才开放新事务。
    // 从刷新待处理到恢复完成，持续阻止新事务。
    assign block_requests = (state_code != ST_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            app_ref_req <= 1'b0;
            refresh_fault <= 1'b0;
            request_count <= 32'd0;
            ack_count <= 32'd0;
            cycle_count <= 32'd0;
            ack_wait_count <= 32'd0;
            deadline_count <= 32'd0;
            state_code <= ST_IDLE;
        end else begin
            app_ref_req <= 1'b0;
            if (!init_done || (state_code == ST_WAIT_ACK && refresh_valid))
                deadline_count <= 0;
            else if (deadline_count < REFRESH_PERIOD_CYCLES)
                deadline_count <= deadline_count + 1'b1;
            else begin
                refresh_fault <= 1'b1;
                state_code <= ST_FAULT;
            end

            case (state_code)
                ST_IDLE: begin
                    if (!init_done) begin
                        cycle_count <= 32'd0;
                    end else if (cycle_count >= REQUEST_CYCLE) begin
                        state_code <= ST_WAIT_READY;
                    end else begin
                        cycle_count <= cycle_count + 1'b1;
                    end
                end

                ST_WAIT_READY: begin
                    if (!init_done) begin
                        cycle_count <= 32'd0;
                        state_code <= ST_IDLE;
                    end else if (!client_busy && !sdr_busy && !refresh_valid) begin
                        app_ref_req <= 1'b1;
                        if (request_count != 32'hffff_ffff)
                            request_count <= request_count + 1'b1;
                        ack_wait_count <= 32'd0;
                        state_code <= ST_WAIT_ACK;
                    end
                end

                ST_WAIT_ACK: begin
                    if (refresh_valid) begin
                        if (ack_count != 32'hffff_ffff)
                            ack_count <= ack_count + 1'b1;
                        state_code <= ST_WAIT_LOW;
                    end else if (ack_wait_count >= ACK_TIMEOUT_CYCLES) begin
                        refresh_fault <= 1'b1;
                        state_code <= ST_FAULT;
                    end else begin
                        ack_wait_count <= ack_wait_count + 1'b1;
                    end
                end

                ST_WAIT_LOW: begin
                    if (!refresh_valid) begin
                        ack_wait_count <= 32'd0;
                        state_code <= ST_RECOVER;
                    end else if (ack_wait_count >= ACK_TIMEOUT_CYCLES) begin
                        refresh_fault <= 1'b1;
                        state_code <= ST_FAULT;
                    end else begin
                        ack_wait_count <= ack_wait_count + 1'b1;
                    end
                end

                ST_RECOVER: begin
                    if (ack_wait_count >= RECOVERY_CYCLES-1) begin
                        cycle_count <= 32'd0;
                        ack_wait_count <= 32'd0;
                        state_code <= ST_IDLE;
                    end else ack_wait_count <= ack_wait_count + 1'b1;
                end

                ST_FAULT: begin
                    refresh_fault <= 1'b1;
                end

                default: begin
                    state_code <= ST_FAULT;
                    refresh_fault <= 1'b1;
                end
            endcase
            // 刷新超时优先报错，避免静默漏刷。
            if (init_done && deadline_count >= REFRESH_PERIOD_CYCLES &&
                !(state_code == ST_WAIT_ACK && refresh_valid)) begin
                refresh_fault <= 1'b1;
                state_code <= ST_FAULT;
            end
        end
    end
endmodule
