`timescale 1ns/1ps

// 字幕文件校验与字形缓存
module s4_subtitle(
    input mem_clk,mem_rst,start,input [2:0] requested_id,input byte_valid,input [7:0] byte_data,input byte_last,
    output reg done,output reg [7:0] error_code,
    input pixel_clk,pixel_rst,input [5:0] glyph_address,
    output [8:0] glyph,output reg valid,output reg [2:0] page_id,output reg [6:0] length
);
    // 文件长度与 CRC 校验通过后才发布字幕，用页号防止旧字幕误显示。
    reg [15:0] pos,count,crc_expected,crc;reg [31:0] magic;reg [7:0] version,file_id,low_byte;
    reg active,publish,invalid_glyph;reg [2:0] id_mail;reg [6:0] length_mail;reg [1:0] publish_sync,start_sync;reg seen,start_toggle,start_seen;
    function [15:0] crc16;input [15:0] previous;input [7:0] value;reg [15:0] c;integer b;begin
        c=previous^{value,8'b0};for(b=0;b<8;b=b+1)c=c[15]?((c<<1)^16'h1021):(c<<1);crc16=c;
    end endfunction
    wire write_glyph=active&&byte_valid&&pos>=16&&pos<16+count*2&&pos[0];
    wire [5:0] address=(pos-16)>>1;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(9),.DATA_WIDTH_B(9),.ADDR_WIDTH_A(6),.ADDR_WIDTH_B(6),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) storage(
        .clka(mem_clk),.cea(1'b1),.ocea(1'b1),.wea(write_glyph),.addra(address),.dia({byte_data[0],low_byte}),.rsta(1'b0),.bea(1'b1),
        .clkb(pixel_clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(glyph_address),.dib(9'b0),.rstb(1'b0),.beb(1'b1),.dob(glyph));
    always @(posedge mem_clk)begin
        if(mem_rst)begin pos<=0;count<=0;crc_expected<=0;crc<=0;magic<=0;version<=0;file_id<=0;low_byte<=0;active<=0;publish<=0;
            id_mail<=0;length_mail<=0;done<=0;error_code<=0;start_toggle<=0;invalid_glyph<=0;end
        else if(start)begin pos<=0;count<=0;crc_expected<=0;crc<=0;magic<=0;version<=0;file_id<=0;active<=1;done<=0;error_code<=0;start_toggle<=~start_toggle;invalid_glyph<=0;end
        else if(active&&byte_valid)begin
            pos<=pos+1'b1;
            case(pos)
                0,1,2,3:magic[pos*8+:8]<=byte_data;4:version<=byte_data;5:file_id<=byte_data;
                6:count[7:0]<=byte_data;7:count[15:8]<=byte_data;8:crc_expected[7:0]<=byte_data;9:crc_expected[15:8]<=byte_data;
            endcase
            if(pos>=16)begin crc<=crc16(crc,byte_data);if(!pos[0])low_byte<=byte_data;end
            if(pos>=16&&pos[0]&&byte_data[7:1]!=0)invalid_glyph<=1;
            if(byte_last)begin
                active<=0;done<=1;
                if(magic!=32'h42533453 || version!=1 || file_id!=requested_id+1 || count==0 || count>64 || pos+1!=16+count*2 || invalid_glyph || byte_data[7:1]!=0)error_code<=8'ha1;
                else if(crc16(crc,byte_data)!=crc_expected)error_code<=8'ha2;
                else begin publish<=~publish;id_mail<=requested_id;length_mail<=count;end
            end
        end
    end
    always @(posedge pixel_clk)begin
        if(pixel_rst)begin publish_sync<=0;start_sync<=0;start_seen<=0;seen<=0;valid<=0;page_id<=0;length<=0;end
        else begin publish_sync<={publish_sync[0],publish};start_sync<={start_sync[0],start_toggle};
            if(start_sync[1]!=start_seen)begin start_seen<=start_sync[1];valid<=0;end
            if(publish_sync[1]!=seen)begin
            seen<=publish_sync[1];page_id<=id_mail;length<=length_mail;valid<=1;
        end end
    end
endmodule
