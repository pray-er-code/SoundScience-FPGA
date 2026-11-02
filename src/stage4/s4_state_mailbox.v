`timescale 1ns/1ps

// 一致状态跨时钟域邮箱
module s4_state_mailbox #(parameter WIDTH=26)(
 input source_clk,source_rst,input [WIDTH-1:0] source_data,
 input dest_clk,dest_rst,output reg [WIDTH-1:0] dest_data);
    // 确认返回前保持整组源数据稳定，期间变化合并到下一次发布。
 reg [WIDTH-1:0] held;reg published,acknowledged;reg [1:0] ack_sync,request_sync;reg [1:0] settle;
 always @(posedge source_clk)begin
  if(source_rst)begin held<=0;published<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],acknowledged};
   if(ack_sync[1]==published&&held!=source_data)begin held<=source_data;published<=~published;end
  end
 end
 always @(posedge dest_clk)begin
  if(dest_rst)begin request_sync<=0;settle<=0;acknowledged<=0;dest_data<=0;end
  else begin
   request_sync<={request_sync[0],published};
   if(request_sync[1]==acknowledged)settle<=0;
   else if(settle!=2)settle<=settle+1'b1;
   else begin dest_data<=held;acknowledged<=request_sync[1];settle<=0;end
  end
 end
endmodule
