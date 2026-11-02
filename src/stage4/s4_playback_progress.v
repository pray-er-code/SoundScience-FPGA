`timescale 1ns/1ps

// 讲解阶段和动景帧进度
module s4_playback_progress #(
 parameter integer MUSIC_START_SAMPLES=960000,PREPARE_SAMPLES=816000,FRAME_SAMPLES=6000,MANUAL_VIDEO_STEP=0
)(input pixel_clk,pixel_rst,display_valid,showcase,input [2:0] page_id,input [15:0] video_token,active_token,
 input auto_play,
 input [31:0] consumed_samples,input [2:0] playback_mode,
 output music_active,content_finished,output prepare_video,output reg [7:0] music_frame,
 input mem_clk,mem_rst,input [15:0] requested_token,
 output mem_finished,mem_prepare,mem_music,output [7:0] mem_frame);
 reg [15:0] seen_token;reg [31:0] next_frame_sample;reg natural_started;
 wire identity=display_valid&&active_token==video_token;
 assign content_finished=identity&&playback_mode==4;
 wire [31:0] music_start=showcase?32'd0:MUSIC_START_SAMPLES;
 wire natural_enabled=!MANUAL_VIDEO_STEP||auto_play||natural_started;
 assign music_active=identity&&page_id==7&&(showcase||(natural_enabled&&consumed_samples>=MUSIC_START_SAMPLES))&&!content_finished;
 assign prepare_video=identity&&page_id==7&&(showcase||(natural_enabled&&consumed_samples>=PREPARE_SAMPLES));
 always @(posedge pixel_clk)begin
  if(pixel_rst)begin seen_token<=0;music_frame<=0;next_frame_sample<=MUSIC_START_SAMPLES+FRAME_SAMPLES;natural_started<=0;end
  else if(seen_token!=video_token)begin seen_token<=video_token;music_frame<=0;next_frame_sample<=music_start+FRAME_SAMPLES;natural_started<=0;end
  else begin
   // 关闭轮播不打断已开始的视频，切换内容标识后清除播放状态。
   if(MANUAL_VIDEO_STEP&&identity&&page_id==7&&!showcase&&auto_play&&consumed_samples>=MUSIC_START_SAMPLES)natural_started<=1;
   if(identity&&consumed_samples>=next_frame_sample&&music_frame<195)begin
    music_frame<=music_frame+1'b1;next_frame_sample<=next_frame_sample+FRAME_SAMPLES;
   end
  end
 end
 wire [26:0] received;
 s4_state_mailbox #(.WIDTH(27)) mailbox(.source_clk(pixel_clk),.source_rst(pixel_rst),
  .source_data({video_token,music_frame,prepare_video,music_active,content_finished}),.dest_clk(mem_clk),.dest_rst(mem_rst),.dest_data(received));
 wire matching=received[26:11]==requested_token;
 assign mem_finished=matching&&received[0];assign mem_music=matching&&received[1];assign mem_prepare=matching&&received[2];
 assign mem_frame=matching?received[10:3]:8'b0;
endmodule
