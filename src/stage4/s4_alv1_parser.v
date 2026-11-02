`timescale 1ns/1ps

// ALV1 动景文件解析
module s4_alv1_parser(input clk,rst,start,cancel,input [31:0] file_size,
 input byte_valid,input [7:0] byte_data,output byte_ready,input byte_last,
 input next_frame,sink_idle,output reg frame_ready,output reg [7:0] frame_index,
 output reg header_valid,file_complete,output reg [7:0] error_code,output [10:0] frame_width,frame_height,
 output reg pixel_valid,output reg [23:0] pixel,output reg [9:0] pixel_x,pixel_y,
 output reg row_last,input pixel_ready);
    // 每帧通过 CRC 校验且像素全部写完后，才允许提交显示。
 localparam IDLE=0,HEADER=1,FRAME_HEADER=2,PIXELS=3,DRAIN=4,READY=5,FAILED=6;
 reg high_resolution,long_clip;
 wire [7:0] last_frame=long_clip?8'd195:8'd79;
 assign frame_width=high_resolution?11'd192:11'd160;assign frame_height=high_resolution?11'd144:11'd120;
 wire [15:0] last_payload=high_resolution?16'd55295:16'd38399;
 reg [2:0] state;reg [5:0] pos;reg [15:0] payload_pos;reg [7:0] low_byte;
 reg [31:0] crc,expected_crc,header_crc,pts;
 function [31:0] crc32;input [31:0] previous;input [7:0] b;reg [31:0] c;integer j;begin
  c=previous^{24'b0,b};for(j=0;j<8;j=j+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;crc32=c;
 end endfunction
 function [7:0] header_byte;input [5:0] n;begin case(n)
  0:header_byte=8'h41;1:header_byte=8'h4c;2:header_byte=8'h56;3:header_byte=8'h31;
  4,14,20:header_byte=1;6:header_byte=8'h40;8:header_byte=high_resolution?8'hc0:8'ha0;10:header_byte=high_resolution?8'h90:8'h78;
  12:header_byte=8'h08;16:header_byte=long_clip?8'hc4:8'h50;22:header_byte=8'h10;25:header_byte=high_resolution?8'hd8:8'h96;
  28:header_byte=8'h80;29:header_byte=8'hbb;32:header_byte=8'h70;33:header_byte=8'h17;
  36:header_byte=long_clip?8'h80:8'h40;
  37:header_byte=long_clip?8'h6c:high_resolution?8'h85:8'he5;38:header_byte=long_clip?8'ha5:high_resolution?8'h43:8'h2e;default:header_byte=0;
 endcase end endfunction
 reg [7:0] expected_header;
 always @*case(pos[3:0])
  0:expected_header=frame_index;1,2,3:expected_header=0;
  4:expected_header=pts[7:0];5:expected_header=pts[15:8];6:expected_header=pts[23:16];7:expected_header=pts[31:24];
  9:expected_header=high_resolution?8'hd8:8'h96;default:expected_header=0;
 endcase
 assign byte_ready=(state==HEADER||state==FRAME_HEADER||state==PIXELS)&&(!pixel_valid||pixel_ready);
 wire [7:0] crc_byte=state==HEADER&&pos>=40&&pos<44?8'b0:byte_data;
 wire [31:0] next_crc=crc32(crc,crc_byte);
 wire [15:0] rgb565={byte_data,low_byte};
 task fail;input [7:0] code;begin state<=FAILED;error_code<=code;pixel_valid<=0;frame_ready<=0;end endtask
 always @(posedge clk)begin
  if(rst)begin high_resolution<=0;long_clip<=0;state<=IDLE;pos<=0;payload_pos<=0;low_byte<=0;crc<=32'hffffffff;expected_crc<=0;header_crc<=0;pts<=0;
   frame_ready<=0;frame_index<=0;header_valid<=0;file_complete<=0;error_code<=0;pixel_valid<=0;pixel<=0;pixel_x<=0;pixel_y<=0;row_last<=0;end
  else if(cancel)begin state<=IDLE;pixel_valid<=0;frame_ready<=0;header_valid<=0;file_complete<=0;error_code<=0;end
  else if(start)begin
   high_resolution<=file_size!=3073344;long_clip<=file_size==10841216;state<=HEADER;pos<=0;payload_pos<=0;crc<=32'hffffffff;header_crc<=0;expected_crc<=0;pts<=0;frame_index<=0;
   header_valid<=0;file_complete<=0;frame_ready<=0;pixel_valid<=0;pixel_x<=0;pixel_y<=0;error_code<=0;
   if(file_size!=3073344&&file_size!=4425024&&file_size!=10841216)fail(8'hd1);
  end else begin
   if(pixel_valid&&pixel_ready)pixel_valid<=0;
   if(state==DRAIN&&!pixel_valid&&sink_idle)begin frame_ready<=1;state<=READY;if(frame_index==last_frame)file_complete<=1;end
   if(state==READY&&next_frame&&frame_index<last_frame)begin
    state<=FRAME_HEADER;frame_ready<=0;frame_index<=frame_index+1'b1;pts<=pts+6000;pos<=0;expected_crc<=0;pixel_x<=0;pixel_y<=0;
   end
   if(byte_valid&&byte_ready)begin
    case(state)
     HEADER:begin
      crc<=next_crc;
      if(pos>=40&&pos<44)header_crc[(pos-40)*8+:8]<=byte_data;
      else if(byte_data!=header_byte(pos))fail(8'hd1);
      if(pos==63)begin
       if((~next_crc)!=header_crc)fail(8'hd2);
       else if(byte_data==header_byte(pos))begin state<=FRAME_HEADER;header_valid<=1;pos<=0;expected_crc<=0;end
      end else pos<=pos+1'b1;
      if(byte_last)fail(8'hd4);
     end
     FRAME_HEADER:begin
      if(pos<12&&byte_data!=expected_header)fail(8'hd3);
      if(pos>=12)expected_crc[(pos-12)*8+:8]<=byte_data;
      if(pos==15)begin state<=PIXELS;payload_pos<=0;crc<=32'hffffffff;pixel_x<=0;pixel_y<=0;end
      else pos<=pos+1'b1;
      if(byte_last)fail(8'hd4);
     end
     PIXELS:begin
      crc<=next_crc;payload_pos<=payload_pos+1'b1;
      if(!payload_pos[0])low_byte<=byte_data;
      else begin
       pixel_valid<=1;pixel<={{rgb565[15:11],rgb565[15:13]},{rgb565[10:5],rgb565[10:9]},{rgb565[4:0],rgb565[4:2]}};
       row_last<=pixel_x==frame_width-1'b1;
      end
      if(payload_pos==last_payload)begin
       if((~next_crc)!=expected_crc)fail(8'hd5);else state<=DRAIN;
       if(byte_last!=(frame_index==last_frame))fail(8'hd4);
      end else if(byte_last)fail(8'hd4);
     end
    endcase
   end
   if(pixel_valid&&pixel_ready)begin
    if(pixel_x==frame_width-1'b1)begin pixel_x<=0;pixel_y<=pixel_y+1'b1;end else pixel_x<=pixel_x+1'b1;
   end
  end
 end
endmodule
