`timescale 1ns/1ps

// SDRAM 统一突发应用端口
module s3_mem_port (
    input clk,rst,init_done,refresh_block,core_busy,
    input cmd_valid,cmd_write,input [20:0] cmd_addr,input [6:0] cmd_words,
    output cmd_ready,output reg done,output reg fault,
    output [5:0] write_index,input [31:0] write_data,
    output reg read_valid,output reg [5:0] read_index,output reg [31:0] read_data,
    output client_busy,output app_wr_en,app_rd_en,
    output [20:0] app_addr,output [31:0] app_data,
    input core_rd_valid,input [31:0] core_rd_data
);
    // 突发长度为 4～64 字且须为 4 的倍数，启动前备齐写数据或预留读空间。
    reg [1:0] state;
    reg is_write,seen_busy;
    reg [20:0] base;
    reg [6:0] words,issued,returned;
    reg [15:0] timeout_count;
    assign cmd_ready=state==0 && init_done && !refresh_block && !core_busy && !fault;
    assign client_busy=state!=0 || (cmd_valid && cmd_ready);
    assign app_wr_en=state==1 && is_write;
    assign app_rd_en=state==1 && !is_write;
    assign app_addr=base+issued;
    assign write_index=issued[5:0];
    assign app_data=write_data;
    always @(posedge clk) begin
        if(rst) begin state<=0;done<=0;fault<=0;read_valid<=0;seen_busy<=0;
            is_write<=0;base<=0;words<=0;issued<=0;returned<=0;timeout_count<=0;read_index<=0;read_data<=0;end
        else begin
            done<=0;read_valid<=0;
            if(state!=0) begin
                timeout_count<=timeout_count+1'b1;
                if(core_busy) seen_busy<=1;
                if(timeout_count==16'hffff) begin fault<=1;state<=3;end
            end
            if(core_rd_valid) begin
                if(state!=0 && !is_write && returned<words) begin
                    read_valid<=1;read_data<=core_rd_data;read_index<=returned[5:0];returned<=returned+1'b1;
                end else begin fault<=1;state<=3;end
            end
            case(state)
                0: if(cmd_valid && cmd_ready) begin
                    if(cmd_words<4 || cmd_words>64 || cmd_words[1:0]!=0) begin fault<=1;state<=3;end
                    else begin base<=cmd_addr;words<=cmd_words;is_write<=cmd_write;
                        issued<=0;returned<=0;seen_busy<=0;timeout_count<=0;state<=1;end
                end
                1: begin issued<=issued+1'b1;if(issued==words-1) state<=2;end
                2: if(seen_busy && !core_busy && (is_write || returned==words)) begin done<=1;state<=0;end
                3: fault<=1;
            endcase
        end
    end
endmodule
