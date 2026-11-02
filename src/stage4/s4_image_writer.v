`timescale 1ns/1ps
// 图片像素到 SDRAM 突发写入
module s4_image_writer (
    input clk,rst,start,abort,input [2:0] buffer_id,
    input pixel_valid,input [23:0] pixel,input [9:0] pixel_x,pixel_y,input row_last,
    output pixel_ready,output idle,
    output cmd_valid,output [20:0] cmd_addr,output [6:0] cmd_words,input cmd_ready,cmd_done,
    input [5:0] write_index,input write_active,output [31:0] write_data,output reg [31:0] written_pixels
);
    reg [1:0] state;
    reg [6:0] count,length,pad_index;
    reg [20:0] base;
    reg [2:0] page;
    wire [20:0] slot_base=page*21'h50000;
    // 每次新命令前预取第零字，避免沿用上一事务末尾的读索引。
    wire [5:0] next_read=write_active?(write_index+6'd1):6'd0;
    wire store_pixel=state==0&&!abort&&pixel_valid&&pixel_ready;
    wire store_pad=state==1&&pad_index<length;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(6),.ADDR_WIDTH_B(6),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) staging(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(store_pixel||store_pad),.addra(store_pad?pad_index[5:0]:count[5:0]),.dia(store_pad?32'b0:{8'b0,pixel}),.rsta(1'b0),.bea(1'b1),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(next_read),.dib(32'b0),.rstb(1'b0),.beb(1'b1),.dob(write_data));
    assign pixel_ready=state==0;
    assign idle=state==0 && count==0;
    assign cmd_valid=state==2;
    assign cmd_addr=base;
    assign cmd_words=length;
    always @(posedge clk) begin
        if(rst || start) begin state<=0;count<=0;length<=0;pad_index<=0;base<=0;page<=buffer_id;written_pixels<=0;end
        else case(state)
            0:if(abort) count<=0;else if(pixel_valid && pixel_ready) begin
                written_pixels<=written_pixels+1'b1;
                if(count==0) base<=slot_base+pixel_y*640+pixel_x;
                if(count==63 || row_last) begin length<=((count+4)>>2)<<2;pad_index<=count+1'b1;state<=1;end
                else count<=count+1'b1;
            end
            1:if(pad_index<length) begin pad_index<=pad_index+1'b1;end else state<=2;
            2:if(cmd_ready) state<=3;
            3:if(cmd_done) begin state<=0;count<=0;end
        endcase
    end
endmodule

