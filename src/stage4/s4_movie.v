`timescale 1ns/1ps

// PCM 进度驱动的动景播放
module s4_movie(input clk,rst,input [15:0] content_token,input prepare,music,finished,cancel,
 input [7:0] target_frame,input available,input [2:0] static_slot,input cache_read_idle,
 output reg media_start,media_cancel,output media_need,input file_start,input [31:0] file_size,
 input byte_valid,input [7:0] byte_data,input byte_last,output byte_ready,input [7:0] file_error,
 output writer_cmd,output [20:0] writer_addr,output [6:0] writer_words,input writer_ready,writer_done,
 input [5:0] write_index,input write_active,output [31:0] write_data,
 output reg commit_valid,input commit_ready,commit_done,output reg [2:0] commit_slot,
 output [15:0] commit_token,output reg commit_restore,
 output pause_prefetch,output reg [7:0] error_code,output movie_display,
 output [10:0] frame_width,frame_height,
 output [10:0] fifo_level,output [7:0] shown_frame,output [31:0] decoded_frames);
    // 视频使用第 5、6 槽的前 144 行，与第 0～4 槽的静态图片隔离。
 reg active,blocked,writing,write_slot,writer_start,parser_next,clear_fifo,parser_cancel;
 reg [15:0] seen_token;reg [1:0] ready_frames,quarantine;reg [7:0] frame_numbers[0:1];reg [4:0] guard[0:1];
 reg displayed,display_slot,pending,pending_slot,pending_restore,restore_needed;
 reg [7:0] shown;reg [31:0] completed;
 wire fifo_valid,fifo_last,fifo_ready,fifo_overflow;wire [7:0] fifo_data;
 wire parser_ready,parser_header,parser_complete,pv,pr,rl,writer_idle;wire [7:0] parser_index;wire [7:0] parser_error;
 wire [23:0] pixel;wire [9:0] px,py;
 assign media_need=active&&!finished&&fifo_level<=512&&!fifo_overflow;
 assign pause_prefetch=active||pending||restore_needed;
 assign movie_display=displayed;assign commit_token=content_token;assign shown_frame=shown;assign decoded_frames=completed;
 s4_movie_fifo fifo(.clk(clk),.rst(rst),.clear(clear_fifo),.in_valid(byte_valid),.in_data(byte_data),.in_last(byte_last),.in_ready(byte_ready),
  .out_valid(fifo_valid),.out_data(fifo_data),.out_last(fifo_last),.out_ready(fifo_ready),.level(fifo_level),.overflow(fifo_overflow));
 s4_alv1_parser parser(.clk(clk),.rst(rst),.start(file_start&&active),.cancel(parser_cancel),.file_size(file_size),
  .byte_valid(fifo_valid&&active),.byte_data(fifo_data),.byte_ready(fifo_ready),.byte_last(fifo_last),.next_frame(parser_next),.sink_idle(writer_idle),
  .frame_ready(parser_ready),.frame_index(parser_index),.header_valid(parser_header),.frame_width(frame_width),.frame_height(frame_height),.file_complete(parser_complete),.error_code(parser_error),
  .pixel_valid(pv),.pixel(pixel),.pixel_x(px),.pixel_y(py),.row_last(rl),.pixel_ready(pr));
 s4_movie_writer writer(.clk(clk),.rst(rst),.start(writer_start),.abort(!active||parser_error!=0),.buffer_id(write_slot?3'd6:3'd5),
  .pixel_valid(pv&&active),.pixel(pixel),.pixel_x(px),.pixel_y(py),.row_last(rl),.pixel_ready(pr),.idle(writer_idle),
  .cmd_valid(writer_cmd),.cmd_addr(writer_addr),.cmd_words(writer_words),.cmd_ready(writer_ready),.cmd_done(writer_done),
  .write_index(write_index),.write_active(write_active),.write_data(write_data));
 reg free_found,free_slot,candidate,candidate_slot;integer k;
 always @*begin
  free_found=0;free_slot=0;candidate=0;candidate_slot=0;
  for(k=0;k<2;k=k+1)begin
   if(!ready_frames[k]&&!quarantine[k]&&!(displayed&&display_slot==k)&&!(pending&&pending_slot==k)&&!(commit_valid&&!commit_restore&&commit_slot==k+5))begin free_found=1;free_slot=k;end
   if(ready_frames[k]&&frame_numbers[k]<=target_frame&&(!displayed||frame_numbers[k]>shown)&&(!candidate||frame_numbers[k]>frame_numbers[candidate_slot]))begin candidate=1;candidate_slot=k;end
  end
 end
 always @(posedge clk)begin
  if(rst)begin
   active<=0;blocked<=0;writing<=0;write_slot<=0;writer_start<=0;parser_next<=0;clear_fifo<=0;parser_cancel<=0;seen_token<=0;
   media_start<=0;media_cancel<=0;ready_frames<=0;quarantine<=0;displayed<=0;display_slot<=0;pending<=0;pending_slot<=0;pending_restore<=0;restore_needed<=0;
   commit_valid<=0;commit_slot<=0;commit_restore<=0;error_code<=0;shown<=0;completed<=0;
   frame_numbers[0]<=0;frame_numbers[1]<=0;guard[0]<=0;guard[1]<=0;
  end else begin
   media_start<=0;media_cancel<=0;writer_start<=0;parser_next<=0;clear_fifo<=0;parser_cancel<=0;
   for(k=0;k<2;k=k+1)begin
    if(quarantine[k])begin if(guard[k]!=0)guard[k]<=guard[k]-1'b1;else if(cache_read_idle)quarantine[k]<=0;end
    if(ready_frames[k]&&displayed&&frame_numbers[k]<=shown&&!(display_slot==k)&&!(pending&&pending_slot==k)&&!(commit_valid&&commit_slot==k+5))ready_frames[k]<=0;
   end
   if(commit_valid&&commit_ready)begin
    commit_valid<=0;pending<=1;pending_slot<=commit_slot==6;pending_restore<=commit_restore;
   end
   if(pending&&commit_done)begin
    pending<=0;
    if(pending_restore)begin displayed<=0;restore_needed<=0;end
    else begin
     if(displayed&&display_slot!=pending_slot)begin quarantine[display_slot]<=1;guard[display_slot]<=16;end
     displayed<=1;display_slot<=pending_slot;shown<=frame_numbers[pending_slot];ready_frames[pending_slot]<=0;
    end
   end
   if(content_token!=seen_token)begin
    seen_token<=content_token;active<=0;blocked<=0;writing<=0;ready_frames<=0;quarantine<=0;commit_valid<=0;restore_needed<=0;
    displayed<=0;pending<=0;media_cancel<=1;parser_cancel<=1;clear_fifo<=1;error_code<=0;shown<=0;completed<=0;
   end else if(cancel)begin
    active<=0;blocked<=1;writing<=0;ready_frames<=0;commit_valid<=0;restore_needed<=0;media_cancel<=1;parser_cancel<=1;clear_fifo<=1;
   end else if(active&&(parser_error!=0||(file_error!=0&&!media_start)||fifo_overflow))begin
    active<=0;blocked<=1;writing<=0;ready_frames<=0;commit_valid<=0;restore_needed<=displayed||pending;media_cancel<=1;parser_cancel<=1;clear_fifo<=1;
    if(error_code==0)error_code<=parser_error!=0?parser_error:file_error!=0?8'hd6:8'hd7;
   end else if(active&&finished)begin
    active<=0;blocked<=1;writing<=0;ready_frames<=0;media_cancel<=1;parser_cancel<=1;clear_fifo<=1;
   end else begin
    if(!active&&!blocked&&prepare&&writer_idle&&!pending)begin
     if(!available)begin error_code<=8'hd0;blocked<=1;end
     else begin active<=1;media_start<=1;clear_fifo<=1;writing<=1;write_slot<=0;writer_start<=1;ready_frames<=0;end
    end
    if(active&&writing&&parser_ready&&writer_idle&&!writer_start&&!parser_next)begin
     ready_frames[write_slot]<=1;frame_numbers[write_slot]<=parser_index;writing<=0;completed<=completed+1'b1;
    end
    if(active&&!writing&&!parser_complete&&free_found&&parser_ready&&writer_idle)begin
     write_slot<=free_slot;writer_start<=1;writing<=1;parser_next<=1;
    end
    if(!commit_valid&&!pending)begin
     if(restore_needed)begin commit_valid<=1;commit_slot<=static_slot;commit_restore<=1;end
     else if(active&&music&&candidate)begin commit_valid<=1;commit_slot<=candidate_slot?3'd6:3'd5;commit_restore<=0;end
    end
   end
  end
 end
endmodule
