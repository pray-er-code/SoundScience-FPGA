`timescale 1ns/1ps

// 四拨码整体同步消抖
module s4_switch_filter #(parameter integer STABLE_CYCLES=1000000)(
    input clk,rst,input [3:0] switches,output reg [3:0] value);
    reg [3:0] sync1,sync2,candidate;reg [19:0] count;
    always @(posedge clk)begin
        if(rst)begin sync1<=0;sync2<=0;candidate<=0;value<=0;count<=0;end
        else begin
            sync1<=switches;sync2<=sync1;
            if(sync2!=candidate)begin candidate<=sync2;count<=0;end
            else if(count<STABLE_CYCLES-1)count<=count+1'b1;
            else value<=candidate;
        end
    end
endmodule
