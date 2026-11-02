`timescale 1ns/1ps
// 单按键消抖脉冲
module s3_button #(parameter integer CYCLES=1000000)(input clk,rst,key_n,output reg pulse);
    reg [1:0] sync_key;reg stable;reg [19:0] count;
    always @(posedge clk) begin
        if(rst) begin sync_key<=3;stable<=1;count<=0;pulse<=0;end
        else begin sync_key<={sync_key[0],key_n};pulse<=0;
            if(sync_key[1]==stable) count<=0;
            else if(count>=CYCLES-1) begin stable<=sync_key[1];count<=0;if(!sync_key[1])pulse<=1;end
            else count<=count+1'b1;
        end
    end
endmodule
