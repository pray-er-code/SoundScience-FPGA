`timescale 1ns/1ps

// 视频字节弹性缓冲
module s4_movie_fifo(input clk,rst,clear,input in_valid,input [7:0] in_data,input in_last,output in_ready,
 output reg out_valid,output [7:0] out_data,output out_last,input out_ready,output reg [10:0] level,output reg overflow);
    // 保留一个完整扇区的接收余量，避免视频反压阻塞音频补充。
 reg [9:0] wr,rd;reg pending;reg [8:0] held;wire [8:0] ram_data;
 wire push=in_valid&&in_ready,pop=out_valid&&out_ready;
 assign in_ready=level<1024;assign out_data=held[7:0];assign out_last=held[8];
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(9),.DATA_WIDTH_B(9),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) storage(
  .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(push),.addra(wr),.dia({in_last,in_data}),.rsta(1'b0),.bea(1'b1),
  .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(rd),.dib(9'b0),.rstb(1'b0),.beb(1'b1),.dob(ram_data));
 always @(posedge clk)begin
  if(rst||clear)begin wr<=0;rd<=0;level<=0;pending<=0;out_valid<=0;held<=0;overflow<=0;end
  else begin
   if(in_valid&&!in_ready)overflow<=1;
   case({push,pop})2'b10:level<=level+1'b1;2'b01:level<=level-1'b1;endcase
   if(push)wr<=wr+1'b1;
   if(pop)begin rd<=rd+1'b1;out_valid<=0;end
   if(pending)begin held<=ram_data;out_valid<=1;pending<=0;end
   else if(!out_valid&&level!=0)pending<=1;
  end
 end
endmodule
