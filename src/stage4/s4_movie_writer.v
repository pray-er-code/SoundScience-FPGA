`timescale 1ns/1ps

// 动景帧专用 SDRAM 写入器
module s4_movie_writer(input clk,rst,start,abort,input [2:0] buffer_id,
 input pixel_valid,input [23:0] pixel,input [9:0] pixel_x,pixel_y,input row_last,
 output pixel_ready,idle,output cmd_valid,output [20:0] cmd_addr,output [6:0] cmd_words,input cmd_ready,cmd_done,
 input [5:0] write_index,input write_active,output [31:0] write_data);
 reg [1:0] state;reg [6:0] count,length,pad;reg [20:0] base;reg [2:0] slot;
 wire [5:0] read_address=write_active?write_index+6'd1:6'd0;
 wire store=state==0&&!abort&&pixel_valid&&pixel_ready;
 wire padding=state==1&&pad<length;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(6),.ADDR_WIDTH_B(6),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) staging(
  .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(store||padding),.addra(padding?pad[5:0]:count[5:0]),.dia(padding?32'b0:{8'b0,pixel}),.rsta(1'b0),.bea(1'b1),
  .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(read_address),.dib(32'b0),.rstb(1'b0),.beb(1'b1),.dob(write_data));
 assign pixel_ready=state==0;assign idle=state==0&&count==0;assign cmd_valid=state==2;assign cmd_addr=base;assign cmd_words=length;
 always @(posedge clk)begin
  if(rst||start)begin state<=0;count<=0;length<=0;pad<=0;base<=0;slot<=buffer_id;end
  else case(state)
   0:if(abort)count<=0;else if(store)begin
    if(count==0)base<=slot*21'h50000+pixel_y*21'd640+pixel_x;
    if(count==63||row_last)begin length<=((count+4)>>2)<<2;pad<=count+1'b1;state<=1;end else count<=count+1'b1;
   end
   1:if(pad<length)pad<=pad+1'b1;else state<=2;
   2:if(cmd_ready)state<=3;
   3:if(cmd_done)begin state<=0;count<=0;end
  endcase
 end
endmodule
