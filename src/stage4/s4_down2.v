`timescale 1ns/1ps

// 图片入库前的双线性预缩放
module s4_down2(
 input clk,rst,start,abort,input [10:0] width,height,input top_down,
 input in_valid,input [23:0] in_pixel,input [10:0] in_x,in_y,input in_row_last,output in_ready,
 output reg out_valid,output reg [23:0] out_pixel,output reg [9:0] out_x,out_y,output reg out_row_last,input out_ready,
 output reg [10:0] out_width,out_height,output reg [31:0] accepted,generated,stall_cycles,output idle
);
    // 小图保留原尺寸，大图按比例双线性缩放至 640×480 范围。
 localparam WAIT=0,FIT=1,FIT_WAIT=2,X_START=3,X_WAIT=4,Y_START=5,Y_WAIT=6,RUN=7,
  H_MUL=8,H_RESULT=9,H_SAVE=10,V_MUL=11,V_RESULT=12,PUBLISH=13;
 reg [3:0] state;reg shrink,top,wide;
 reg [10:0] source_w,source_h;reg [26:0] x_step,y_step,x_fp,y_fp,x_initial;
 reg [9:0] column,row;reg row_finished,selected_row_last,emit_row,duplicate_row;
 reg [23:0] source_previous,left_pixel,right_pixel,previous_rgb,horizontal_rgb,vertical_rgb;
 reg [1:0] channel;reg [15:0] x_fraction,y_fraction;
 reg divider_start;wire divider_busy,divider_done;reg [26:0] numerator;reg [10:0] denominator;
 wire [26:0] quotient;wire [10:0] residual;
 s4_scale_divider divide(.clk(clk),.rst(rst||start||abort),.start(divider_start),.numerator(numerator),.denominator(denominator),
  .busy(divider_busy),.done(divider_done),.quotient(quotient),.residual(residual));
 wire [31:0] fit_width={21'b0,width}<<9; // 常数乘法用移位分解。
 wire [31:0] fit_height={21'b0,height}<<9;
 wire width_limited=(fit_width-({21'b0,width}<<5))>=(fit_height+({21'b0,height}<<7));
 wire [10:0] stream_y=top?in_y:source_h-1'b1-in_y;
 wire [10:0] sample_x0=x_fp[26:16];
 wire [10:0] sample_x1=x_fp[15:0]==0?sample_x0:sample_x0+1'b1<source_w?sample_x0+1'b1:sample_x0;
 wire [10:0] sample_y0=y_fp[26:16];
 wire [10:0] sample_y1=y_fp[15:0]==0?sample_y0:sample_y0+1'b1<source_h?sample_y0+1'b1:sample_y0;
 wire take=in_valid&&in_ready;
 assign in_ready=state==RUN&&(!out_valid||out_ready);
 assign idle=(state==RUN||state==WAIT)&&!out_valid;
 wire [23:0] prior_row;
 wire row_write=state==H_SAVE;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(24),.DATA_WIDTH_B(24),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K")) u_previous_row(
  .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(row_write),.addra(column),.dia(horizontal_rgb),.rsta(1'b0),.bea(1'b1),
  .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(column),.dib(24'b0),.rstb(1'b0),.beb(1'b1),.dob(prior_row));
 wire vertical=state==V_MUL||state==V_RESULT;
 reg [7:0] p,q;
 always @*begin
  case(channel)
   0:begin p=vertical?previous_rgb[7:0]:left_pixel[7:0];q=vertical?horizontal_rgb[7:0]:right_pixel[7:0];end
   1:begin p=vertical?previous_rgb[15:8]:left_pixel[15:8];q=vertical?horizontal_rgb[15:8]:right_pixel[15:8];end
   default:begin p=vertical?previous_rgb[23:16]:left_pixel[23:16];q=vertical?horizontal_rgb[23:16]:right_pixel[23:16];end
  endcase
 end
 wire signed [8:0] delta=$signed({1'b0,q})-$signed({1'b0,p});
 wire signed [16:0] fraction=$signed({1'b0,vertical?y_fraction:x_fraction});
 reg signed [25:0] product;
 wire signed [26:0] rounded=$signed({1'b0,p,16'b0})+product+27'sd32768;
 wire [7:0] result=rounded[23:16];
 always @(posedge clk)begin
  if(rst||start||abort)begin
   state<=WAIT;shrink<=0;top<=0;wide<=0;source_w<=0;source_h<=0;out_width<=0;out_height<=0;
   x_step<=0;y_step<=0;x_fp<=0;y_fp<=0;x_initial<=0;column<=0;row<=0;row_finished<=0;selected_row_last<=0;emit_row<=0;duplicate_row<=0;
   source_previous<=0;left_pixel<=0;right_pixel<=0;previous_rgb<=0;horizontal_rgb<=0;vertical_rgb<=0;
   channel<=0;x_fraction<=0;y_fraction<=0;product<=0;divider_start<=0;numerator<=0;denominator<=1;
   out_valid<=0;out_pixel<=0;out_x<=0;out_y<=0;out_row_last<=0;accepted<=0;generated<=0;stall_cycles<=0;
  end else begin
   divider_start<=0;
   if(out_valid&&out_ready)begin out_valid<=0;if(generated!=32'hffffffff)generated<=generated+1'b1;end
   if(in_valid&&!in_ready&&stall_cycles!=32'hffffffff)stall_cycles<=stall_cycles+1'b1;
   case(state)
    WAIT:if(in_valid)begin
     source_w<=width;source_h<=height;top<=top_down;wide<=width_limited;
     shrink<=width>640||height>480;
     if(width<=640&&height<=480)begin out_width<=width;out_height<=height;state<=RUN;end
     else state<=FIT;
    end
    FIT:begin
     numerator<=wide?({21'b0,source_h}<<9)+({21'b0,source_h}<<7):({21'b0,source_w}<<9)-({21'b0,source_w}<<5);
     denominator<=wide?source_w:source_h;divider_start<=1;state<=FIT_WAIT;
    end
    FIT_WAIT:if(divider_done)begin
     out_width<=wide?11'd640:(quotient==0?11'd1:quotient[10:0]);
     out_height<=wide?(quotient==0?11'd1:quotient[10:0]):11'd480;state<=X_START;
    end
    X_START:begin numerator<={21'b0,source_w}<<16;denominator<=out_width;divider_start<=1;state<=X_WAIT;end
    X_WAIT:if(divider_done)begin x_step<=quotient;x_initial<=(quotient-65536)>>1;x_fp<=(quotient-65536)>>1;state<=Y_START;end
    Y_START:begin numerator<={21'b0,source_h}<<16;denominator<=out_height;divider_start<=1;state<=Y_WAIT;end
    Y_WAIT:if(divider_done)begin
     y_step<=quotient;
     // 倒序 BMP 镜像同一采样网格，利用余数保持正倒序结果一致。
     y_fp<=top?((quotient-65536)>>1):residual+((quotient-65536+1)>>1);
     state<=RUN;
    end
    RUN:if(take)begin
     if(accepted!=32'hffffffff)accepted<=accepted+1'b1;
     source_previous<=in_pixel;
     if(!shrink)begin out_valid<=1;out_pixel<=in_pixel;out_x<=in_x;out_y<=in_y;out_row_last<=in_row_last;end
     else if(!row_finished&&row<out_height&&in_x==sample_x1)begin
      left_pixel<=sample_x0==sample_x1?in_pixel:source_previous;right_pixel<=in_pixel;
      x_fraction<=x_fp[15:0];y_fraction<=y_fp[15:0];duplicate_row<=sample_y0==sample_y1;
      emit_row<=stream_y==sample_y1;selected_row_last<=in_row_last;channel<=0;state<=H_MUL;
     end
     if(in_row_last&&shrink)begin
      if(row_finished||in_x!=sample_x1||row>=out_height)begin
       column<=0;x_fp<=x_initial;row_finished<=0;
       if(stream_y==sample_y1&&row<out_height)begin row<=row+1'b1;y_fp<=y_fp+y_step;end
      end
     end
    end
    H_MUL:begin product<=delta*fraction;state<=H_RESULT;end
    H_RESULT:begin
     case(channel)0:horizontal_rgb[7:0]<=result;1:horizontal_rgb[15:8]<=result;2:horizontal_rgb[23:16]<=result;endcase
     if(channel==2)state<=H_SAVE;else begin channel<=channel+1'b1;state<=H_MUL;end
    end
    H_SAVE:begin
     channel<=0;previous_rgb<=prior_row;
     if(emit_row)begin if(duplicate_row)begin vertical_rgb<=horizontal_rgb;state<=PUBLISH;end else state<=V_MUL;end
     else begin
      if(selected_row_last)begin column<=0;x_fp<=x_initial;row_finished<=0;end
      else if(column+1>=out_width)row_finished<=1;
      else begin column<=column+1'b1;x_fp<=x_fp+x_step;end
      state<=RUN;
     end
    end
    V_MUL:begin product<=delta*fraction;state<=V_RESULT;end
    V_RESULT:begin
     case(channel)0:vertical_rgb[7:0]<=result;1:vertical_rgb[15:8]<=result;2:vertical_rgb[23:16]<=result;endcase
     if(channel==2)state<=PUBLISH;else begin channel<=channel+1'b1;state<=V_MUL;end
    end
    PUBLISH:begin
     out_valid<=1;out_pixel<=vertical_rgb;out_x<=column;out_y<=top?row:out_height-1'b1-row;out_row_last<=column+1>=out_width;
     if(selected_row_last)begin column<=0;x_fp<=x_initial;row<=row+1'b1;y_fp<=y_fp+y_step;row_finished<=0;end
     else if(column+1>=out_width)row_finished<=1;
     else begin column<=column+1'b1;x_fp<=x_fp+x_step;end
     state<=RUN;
    end
   endcase
  end
 end
endmodule

// 预缩放坐标迭代除法
module s4_scale_divider(input clk,rst,start,input [26:0] numerator,input [10:0] denominator,
 output reg busy,done,output reg [26:0] quotient,output [10:0] residual);
 reg [26:0] dividend;reg [11:0] remainder;reg [10:0] divisor;reg [4:0] count;
 wire [11:0] shifted={remainder[10:0],dividend[26]};assign residual=remainder[10:0];
 always @(posedge clk)begin
  if(rst)begin busy<=0;done<=0;quotient<=0;dividend<=0;remainder<=0;divisor<=1;count<=0;end
  else begin
   done<=0;
   if(start&&!busy)begin busy<=1;dividend<=numerator;divisor<=denominator==0?1:denominator;remainder<=0;quotient<=0;count<=0;end
   else if(busy)begin
    dividend<={dividend[25:0],1'b0};
    if(shifted>=divisor)begin remainder<=shifted-divisor;quotient<={quotient[25:0],1'b1};end
    else begin remainder<=shifted;quotient<={quotient[25:0],1'b0};end
    if(count==26)begin busy<=0;done<=1;end else count<=count+1'b1;
   end
  end
 end
endmodule
