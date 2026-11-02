`timescale 1ns/1ps

// BMP 文件头与原始像素解析
module s4_bmp_decode (
    input clk,rst,start,abort,input [31:0] file_size,
    input byte_valid,input [7:0] byte_data,output byte_ready,input byte_last,
    output reg pixel_valid,output reg [23:0] pixel,output reg [10:0] pixel_x,pixel_y,
    input pixel_ready,output reg row_last,
    output reg done,output reg [7:0] error_code,
    output reg [10:0] image_width,image_height,
    output reg top_down,output reg [15:0] source_width,source_height,output reg [31:0] pixels_out
);
    // 校验文件头后，按行处理像素字节和 BMP 对齐填充。
    reg active,header_checked,downsample;
    reg [31:0] pos,offset,dib,width_raw,height_raw,compression;
    reg [15:0] magic,planes,bpp;
    reg [15:0] x,y;
    reg [1:0] channel;
    reg [15:0] padding,pad_left;
    reg [7:0] blue,green;
    wire [15:0] logical_y=top_down?y:(source_height-1-y);
    wire select_pixel=1'b1;
    reg [2:0] length_prepare;
    reg [11:0] checked_stride;
    reg [21:0] checked_payload;
    reg [32:0] checked_end;
    assign byte_ready=active && length_prepare==0 && (!pixel_valid || pixel_ready);
    task fail;input [7:0] code;begin error_code<=code;active<=0;pixel_valid<=0;done<=1;end endtask
    always @(posedge clk) begin
        if(rst) begin active<=0;done<=0;error_code<=0;pixel_valid<=0;pixel<=0;pixel_x<=0;pixel_y<=0;row_last<=0;
            image_width<=0;image_height<=0;
            pos<=0;offset<=0;dib<=0;width_raw<=0;height_raw<=0;compression<=0;magic<=0;planes<=0;bpp<=0;
            header_checked<=0;downsample<=0;top_down<=0;x<=0;y<=0;channel<=0;padding<=0;pad_left<=0;blue<=0;green<=0;
            length_prepare<=0;checked_stride<=0;checked_payload<=0;checked_end<=0;end
        else if(start) begin active<=1;done<=0;error_code<=0;pixel_valid<=0;pixels_out<=0;pos<=0;
            offset<=0;dib<=0;width_raw<=0;height_raw<=0;compression<=0;magic<=0;planes<=0;bpp<=0;
            header_checked<=0;x<=0;y<=0;channel<=0;pad_left<=0;length_prepare<=0;end
        else if(abort) fail(8'h34);
        else begin
            if(length_prepare!=0)begin
                // 尺寸校验后统一计算行跨度和像素负载，避免逐像素重复计算。
                case(length_prepare)
                    1:checked_stride<=((source_width[10:0]*12'd3+12'd3)>>2)<<2;
                    2:checked_payload<=checked_stride*source_height[9:0];
                    3:checked_end<={1'b0,offset}+checked_payload;
                endcase
                length_prepare<=length_prepare==3?3'd0:length_prepare+1'b1;
            end
            if(pixel_valid && pixel_ready) begin pixel_valid<=0;pixels_out<=pixels_out+1'b1;end
            if(byte_valid && byte_ready) begin
                pos<=pos+1'b1;
                case(pos)
                    0:magic[7:0]<=byte_data;1:magic[15:8]<=byte_data;
                    10:offset[7:0]<=byte_data;11:offset[15:8]<=byte_data;12:offset[23:16]<=byte_data;13:offset[31:24]<=byte_data;
                    14:dib[7:0]<=byte_data;15:dib[15:8]<=byte_data;16:dib[23:16]<=byte_data;17:dib[31:24]<=byte_data;
                    18:width_raw[7:0]<=byte_data;19:width_raw[15:8]<=byte_data;20:width_raw[23:16]<=byte_data;21:width_raw[31:24]<=byte_data;
                    22:height_raw[7:0]<=byte_data;23:height_raw[15:8]<=byte_data;24:height_raw[23:16]<=byte_data;25:height_raw[31:24]<=byte_data;
                    26:planes[7:0]<=byte_data;27:planes[15:8]<=byte_data;28:bpp[7:0]<=byte_data;29:bpp[15:8]<=byte_data;
                    30:compression[7:0]<=byte_data;31:compression[15:8]<=byte_data;32:compression[23:16]<=byte_data;33:compression[31:24]<=byte_data;
                endcase
                if(pos==53) begin
                    if(magic!=16'h4d42 || dib<40 || offset<54 || offset>=file_size || planes!=1 || bpp!=24 || compression!=0)
                        fail(8'h31);
                    else if(width_raw==0 || width_raw>1280 || height_raw==0 ||
                        (height_raw[31] ? -height_raw : height_raw)>960) fail(8'h32);
                    else begin
                        header_checked<=1;length_prepare<=1;source_width<=width_raw[15:0];source_height<=height_raw[31]?-height_raw:height_raw;
                        top_down<=height_raw[31];downsample<=0;
                        image_width<=width_raw;
                        image_height<=height_raw[31]?-height_raw:height_raw;
                        padding<=(-width_raw*3)&3;
                    end
                end
                if(header_checked && pos>=offset && y<source_height) begin
                    if(pad_left!=0) begin pad_left<=pad_left-1'b1;if(pad_left==1) y<=y+1'b1;end
                    else case(channel)
                        0:begin blue<=byte_data;channel<=1;end
                        1:begin green<=byte_data;channel<=2;end
                        2:begin
                            channel<=0;
                            if(select_pixel) begin pixel_valid<=1;pixel<={byte_data,green,blue};
                                pixel_x<=x;pixel_y<=logical_y;
                                row_last<=x+1==source_width;end
                            if(x+1==source_width) begin x<=0;pad_left<=padding;if(padding==0)y<=y+1'b1;end
                            else x<=x+1'b1;
                        end
                    endcase
                end
                if(byte_last) begin
                    active<=0;done<=1;
                    if(!header_checked || {1'b0,pos}+33'd1 < checked_end) fail(8'h33);
                end
            end
        end
    end
endmodule

