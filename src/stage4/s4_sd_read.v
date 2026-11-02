`timescale 1ns/1ps

// 正式版 SD 卡只读扇区控制
module s4_sd_read #(
    parameter integer POWER_WAIT=500000,
    parameter integer INIT_DIV=64,
    parameter integer FAST_DIV=2
)(
    input clk,rst,input sd_miso,output sd_sck,sd_mosi,output reg sd_cs_n,
    output reg initialized,output reg [7:0] error_code,
    input req_valid,input [31:0] req_lba,output req_ready,
    output data_valid,output [7:0] data, input data_ready,output reg sector_done,
    output reg [31:0] sectors_read,
    output reg [31:0] token_cycles,transfer_cycles,drain_cycles,stall_cycles,request_cycles,
    output reg [31:0] last_request_cycles
);
    localparam BOOT=0,CLOCKS=1,IDLE=2,WAIT_BYTE=3,CMD_SEND=4,CMD_NEXT=5,
        RESP=6,RESP_CHECK=7,EXT=8,EXT_NEXT=9,C0=10,C8=11,C55=12,C41=13,C58=14,C16=15,
        READ_R1=16,TOKEN=17,TOKEN_CHECK=18,BYTE=19,STORE=20,CRC1=21,CRC2=22,STREAM=23,FAIL=24,CMD_PRE=25,CRC_CHECK=26,STREAM_PRE=27;
    reg [5:0] state,return_state,command_return;
    reg spi_start;reg [7:0] spi_tx;
    wire spi_done,spi_busy;wire [7:0] spi_rx;
    reg [47:0] packet;
    reg [2:0] command_byte,ext_left;
    reg [7:0] r1;
    reg [31:0] ext_data,wait_count;
    reg [15:0] attempts;
    reg [19:0] token_count;
    reg [9:0] ptr;
    reg [4:0] boot_bytes;
    reg high_capacity,v2;
    reg [15:0] data_crc;reg [7:0] crc_high;
    function [15:0] crc16;input [15:0] previous;input [7:0] value;
        reg [15:0] c;integer bitno;begin c=previous^{value,8'b0};
        for(bitno=0;bitno<8;bitno=bitno+1)c=c[15]?((c<<1)^16'h1021):(c<<1);crc16=c;end endfunction
    assign req_ready=initialized && state==IDLE && error_code==0;
    assign data_valid=state==STREAM;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) u_sector (
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(state==STORE),.addra(ptr[8:0]),.dia(spi_rx),.rsta(1'b0),.bea(1'b1),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(ptr[8:0]),.dib(8'b0),.rstb(1'b0),.beb(1'b1),.dob(data));
    s3_spi_byte spi(.clk(clk),.rst(rst),.start(spi_start),.tx(spi_tx),
        .divider(initialized ? FAST_DIV[7:0] : INIT_DIV[7:0]),.miso(sd_miso),
        .sck(sd_sck),.mosi(sd_mosi),.busy(spi_busy),.done(spi_done),.rx(spi_rx));
    task xfer;input [7:0] value;input [5:0] next_state;begin
        spi_tx<=value;spi_start<=1;return_state<=next_state;state<=WAIT_BYTE;end endtask
    task command;input [5:0] number;input [31:0] arg;input [7:0] crc;
        input [2:0] extra;input [5:0] next_state;begin
        sd_cs_n<=0;packet<={2'b01,number,arg,crc};command_byte<=0;ext_left<=extra;
        command_return<=next_state;token_count<=0;ext_data<=0;state<=CMD_PRE;end endtask
    task fail;input [7:0] code;begin error_code<=code;state<=FAIL;sd_cs_n<=1;end endtask
    // 各阶段耗时按 50 MHz 时钟饱和计数。
    reg request_active;
    always @(posedge clk)begin
        if(rst)begin token_cycles<=0;transfer_cycles<=0;drain_cycles<=0;stall_cycles<=0;
            request_cycles<=0;last_request_cycles<=0;request_active<=0;end
        else begin
            if(req_valid&&req_ready)begin request_cycles<=0;request_active<=1;end
            else if(request_active && request_cycles!=32'hffffffff)request_cycles<=request_cycles+1'b1;
            if(sector_done)begin last_request_cycles<=request_cycles;request_active<=0;end
            if((state==TOKEN || state==TOKEN_CHECK || (state==WAIT_BYTE&&return_state==TOKEN_CHECK)) && token_cycles!=32'hffffffff)token_cycles<=token_cycles+1'b1;
            if((state==BYTE || state==STORE || (state==WAIT_BYTE&&return_state==STORE)) && transfer_cycles!=32'hffffffff)transfer_cycles<=transfer_cycles+1'b1;
            if((state==STREAM || state==STREAM_PRE) && drain_cycles!=32'hffffffff)drain_cycles<=drain_cycles+1'b1;
            if(state==STREAM && !data_ready && stall_cycles!=32'hffffffff)stall_cycles<=stall_cycles+1'b1;
        end
    end
    always @(posedge clk) begin
        if(rst) begin state<=BOOT;sd_cs_n<=1;initialized<=0;error_code<=0;wait_count<=0;attempts<=0;
            token_count<=0;ptr<=0;boot_bytes<=0;high_capacity<=0;v2<=1;spi_start<=0;spi_tx<=255;
            sector_done<=0;sectors_read<=0;packet<=0;command_byte<=0;ext_left<=0;ext_data<=0;r1<=255;
            return_state<=0;command_return<=0;data_crc<=0;crc_high<=0;end
        else begin spi_start<=0;sector_done<=0;
            case(state)
                BOOT: if(wait_count>=POWER_WAIT) begin wait_count<=0;state<=CLOCKS;end else wait_count<=wait_count+1'b1;
                CLOCKS: if(boot_bytes==12) command(0,0,8'h95,0,C0);
                    else begin boot_bytes<=boot_bytes+1'b1;xfer(255,CLOCKS);end
                WAIT_BYTE: if(spi_done) state<=return_state;
                CMD_PRE:xfer(255,CMD_SEND);
                CMD_SEND: xfer(packet[47:40],CMD_NEXT);
                CMD_NEXT: begin packet<={packet[39:0],8'hff};
                    if(command_byte==5) state<=RESP;else begin command_byte<=command_byte+1'b1;state<=CMD_SEND;end end
                RESP: xfer(255,RESP_CHECK);
                RESP_CHECK: if(!spi_rx[7]) begin r1<=spi_rx;
                        if(ext_left!=0 && spi_rx!=8'h05) state<=EXT;else state<=command_return;
                    end else if(token_count==63) fail(8'h01);else begin token_count<=token_count+1'b1;state<=RESP;end
                EXT: xfer(255,EXT_NEXT);
                EXT_NEXT: begin ext_data<={ext_data[23:0],spi_rx};ext_left<=ext_left-1'b1;
                    state<=(ext_left==1)?command_return:EXT;end
                C0: if(r1==1) command(8,32'h1aa,8'h87,4,C8);else fail(8'h02);
                C8: if(r1==1 && ext_data[11:0]==12'h1aa) command(55,0,255,0,C55);
                    else if(r1==5) begin v2<=0;command(55,0,255,0,C55);end else fail(8'h03);
                C55: if(r1<=1) command(41,v2?32'h40000000:0,255,0,C41);else fail(8'h04);
                C41: if(r1==0) command(58,0,255,4,C58);
                    else if(r1==1 && attempts<2000) begin attempts<=attempts+1'b1;command(55,0,255,0,C55);end
                    else fail(8'h05);
                C58: if(r1==0) begin high_capacity<=ext_data[30];
                    if(ext_data[30]) begin initialized<=1;state<=IDLE;sd_cs_n<=1;end
                    else command(16,512,255,0,C16);end else fail(8'h06);
                C16: if(r1==0) begin initialized<=1;state<=IDLE;sd_cs_n<=1;end else fail(8'h07);
                IDLE: if(req_valid && req_ready) command(17,high_capacity?req_lba:(req_lba<<9),255,0,READ_R1);
                READ_R1: if(r1==0) begin token_count<=0;state<=TOKEN;end else fail(8'h08);
                TOKEN: xfer(255,TOKEN_CHECK);
                TOKEN_CHECK: if(spi_rx==8'hfe) begin ptr<=0;data_crc<=0;state<=BYTE;end
                    else if(spi_rx!=255 || token_count==20'hfffff) fail(8'h09);
                    else begin token_count<=token_count+1'b1;state<=TOKEN;end
                BYTE: xfer(255,STORE);
                STORE: begin data_crc<=crc16(data_crc,spi_rx);
                    if(ptr==511) state<=CRC1;else begin ptr<=ptr+1'b1;state<=BYTE;end end
                CRC1: xfer(255,CRC2);
                CRC2: begin crc_high<=spi_rx;xfer(255,CRC_CHECK);end
                CRC_CHECK:if({crc_high,spi_rx}!=data_crc) fail(8'h0a);
                    else begin ptr<=0;state<=STREAM_PRE;sd_cs_n<=1;end
                STREAM_PRE:state<=STREAM;
                STREAM: if(data_ready) begin
                    if(ptr==511) begin sector_done<=1;sectors_read<=sectors_read+1'b1;state<=IDLE;sd_cs_n<=1;end
                    else begin ptr<=ptr+1'b1;state<=STREAM_PRE;end end
                FAIL: sd_cs_n<=1;
                default: fail(8'hff);
            endcase
        end
    end
endmodule

