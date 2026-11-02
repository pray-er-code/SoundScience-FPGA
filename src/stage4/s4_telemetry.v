`timescale 1ns/1ps

// 完整诊断的双缓冲遥测
module s4_telemetry(input pixel_clk,pixel_rst,input [639:0] records,
    input mem_clk,mem_rst,input [4:0] index,output reg [31:0] value,
    output reg [31:0] underflows,pcm_underflows,output reg [31:0] flags);
    // 先写非活动分区，等待读取端切换并排空旧流水后再复用旧分区。
    reg [4:0] write_index;reg published,write_bank,waiting;
    reg [1:0] ready_sync,ack_sync;reg acknowledged,read_bank,have_bank;
    reg [1:0] settle;
    reg [1:0] poll;reg [4:0] previous_address;
    wire [4:0] address=poll==0?0:poll==1?1:poll==2?2:index;
    wire [31:0] read_data;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(6),.ADDR_WIDTH_B(6),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) storage(
        .clka(pixel_clk),.cea(1'b1),.ocea(1'b1),.wea(!pixel_rst&&!waiting),.addra({write_bank,write_index}),.dia(records[write_index*32+:32]),.rsta(1'b0),.bea(1'b1),
        .clkb(mem_clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb({read_bank,address}),.dib(32'b0),.rstb(1'b0),.beb(1'b1),.dob(read_data));
    always @(posedge pixel_clk)begin
        if(pixel_rst)begin write_index<=0;published<=0;write_bank<=1;waiting<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],acknowledged};
            if(waiting)begin
                if(ack_sync[1]==published)begin waiting<=0;write_bank<=~write_bank;end
            end else if(write_index==19)begin write_index<=0;published<=write_bank;waiting<=1;end
            else write_index<=write_index+1'b1;
        end
    end
    always @(posedge mem_clk)begin
        if(mem_rst)begin ready_sync<=0;acknowledged<=0;read_bank<=0;have_bank<=0;settle<=0;
            poll<=0;previous_address<=0;value<=0;underflows<=0;pcm_underflows<=0;flags<=0;end
        else begin
            ready_sync<={ready_sync[0],published};poll<=poll+1'b1;previous_address<=address;
            if(ready_sync[1]!=read_bank)begin read_bank<=ready_sync[1];have_bank<=1;settle<=2;end
            else if(settle!=0)begin settle<=settle-1'b1;if(settle==1)acknowledged<=read_bank;end
            else if(have_bank)begin
                if(previous_address==0)underflows<=read_data;
                if(previous_address==1)pcm_underflows<=read_data;
                if(previous_address==2)flags<=read_data;
                if(previous_address==index)value<=read_data;
            end
        end
    end
endmodule
