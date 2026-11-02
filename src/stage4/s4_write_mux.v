`timescale 1ns/1ps

// 图片与动景写事务仲裁
module s4_write_mux(input clk,rst,
 input image_valid,input [20:0] image_addr,input [6:0] image_words,output image_ready,image_done,input [31:0] image_data,
 input movie_valid,input [20:0] movie_addr,input [6:0] movie_words,output movie_ready,movie_done,input [31:0] movie_data,
 output cmd_valid,output [20:0] cmd_addr,output [6:0] cmd_words,input cmd_ready,cmd_done,
 output [31:0] write_data,input write_active,output image_write_active,movie_write_active);
    // 突发事务接收后保持写入所有者，直到该事务完成。
 reg movie_owner;wire choose_movie=movie_valid;
 assign cmd_valid=image_valid||movie_valid;assign cmd_addr=choose_movie?movie_addr:image_addr;assign cmd_words=choose_movie?movie_words:image_words;
 assign image_ready=cmd_ready&&!choose_movie;assign movie_ready=cmd_ready&&choose_movie;
 assign image_done=cmd_done&&!movie_owner;assign movie_done=cmd_done&&movie_owner;
 assign write_data=movie_owner?movie_data:image_data;
 assign image_write_active=write_active&&!movie_owner;assign movie_write_active=write_active&&movie_owner;
 always @(posedge clk)begin if(rst)movie_owner<=0;else if(cmd_valid&&cmd_ready)movie_owner<=choose_movie;end
endmodule
