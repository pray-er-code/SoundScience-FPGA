`timescale 1ns/1ps

// 静态图与动景的显示提交仲裁
module s4_display_commit_mux(input clk,rst,input normal_toggle,output reg normal_ack,
 input [2:0] normal_slot,normal_id,input [15:0] normal_token,input normal_showcase,
 input [10:0] normal_width,normal_height,input [15:0] normal_source_width,normal_source_height,
 input movie_valid,output movie_ready,output reg movie_done,input [2:0] movie_slot,
 input [15:0] movie_token,input movie_restore,input [10:0] movie_width,movie_height,
 output reg commit_toggle,input cache_ack,
 output reg [2:0] commit_slot,commit_id,output reg [15:0] commit_token,commit_epoch,output reg commit_showcase,
 output reg [10:0] commit_width,commit_height,output reg [15:0] commit_source_width,commit_source_height);
    // 内容标识与帧序号分离，逐视频帧提交不得重启音轨或误确认图片。
 reg pending,owner,saved_normal;reg [1:0] ack_sync;
 assign movie_ready=!pending&&normal_toggle==normal_ack;
 always @(posedge clk)begin
  if(rst)begin normal_ack<=0;movie_done<=0;commit_toggle<=0;commit_slot<=0;commit_id<=0;commit_token<=0;commit_epoch<=0;commit_showcase<=0;
   commit_width<=640;commit_height<=480;commit_source_width<=0;commit_source_height<=0;pending<=0;owner<=0;saved_normal<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],cache_ack};movie_done<=0;
   if(pending)begin
    if(ack_sync[1]==commit_toggle)begin pending<=0;if(owner)movie_done<=1;else normal_ack<=saved_normal;end
   end else if(normal_toggle!=normal_ack)begin
    commit_slot<=normal_slot;commit_id<=normal_id;commit_token<=normal_token;commit_epoch<=commit_epoch+1'b1;
    commit_showcase<=normal_showcase;
    commit_width<=normal_width;commit_height<=normal_height;commit_source_width<=normal_source_width;commit_source_height<=normal_source_height;
    saved_normal<=normal_toggle;commit_toggle<=~commit_toggle;pending<=1;owner<=0;
   end else if(movie_valid)begin
    commit_slot<=movie_slot;commit_id<=3'd7;commit_token<=movie_token;commit_epoch<=commit_epoch+1'b1;
    commit_width<=movie_restore?normal_width:movie_width;commit_height<=movie_restore?normal_height:movie_height;
    commit_source_width<=movie_restore?normal_source_width:{5'b0,movie_width};commit_source_height<=movie_restore?normal_source_height:{5'b0,movie_height};
    commit_toggle<=~commit_toggle;pending<=1;owner<=1;
   end
  end
 end
endmodule
