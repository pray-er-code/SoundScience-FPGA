`timescale 1ns/1ps

// 透明中文界面与分析图形叠加
module s4_osd #(parameter FONT_FILE="font.mif",FRAME_FADE=0,CLEAN_UI=0,VIDEO_INFO=0)(
 input clk,rst,frame_start,valid,user,last,input [23:0] rgb,input [10:0] x,y,
 input [2:0] page_id,input [15:0] token,source_width,source_height,
 input menu,input [3:0] selection,volume,brightness,contrast,input [1:0] transition,view,stage,
 input show_header,show_analysis,show_subtitle,input [2:0] period_setting,
 input [2:0] wave_range,input light_ui,input [5:0] frame_fade_level,
 input music_active,content_finished,full_demo,
 input page_loading,video_wait,input [2:0] pending_page,
 input video_mode,video_ready,
 input low_frequency,freeze,zero_trigger,paused,auto_play,test_tone,color_bars,input [1:0] cache_ready,
 input subtitle_valid,input [2:0] subtitle_id,input [6:0] subtitle_length,output [5:0] subtitle_address,input [8:0] subtitle_glyph,
 output [7:0] wave_address,input signed [15:0] wave_value,output [4:0] spectrum_address,input [15:0] spectrum_value,
 output reg out_valid,out_user,out_last,output reg [23:0] out_rgb
);
 reg [15:0] current_token;reg [5:0] progress;reg [11:0] scroll;
 wire [5:0] fade_gain=FRAME_FADE?frame_fade_level:progress;
 wire video_context=VIDEO_INFO&&video_mode;
 wire waiting_key=VIDEO_INFO&&video_ready;
 reg subtitle_seen;reg [6:0] subtitle_length_seen;
 wire subtitle_matches=subtitle_valid&&subtitle_id==page_id;
 wire [12:0] subtitle_extent={1'b0,subtitle_length,5'b0};
 // 字幕首字从右侧屏外进入，未进入有效范围时保持透明。
 wire [12:0] scrolled={2'b0,x}+{1'b0,scroll}-13'd1248;
 wire [12:0] scroll_limit=subtitle_extent+13'd1280;
 assign subtitle_address=scrolled[10:5];
 assign wave_address=(x-32)>>2;assign spectrum_address=(x-32)>>5;
 wire [15:0] width_digits,height_digits;
 reg [15:0] seen_source_width,seen_source_height;
 wire geometry_changed=source_width!=seen_source_width||source_height!=seen_source_height;
 wire [3:0] period_tens=({1'b0,period_setting}+4'd1)>>1;
 reg [79:0] range_label;
 always @*case(wave_range)
  0:range_label="2FS       ";1:range_label="1FS       ";2:range_label="0.5FS     ";
  3:range_label="0.25FS    ";4:range_label="0.125FS   ";5:range_label="0.0625FS  ";
  default:range_label="0.03125FS ";
 endcase
 wire [23:0] color_text=CLEAN_UI?24'h27b879:light_ui?24'h203a39:24'hf4f8ff;
 wire [23:0] color_accent=CLEAN_UI?24'hd4483b:light_ui?24'h873f27:24'hffcf50;
 wire [23:0] color_curve=light_ui?24'h17624f:24'h50e0c0;
 wire [23:0] color_dim=CLEAN_UI?24'h27b879:light_ui?24'h4c6259:24'ha8bdcd;
 wire [23:0] color_grid=light_ui?24'hacb5a5:24'h314756;
 wire [23:0] color_halo=CLEAN_UI?24'h163f32:light_ui?24'hf5f0e5:24'h081018;
 s4_bcd wd(.clk(clk),.rst(rst),.start(token!=current_token||geometry_changed),.value(source_width),.digits(width_digits));
 s4_bcd hd(.clk(clk),.rst(rst),.start(token!=current_token||geometry_changed),.value(source_height),.digits(height_digits));
 reg [5:0] line,column,line_reg,column_reg;wire [8:0] text_glyph;
 reg [8:0] chosen_glyph,override0;reg text_region,subtitle_region,choose_label,label0;
 reg [10:0] text_x,text_y;reg [23:0] ink,ink_pre,ink0,ink1;
 reg [4:0] row_pre,bit_pre;reg text_pre,sub_pre;reg [3:0] setting_value;
 s4_ui_text labels(.line(line_reg),.column(column_reg),.glyph(text_glyph));
 function [8:0] digit;input [3:0] n;begin digit=n<10?n+16:n+23;end endfunction
 // 频谱刻度对应第 4、8、16、32 个正频率点。
 reg [1:0] frequency_tick;reg [2:0] frequency_column;
 always @*begin
  frequency_tick=x<208?0:x<480?1:x<976?2:3;
  // 利用标签对齐关系简化列坐标计算。
  frequency_column=x[6:4]+(frequency_tick[1]?3'd1:3'd2);
 end
 always @*begin
  line=0;column=0;text_region=0;subtitle_region=0;chosen_glyph=0;choose_label=0;
  text_x=x;text_y=y;ink=color_text;setting_value=0;
  if(show_header&&y>=16&&y<48&&x>=32&&x<(CLEAN_UI?1184:896))begin
   text_region=1;text_y=y-16;
   if(video_context&&x<112)begin
    text_x=(x-32)&15;
    case((x-32)>>4)0:chosen_glyph=54;1:chosen_glyph=41;2:chosen_glyph=36;3:chosen_glyph=37;4:chosen_glyph=47;endcase
   end
   else if(x<96)begin line=24;text_x=x-32;column=(x-32)>>5;choose_label=1;end
   else if(x>=112&&x<176)begin
    text_x=(x-112)&15;
    case((x-112)>>4)0:chosen_glyph=digit(width_digits[15:12]);1:chosen_glyph=digit(width_digits[11:8]);2:chosen_glyph=digit(width_digits[7:4]);3:chosen_glyph=digit(width_digits[3:0]);endcase
   end else if(x>=176&&x<192)begin text_x=(x-176)&15;chosen_glyph=9'd88;end
   else if(x>=192&&x<256)begin
    text_x=(x-192)&15;
    case((x-192)>>4)0:chosen_glyph=digit(height_digits[15:12]);1:chosen_glyph=digit(height_digits[11:8]);2:chosen_glyph=digit(height_digits[7:4]);3:chosen_glyph=digit(height_digits[3:0]);endcase
   end else if(x>=288&&x<352)begin
    if(video_context)begin text_x=(x-288)&15;case((x-288)>>4)0:chosen_glyph=24;1:chosen_glyph=70;2:chosen_glyph=80;3:chosen_glyph=83;endcase end
    else begin line=23;text_x=x-288;column=(x-288)>>5;choose_label=1;end
   end
   else if(!video_context&&x>=368&&x<384)begin text_x=(x-368)&15;chosen_glyph=digit(page_id+1'b1);end
   else if(x>=416&&x<480)begin line=auto_play?40:39;text_x=x-416;column=(x-416)>>5;choose_label=1;end
   else if(x>=512&&x<576)begin
    text_x=x-512;column=(x-512)>>5;choose_label=1;
    if(CLEAN_UI)begin
     line=paused?9:15;
     if(!paused&&(content_finished||video_wait||waiting_key))begin
      text_x=(x-512)&15;choose_label=0;
      case((x-512)>>4)
       0:chosen_glyph=waiting_key?9'd43:content_finished?9'd37:9'd55;
       1:chosen_glyph=waiting_key?9'd37:content_finished?9'd46:9'd33;
       2:chosen_glyph=waiting_key?9'd57:content_finished?9'd36:9'd41;
       3:chosen_glyph=waiting_key?9'd18:content_finished?9'd0:9'd52;
      endcase
     end
    end else line=paused?9:(freeze||(stage==3&&!music_active))?7:15;
   end
   else if(menu&&x>=640&&x<704)begin line=38;text_x=x-640;column=(x-640)>>5;choose_label=1;ink=color_accent;end
   else if(!menu&&!video_context&&x>=640&&x<704)begin line=41;text_x=x-640;column=(x-640)>>5;choose_label=1;end
   else if(!menu&&!video_context&&x>=720&&x<736)begin text_x=(x-720)&15;chosen_glyph=digit({2'b0,cache_ready});ink=CLEAN_UI?color_text:color_curve;end
   else if(CLEAN_UI&&!menu&&page_loading&&x>=768&&x<880)begin
    text_x=(x-768)&15;ink=color_accent;
    case((x-768)>>4)0:chosen_glyph=55;1:chosen_glyph=33;2:chosen_glyph=41;3:chosen_glyph=52;5:chosen_glyph=digit(pending_page+1'b1);endcase
   end
   else if(CLEAN_UI&&x>=960&&x<1024)begin line=view==2?22:21;text_x=x-960;column=(x-960)>>5;choose_label=1;ink=color_dim;end
   else if(CLEAN_UI&&x>=1056&&x<1120)begin line=(freeze||(stage==3&&!music_active))?7:47;text_x=x-1056;column=(x-1056)>>5;choose_label=1;ink=(freeze||(stage==3&&!music_active))?color_accent:color_text;end
  end else if(menu&&y>=56&&y<88&&x>=32&&x<896)begin
   // 菜单仅显示当前参数，空白像素透出原图。
   text_region=1;text_y=y-56;text_x=x-32;column=(x-32)>>5;line=selection+1;
   if(selection==6)line=40;if(selection==7)line=32;
   case(selection)
    0:setting_value=volume;1:setting_value=brightness;2:setting_value=contrast;3:setting_value=transition;4:setting_value=view;
    5:setting_value=low_frequency;
   endcase
   if(x<192)begin choose_label=1;ink=CLEAN_UI?color_accent:color_curve;end
   else if(x>=224&&x<416)begin
    text_x=x-224;column=(x-224)>>5;ink=color_accent;
    if(selection==6)begin line=full_demo?58:62;column=(x-224)>>4;choose_label=1;end
    else if(selection==7&&x<256)begin text_x=(x-224)&15;chosen_glyph=x<240?digit(period_tens):digit(period_setting[0]?4'd0:4'd5);end
    else if(selection==7&&x>=272&&x<288)begin text_x=(x-272)&15;chosen_glyph=9'd83;end
    else if(selection==7)chosen_glyph=0;
    else if(selection==3)begin line=17+transition;choose_label=1;end
    else if(selection==4)begin line=view==1?21:22;choose_label=1;end
    else if(selection==5)begin line=setting_value?27:28;choose_label=1;end
    else if(x<256)begin text_x=(x-224)&15;chosen_glyph=x<240?(setting_value>=10?digit(1):9'd0):digit(setting_value>=10?setting_value-10:setting_value);end
   end
  end else if(show_analysis&&view!=0&&y>=560&&y<592&&x>=32&&x<1184)begin
   text_region=1;text_y=y-560;
   if(x<544)begin
    if(music_active||content_finished)begin
     text_x=(x-32)&15;column=(x-32)>>4;choose_label=1;ink=color_accent;
     if(content_finished)begin choose_label=0;case(column)0:chosen_glyph=9'd37;1:chosen_glyph=9'd46;2:chosen_glyph=9'd36;endcase end
     else line=57;
    end else begin line=11+((x-32)>>7);column=((x-32)&127)>>5;text_x=(x-32)&31;choose_label=column<2;ink=((x-32)>>7)==stage?color_accent:color_dim;end
   end
   else if(x>=608&&x<672)begin line=view==1?21:22;text_x=x-608;column=(x-608)>>5;choose_label=1;end
   else if(x>=704&&x<816)begin
    text_x=(x-704)&15;
    if(view==1)case((x-704)>>4)
     0:chosen_glyph=digit(low_frequency?4:5);1:chosen_glyph=low_frequency?digit(2):9'd14;2:chosen_glyph=low_frequency?9'd14:digit(3);3:chosen_glyph=digit(low_frequency?6:3);
     4:chosen_glyph=low_frequency?digit(7):9'd77;5:chosen_glyph=low_frequency?9'd77:9'd83;6:chosen_glyph=low_frequency?9'd83:9'd0;
    endcase
    else case((x-704)>>4)
     0:chosen_glyph=digit(0);1:chosen_glyph=13;2:chosen_glyph=digit(low_frequency?7:6);3:chosen_glyph=low_frequency?digit(5):9'd75;4:chosen_glyph=low_frequency?digit(0):9'd40;
     5:chosen_glyph=low_frequency?9'd40:9'd90;6:chosen_glyph=low_frequency?9'd90:9'd0;
    endcase
   end else if(x>=864&&x<928)begin line=low_frequency?6:43;text_x=x-864;column=(x-864)>>5;choose_label=1;end
   else if(view==2&&x>=960&&x<1088)begin line=56;text_x=x-960;column=(x-960)>>5;choose_label=1;ink=color_dim;end
  end else if(show_analysis&&view!=0&&x>=1088&&x<1264&&((y>=592&&y<608)||(y>=616&&y<632)||(y>=644&&y<660)))begin
   text_region=1;text_x=(x-1088)&15;column=(x-1088)>>4;text_y=(y>=644?y-644:y>=616?y-616:y-592)<<1;
   if(view==1)begin
    if(y>=616&&y<632)case(column)0:chosen_glyph=digit(0);1:chosen_glyph=38;2:chosen_glyph=51;endcase
    else if(column==0)chosen_glyph=y>=644?9'd13:9'd11;
    else chosen_glyph=((range_label>>((10-column)*8))&8'hff)-9'd32;
   end else begin
    if(y<608)begin line=63;choose_label=1;end
    else if(y>=644&&column==0)chosen_glyph=digit(0);
   end
  end else if(show_analysis&&view==2&&y>=668&&y<684&&((x>=96&&x<176)||(x>=224&&x<304)||(x>=496&&x<560)||(x>=1008&&x<1072)))begin
   text_region=1;line={3'b110,low_frequency,frequency_tick};column={3'b0,frequency_column};choose_label=1;
   text_x=x&15;text_y=(y-668)<<1;ink=color_dim;
  end else if(show_subtitle&&y>=684&&y<716&&x>=32&&x<1248&&subtitle_matches&&scrolled<subtitle_extent)begin
   subtitle_region=1;text_region=1;text_x=scrolled[10:0];text_y=y-684;
  end
 end
 reg [8:0] glyph0;reg [4:0] row0,bit0,bit1;reg text0,text1,sub0;wire [31:0] glyph_row;reg [8:0] subglyph0;
 wire [8:0] address_glyph=sub0?subglyph0:glyph0;
 wire font_pixel,font_halo;
 s4_font32 #(.PIPELINE_PIXELS(CLEAN_UI)) font(.clk(clk),.address({address_glyph,row0}),.pixel_column(bit0),.data(glyph_row),.pixel_ink(font_pixel),.pixel_halo(font_halo));
 wire [31:0] glyph_shadow=(glyph_row<<1)|(glyph_row>>1);
 reg signed [13:0] product_r,product_g,product_b;
 function [7:0] finish_adjust;input signed [13:0] product;reg signed [15:0] n;begin n=(product>>>3)+128+($signed({1'b0,brightness})-8)*8;finish_adjust=n<0?0:n>255?255:n;end endfunction
 reg [23:0] bg0,bg1,bg2,bg3,ink2,ink3;reg [5:0] vp,up,lp;reg text2,text3,glyph_ink,glyph_halo;
 // 淡变乘法使用器件乘法器，降低逻辑进位链的时序压力。
 wire [35:0] fade_product[0:2];genvar channel;
 generate for(channel=0;channel<3;channel=channel+1)begin:fade_dsp
  EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),.OUTPUTREG("DISABLE"),.MODE("MULT18X18C")) mul(
   .a({10'b0,bg0[channel*8+:8]}),.b({12'b0,fade_gain}),.p(fade_product[channel]),
   .signeda(1'b0),.signedb(1'b0),.acin(18'b0),.bcin(18'b0),.sourcea(1'b1),.sourceb(1'b1),
   .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(clk),.rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1));
 end endgenerate
 wire ascii_cell=(y>=16&&y<48&&((x>=96&&x<288)||(x>=352&&x<416)||(x>=720&&x<736)||(video_context&&((x>=32&&x<112)||(x>=288&&x<352)))||(CLEAN_UI&&((x>=768&&x<880)||(x>=512&&x<576&&!paused&&(content_finished||video_wait||waiting_key))))))||
  (y>=56&&y<88&&x>=224&&x<416&&(selection<3||selection>=6))||
  (y>=560&&y<592&&((x>=704&&x<816)||((music_active||content_finished)&&x>=32&&x<544)))||(x>=1088&&x<1264&&y>=592&&y<660)||
  (view==2&&y>=668&&y<684);
 reg [10:0] plotx0,ploty0;reg plot0,plot1,grid0,grid1,accent0,accent1;reg [1:0] view0;
 reg [10:0] x0,x1;reg plot_result;
 // 相邻波形样本间做四列插值，减少显示台阶。
 reg signed [15:0] previous_sample;
 wire signed [17:0] current_extended={{2{wave_value[15]}},wave_value};
 wire signed [17:0] previous_extended={{2{previous_sample[15]}},previous_sample};
 // 两个 16 位有符号样本相加使用 17 位，避免无用位宽。
 wire signed [16:0] pair_sum=$signed(wave_value)+$signed(previous_sample);
 reg signed [17:0] wave_scaled;
 always @*begin
  if(plotx0<4)wave_scaled=current_extended<<<2;
  else case(plotx0[1:0])
   0:wave_scaled=pair_sum+(previous_extended<<<1);
   1:wave_scaled=pair_sum<<<1;
   2:wave_scaled=pair_sum+(current_extended<<<1);
   3:wave_scaled=current_extended<<<2;
  endcase
 end
 // 加权样本与底图流水对齐，普通配置五拍，CLEAN_UI 配置六拍。
 reg signed [10:0] interpolated_delta;
 reg [10:0] ploty1;reg first_column1;reg [1:0] view1;
 reg signed [10:0] wave_delta;
 always @*case(wave_range)
  0:wave_delta=wave_scaled>>>13;1:wave_delta=wave_scaled>>>12;
  2:wave_delta=wave_scaled>>>11;3:wave_delta=wave_scaled>>>10;
  4:wave_delta=wave_scaled>>>9;5:wave_delta=wave_scaled>>>8;
  default:wave_delta=wave_scaled>>>7;
 endcase
 wire signed [10:0] wy=11'sd624-interpolated_delta;
 reg signed [10:0] previous_pixel_y;
 wire current_lower=$signed({1'b0,ploty1[9:0]})>=wy-11'sd1;
 wire current_upper=$signed({1'b0,ploty1[9:0]})<=wy+11'sd1;
 wire previous_lower=$signed({1'b0,ploty1[9:0]})>=previous_pixel_y-11'sd1;
 wire previous_upper=$signed({1'b0,ploty1[9:0]})<=previous_pixel_y+11'sd1;
 wire wave_pixel=first_column1?(current_lower&&current_upper):
  ((current_lower&&previous_upper)||(previous_lower&&current_upper));
 function [6:0] compressed_height;input [15:0] value;begin
  if(value<=256)compressed_height=value>>4;
  else if(value<=1024)compressed_height=7'd12+value[10:6];
  else if(value<=4096)compressed_height=7'd24+value[12:8];
  else if(value<=16384)compressed_height=7'd36+value[14:10];
  else compressed_height=7'd48+value[15:12];
 end endfunction
 wire [6:0] bar_height=compressed_height(spectrum_value);
 wire plot_pixel=bar_height!=0&&ploty0>=656-bar_height&&ploty0<656&&plotx0[4:0]<26;
 always @(posedge clk)begin
  if(rst)begin
   current_token<=0;progress<=32;scroll<=0;subtitle_seen<=0;subtitle_length_seen<=0;seen_source_width<=0;seen_source_height<=0;
   glyph0<=0;row0<=0;bit0<=0;bit1<=0;text0<=0;text1<=0;sub0<=0;line_reg<=0;column_reg<=0;override0<=0;label0<=0;
   row_pre<=0;bit_pre<=0;text_pre<=0;sub_pre<=0;subglyph0<=0;ink_pre<=0;ink0<=0;ink1<=0;
   bg0<=0;bg1<=0;bg2<=0;bg3<=0;ink2<=0;ink3<=0;text2<=0;text3<=0;glyph_ink<=0;glyph_halo<=0;vp<=0;up<=0;lp<=0;plotx0<=0;ploty0<=0;plot0<=0;plot1<=0;view0<=0;plot_result<=0;
   grid0<=0;grid1<=0;accent0<=0;accent1<=0;previous_sample<=0;previous_pixel_y<=624;x0<=0;x1<=0;
   interpolated_delta<=0;ploty1<=0;first_column1<=1;view1<=0;
   product_r<=0;product_g<=0;product_b<=0;out_valid<=0;out_user<=0;out_last<=0;out_rgb<=0;
  end else begin
   seen_source_width<=source_width;seen_source_height<=source_height;
   subtitle_seen<=subtitle_matches;subtitle_length_seen<=subtitle_length;
   if(token!=current_token)begin current_token<=token;progress<=transition==0?32:0;scroll<=0;end
   else if(frame_start)begin
    if(progress<32)progress<=progress+1'b1;
    if(!paused&&subtitle_matches)begin
     if({1'b0,scroll}>=scroll_limit-2)scroll<=0;else scroll<=scroll+2'd2;
    end
   end
   if(!subtitle_matches||!subtitle_seen||subtitle_length!=subtitle_length_seen)scroll<=0;
   line_reg<=line;column_reg<=column;override0<=chosen_glyph;label0<=choose_label;
   // 文字起点按 32 像素对齐，直接取局部字形行号。
   row_pre<=text_y[4:0];
   bit_pre<=subtitle_region?scrolled[4:0]:ascii_cell?{1'b0,x[3:0]}:x[4:0];text_pre<=text_region;sub_pre<=subtitle_region;ink_pre<=ink;
   glyph0<=label0?text_glyph:override0;row0<=row_pre;bit0<=bit_pre;bit1<=bit0;text0<=text_pre;text1<=text0;
   sub0<=sub_pre;subglyph0<=subtitle_glyph;ink0<=ink_pre;ink1<=ink0;
   product_r<=($signed({1'b0,rgb[23:16]})-14'sd128)*$signed({1'b0,contrast});
   product_g<=($signed({1'b0,rgb[15:8]})-14'sd128)*$signed({1'b0,contrast});
   product_b<=($signed({1'b0,rgb[7:0]})-14'sd128)*$signed({1'b0,contrast});
   bg0<={finish_adjust(product_r),finish_adjust(product_g),finish_adjust(product_b)};x0<=x;x1<=x0;
   plot0<=show_analysis&&view!=0&&x>=32&&x<1056&&y>=592&&y<658;plotx0<=x-32;ploty0<=y;view0<=view;
   grid0<=show_analysis&&((view!=0&&x>=32&&x<1056&&y>=592&&y<=656&&(y==592||y==624||y==656||(((x-32)&255)==0&&y[2:0]==0)))||
    (view==2&&y>=664&&y<668&&(x==141||x==269||x==525||x==1037)));
   accent0<=menu&&((x>=20&&x<23&&y>=56&&y<88)||(x>=224&&x<352&&y>=92&&y<94));
   plot1<=plot0;grid1<=grid0;accent1<=accent0;plot_result<=plot_pixel;
   interpolated_delta<=wave_delta;ploty1<=ploty0;first_column1<=plotx0==0;view1<=view0;
   if(plot0&&plotx0[1:0]==3)previous_sample<=wave_value;
   if(plot1)previous_pixel_y<=wy;
   bg1<=accent1?color_curve:plot1&&(view1==1?wave_pixel:plot_result)?color_curve:grid1?color_grid:bg0;
   if(transition==1&&fade_gain<32)bg1<={fade_product[2][12:5],fade_product[1][12:5],fade_product[0][12:5]};
   if(transition==2&&x1>progress*40)bg1<=0;
   bg2<=bg1;ink2<=ink1;text2<=text1;glyph_ink<=font_pixel;glyph_halo<=font_halo;
   bg3<=bg2;ink3<=ink2;text3<=text2;
   // 颜色和有效、帧首、行尾信号使用相同流水延迟。
   vp<={vp[4:0],valid};up<={up[4:0],user};lp<={lp[4:0],last};
   out_valid<=CLEAN_UI?vp[4]:vp[3];out_user<=CLEAN_UI?up[4]:up[3];out_last<=CLEAN_UI?lp[4]:lp[3];
   if(CLEAN_UI)out_rgb<=width_digits==0?24'b0:text3&&glyph_ink?ink3:text3&&glyph_halo?color_halo:bg3;
   else out_rgb<=width_digits==0?24'b0:text2&&glyph_ink?ink2:text2&&glyph_halo?color_halo:bg2;
  end
 end
endmodule
