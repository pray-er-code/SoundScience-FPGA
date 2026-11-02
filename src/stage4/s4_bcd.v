`timescale 1ns/1ps
// 二进制转十进制显示编码
module s4_bcd(input clk,rst,start,input [15:0] value,output reg [15:0] digits);
    reg [15:0] binary,bcd;reg [4:0] count;reg busy;reg [15:0] adjusted;integer i;
    always @*begin
        adjusted=bcd;for(i=0;i<4;i=i+1)if(bcd[i*4+:4]>=5)adjusted[i*4+:4]=bcd[i*4+:4]+3;
    end
    always @(posedge clk)begin
        if(rst)begin digits<=0;binary<=0;bcd<=0;count<=0;busy<=0;end
        else if(start)begin binary<=value;bcd<=0;count<=0;busy<=1;end
        else if(busy)begin
            binary<=binary<<1;bcd<={adjusted[14:0],binary[15]};
            if(count==15)begin digits<={adjusted[14:0],binary[15]};busy<=0;end else count<=count+1'b1;
        end
    end
endmodule
