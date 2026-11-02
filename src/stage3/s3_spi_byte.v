`timescale 1ns/1ps
// SPI 单字节传输引擎
module s3_spi_byte (
    input clk,rst,start,input [7:0] tx,input [7:0] divider,
    input miso,output reg sck,mosi,busy,done,output reg [7:0] rx
);
    reg [7:0] timer,shift;
    reg [3:0] bit_index;
    always @(posedge clk) begin
        if(rst) begin sck<=0;mosi<=1;busy<=0;done<=0;rx<=0;timer<=0;shift<=0;bit_index<=0;end
        else begin
            done<=0;
            if(start && !busy) begin busy<=1;sck<=0;mosi<=tx[7];shift<=tx;bit_index<=0;rx<=0;timer<=0;end
            else if(busy) begin
                if(timer>=divider-1) begin
                    timer<=0;sck<=~sck;
                    if(!sck) rx<={rx[6:0],miso};
                    else if(bit_index==7) begin busy<=0;done<=1;mosi<=1;end
                    else begin bit_index<=bit_index+1'b1;shift<={shift[6:0],1'b1};mosi<=shift[6];end
                end else timer<=timer+1'b1;
            end
        end
    end
endmodule
