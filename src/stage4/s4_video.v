`timescale 1ns/1ps

// 多行缓存和 720p 双线性显示
module s4_video #(parameter integer FADE_STEP=2)(
    input mem_clk,mem_rst,pixel_clk,pixel_rst,
    input commit_toggle,input [2:0] commit_slot,input [2:0] commit_id,input [15:0] commit_token,commit_epoch,input commit_showcase,
    input [10:0] commit_width,commit_height,input [15:0] commit_source_width,commit_source_height,
    output reg commit_ack,
    output cmd_valid,read_priority,output [20:0] cmd_addr,output [6:0] cmd_words,input cmd_ready,cmd_done,
    input read_valid,input [5:0] read_index,input [31:0] read_data,
    input bypass,hdmi_ready,input [1:0] transition,
    output reg axis_valid,axis_user,axis_last,output reg [23:0] axis_data,
    output reg [10:0] axis_x,axis_y,output reg frame_start,
    output reg [31:0] underflow_lines,frames,output reg protocol_error,underflow_seen,
    output reg [2:0] current_slot,output reg [2:0] current_id,output reg [15:0] current_token,current_epoch,
    output reg [15:0] source_width,source_height,output reg display_valid,current_showcase,output read_idle,
    output reg [5:0] fade_level
);
    // 四行缓存按奇偶列分组，每拍读取四个相邻像素用于双线性插值。
    reg [11:0] h;reg [10:0] v,w,height,dw,dh,left,top;reg [9:0] last_column,last_row;
    reg [31:0] x_step,y_step,x_fp,y_fp;
    reg [1:0] commit_sync,bypass_sync;
    reg fit_start;wire fit_done,fit_busy;wire [10:0] fit_w,fit_h;wire [31:0] fit_xs,fit_ys;
    reg fit_prepared;
    wire commit_ready=commit_sync[1]!=commit_ack&&fit_prepared;
    // 几何计算完成后锁存提交元数据，源端保持到确认，域内扇出仍受时序检查。
    reg current_content_change;
    wire content_change=current_content_change;
    // 只有内容切换执行淡变，同一内容的视频帧不重复淡变。
    wire fade_wait=transition==1&&display_valid&&content_change&&fade_level!=0;
    reg [5:0] transition_progress;
    reg [10:0] slide_offset;
    s4_fit fit(.clk(pixel_clk),.rst(pixel_rst),.start(fit_start),.width(commit_width),.height(commit_height),
        .source_width(commit_source_width),.source_height(commit_source_height),
        .busy(fit_busy),.done(fit_done),.output_width(fit_w),.output_height(fit_h),.x_step(fit_xs),.y_step(fit_ys));
    wire [10:0] x=h-370,y=v-30;
    wire active=h>=370 && v>=30;
    wire roi=active&&display_valid&&x>=left+slide_offset&&x<left+slide_offset+dw&&y>=top&&y<top+dh;
    wire [9:0] sx=x_fp[25:16],sy=y_fp[25:16];
    wire [9:0] sx1=sx<last_column?sx+1'b1:sx,sy1=sy<last_row?sy+1'b1:sy;
    wire [31:0] next_y_fp=y_fp+y_step;
    reg [3:0] request_toggle,ack_toggle,req_s1,req_s2,ack_s1,ack_s2,ack_seen,need_request,line_ready;
    reg [39:0] request_rows;reg [9:0] next_row[0:3],ready_row[0:3];
    reg [11:0] request_pages;reg [2:0] ready_page[0:3];
    reg [63:0] request_tokens;reg [15:0] ready_token[0:3];
    reg fill_active,inflight;reg [1:0] fill_bank;reg [2:0] fill_page;reg [9:0] fill_row;reg [3:0] chunk;
    reg missing_line;
    wire [9:0] write_at={chunk,6'b0}+read_index;
    assign cmd_valid=fill_active&&!inflight;
    assign read_idle=!fill_active&&!inflight&&req_s2==ack_toggle;
    assign read_priority=fill_active || req_s2!=ack_toggle;
    assign cmd_addr=fill_page*21'h50000+fill_row*21'd640+{chunk,6'b0};
    assign cmd_words=64;
    wire available=line_ready[sy[1:0]]&&line_ready[sy1[1:0]]&&ready_row[sy[1:0]]==sy&&ready_row[sy1[1:0]]==sy1&&
        ready_page[sy[1:0]]==current_slot&&ready_page[sy1[1:0]]==current_slot&&
        ready_token[sy[1:0]]==current_epoch&&ready_token[sy1[1:0]]==current_epoch;
    reg available_pixel;
    wire [23:0] even_data[0:3],odd_data[0:3];
    genvar bank;
    generate for(bank=0;bank<4;bank=bank+1)begin:rows
        EG_LOGIC_BRAM #(.DATA_WIDTH_A(24),.DATA_WIDTH_B(24),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
            .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) even_pixels(
            .clka(mem_clk),.cea(1'b1),.ocea(1'b1),.wea(read_valid&&fill_active&&fill_bank==bank&&!write_at[0]),
            .addra(write_at[9:1]),.dia(read_data[23:0]),.rsta(1'b0),.bea(1'b1),
            .clkb(pixel_clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(sx[0]?sx1[9:1]:sx[9:1]),.dib(24'b0),.rstb(1'b0),.beb(1'b1),.dob(even_data[bank]));
        EG_LOGIC_BRAM #(.DATA_WIDTH_A(24),.DATA_WIDTH_B(24),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
            .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) odd_pixels(
            .clka(mem_clk),.cea(1'b1),.ocea(1'b1),.wea(read_valid&&fill_active&&fill_bank==bank&&write_at[0]),
            .addra(write_at[9:1]),.dia(read_data[23:0]),.rsta(1'b0),.bea(1'b1),
            .clkb(pixel_clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(sx[9:1]),.dib(24'b0),.rstb(1'b0),.beb(1'b1),.dob(odd_data[bank]));
    end endgenerate
    integer i;
    always @(posedge mem_clk)begin
        if(mem_rst)begin req_s1<=0;req_s2<=0;ack_toggle<=0;fill_active<=0;inflight<=0;fill_bank<=0;fill_page<=0;fill_row<=0;chunk<=0;end
        else begin
            req_s1<=request_toggle;req_s2<=req_s1;
            if(!fill_active)begin
                for(i=3;i>=0;i=i-1)if(req_s2[i]!=ack_toggle[i])begin
                    fill_bank<=i;fill_row<=request_rows[i*10+:10];fill_page<=request_pages[i*3+:3];fill_active<=1;chunk<=0;
                end
            end
            if(cmd_valid&&cmd_ready)inflight<=1;
            if(cmd_done&&inflight)begin inflight<=0;
                if(chunk==9)begin ack_toggle[fill_bank]<=req_s2[fill_bank];fill_active<=0;end
                else chunk<=chunk+1'b1;
            end
        end
    end
    function [23:0] bars;input [10:0] xx;begin case(xx/160)
        0:bars=24'hffffff;1:bars=24'hffff00;2:bars=24'h00ffff;3:bars=24'h00ff00;
        4:bars=24'hff00ff;5:bars=24'hff0000;6:bars=24'h0000ff;default:bars=24'h202020;endcase end endfunction
    reg [1:0] ys0,ys1;reg odd_x,clamp_x;
    reg [7:0] fx0,fy0,fy1;reg roi0,available0,bypass0,display0;
    reg [23:0] fallback0;
    reg [2:0] valid_pipe,user_pipe,last_pipe,frame_pipe;
    reg [10:0] xp0,xp1,xp2,yp0,yp1,yp2;
    wire [23:0] a=odd_x?odd_data[ys0]:even_data[ys0];
    wire [23:0] b=clamp_x?a:odd_x?even_data[ys0]:odd_data[ys0];
    wire [23:0] c=odd_x?odd_data[ys1]:even_data[ys1];
    wire [23:0] d=clamp_x?c:odd_x?even_data[ys1]:odd_data[ys1];
    reg [23:0] a_reg,b_reg,c_reg,d_reg;reg [7:0] fx_select,fy_select;reg use_select;reg [23:0] fallback_select;
    reg [23:0] horizontal0,horizontal1,fallback1;
    reg use0,use1;
    function [7:0] blend;input [7:0] p,q,f;reg signed [8:0] delta;reg signed [17:0] value;begin
        delta=$signed({1'b0,q})-$signed({1'b0,p});value=$signed({1'b0,p,8'b0})+delta*$signed({1'b0,f})+128;blend=value[15:8];
    end endfunction
    integer j;
    always @(posedge pixel_clk)begin
        if(pixel_rst)begin
            h<=0;v<=0;w<=640;height<=480;last_column<=639;last_row<=479;dw<=640;dh<=480;left<=320;top<=120;x_step<=0;y_step<=0;x_fp<=0;y_fp<=0;
            commit_sync<=0;bypass_sync<=0;fit_start<=0;fit_prepared<=0;current_content_change<=0;transition_progress<=32;slide_offset<=0;commit_ack<=0;current_slot<=0;current_id<=0;current_token<=0;current_epoch<=0;fade_level<=32;
            source_width<=0;source_height<=0;display_valid<=0;current_showcase<=0;request_toggle<=0;ack_s1<=0;ack_s2<=0;ack_seen<=0;need_request<=0;line_ready<=0;
            underflow_lines<=0;underflow_seen<=0;missing_line<=0;available_pixel<=0;frames<=0;protocol_error<=0;axis_valid<=0;axis_user<=0;axis_last<=0;axis_data<=0;axis_x<=0;axis_y<=0;frame_start<=0;
            ys0<=0;ys1<=0;odd_x<=0;clamp_x<=0;fx0<=0;fy0<=0;fy1<=0;roi0<=0;available0<=0;bypass0<=0;display0<=0;fallback0<=0;
            valid_pipe<=0;user_pipe<=0;last_pipe<=0;frame_pipe<=0;xp0<=0;xp1<=0;xp2<=0;yp0<=0;yp1<=0;yp2<=0;
            horizontal0<=0;horizontal1<=0;fallback1<=0;use0<=0;use1<=0;
            a_reg<=0;b_reg<=0;c_reg<=0;d_reg<=0;fx_select<=0;fy_select<=0;use_select<=0;fallback_select<=0;
            for(j=0;j<4;j=j+1)begin request_rows[j*10+:10]<=0;next_row[j]<=j;ready_row[j]<=0;request_pages[j*3+:3]<=0;ready_page[j]<=0;request_tokens[j*16+:16]<=0;ready_token[j]<=0;end
        end else begin
            commit_sync<={commit_sync[0],commit_toggle};bypass_sync<={bypass_sync[0],bypass};ack_s1<=ack_toggle;ack_s2<=ack_s1;fit_start<=0;
            missing_line<=0;
            available_pixel<=available;
            if(missing_line)underflow_seen<=1;
            if(missing_line&&underflow_lines!=32'hffffffff)underflow_lines<=underflow_lines+1'b1;
            if(h==8&&v==0)slide_offset<=current_slot<5&&transition==3&&transition_progress<32?(32-transition_progress)*40:0;
            if(commit_sync[1]!=commit_ack && !fit_busy && !fit_prepared && !fit_start && !fit_done)fit_start<=1;
            if(fit_done)begin fit_prepared<=1;current_content_change<=commit_token!=current_token;end
            if(h==1649)begin h<=0;if(v==749)v<=0;else v<=v+1'b1;end else h<=h+1'b1;
            if(h==0&&v==0)begin
                if(frames!=32'hffffffff)frames<=frames+1'b1;
                line_ready<=0;need_request<=15;y_fp<=0;x_fp<=0;
                if(transition_progress<32)transition_progress<=transition_progress+1'b1;
                for(j=0;j<4;j=j+1)next_row[j]<=j;
                if(transition!=1)fade_level<=32;
                else if(commit_ready&&fade_wait)fade_level<=fade_level>FADE_STEP?fade_level-FADE_STEP:6'd0;
                else if(fade_level<32)fade_level<=fade_level>=32-FADE_STEP?6'd32:fade_level+FADE_STEP;
                if(commit_ready&&!fade_wait)begin
                    commit_ack<=commit_sync[1];fit_prepared<=0;current_slot<=commit_slot;current_id<=commit_id;current_token<=commit_token;current_epoch<=commit_epoch;
                    current_showcase<=commit_showcase;
                    if(transition==1&&content_change)fade_level<=0;
                    w<=commit_width;height<=commit_height;last_column<=commit_width-1'b1;last_row<=commit_height-1'b1;source_width<=commit_source_width;source_height<=commit_source_height;
                    dw<=fit_w;dh<=fit_h;left<=(1280-fit_w)>>1;top<=(720-fit_h)>>1;x_step<=fit_xs;y_step<=fit_ys;display_valid<=1;
                    transition_progress<=0;
                end
            end else begin
                for(j=0;j<4;j=j+1)begin
                    if(need_request[j]&&ack_s2[j]==request_toggle[j]&&display_valid&&next_row[j]<height)begin
                        request_rows[j*10+:10]<=next_row[j];request_pages[j*3+:3]<=current_slot;request_tokens[j*16+:16]<=current_epoch;
                        request_toggle[j]<=~request_toggle[j];need_request[j]<=0;line_ready[j]<=0;
                    end
                end
            end
            for(j=0;j<4;j=j+1)if(ack_s2[j]!=ack_seen[j])begin
                ack_seen[j]<=ack_s2[j];line_ready[j]<=1;ready_row[j]<=request_rows[j*10+:10];ready_page[j]<=request_pages[j*3+:3];ready_token[j]<=request_tokens[j*16+:16];
            end
            if(roi)begin
                x_fp<=x_fp+x_step;
                if(x==left+slide_offset && !available_pixel&&!bypass_sync[1])missing_line<=1;
            end
            if(h==1649)begin
                x_fp<=0;
                if(active&&display_valid&&y>=top&&y<top+dh)begin
                    y_fp<=next_y_fp;
                    if(next_y_fp[25:16]>sy && sy+4<height)begin next_row[sy[1:0]]<=sy+4;need_request[sy[1:0]]<=1;end
                end
            end
            // 读缓存、水平插值、垂直插值三级流水保持匹配。
            ys0<=sy[1:0];ys1<=sy1[1:0];odd_x<=sx[0];clamp_x<=sx==sx1;fx0<=x_fp[15:8];fy0<=y_fp[15:8];
            use0<=roi&&available_pixel&&!bypass_sync[1];
            fallback0<=bypass_sync[1]||!display_valid?bars(x):roi?24'hff00ff:0;
            valid_pipe<={valid_pipe[1:0],active};user_pipe<={user_pipe[1:0],active&&x==0&&y==0};last_pipe<={last_pipe[1:0],active&&x==1279};
            frame_pipe<={frame_pipe[1:0],h==0&&v==0};xp0<=x;yp0<=y;xp1<=xp0;yp1<=yp0;xp2<=xp1;yp2<=yp1;
            a_reg<=a;b_reg<=b;c_reg<=c;d_reg<=d;fx_select<=fx0;fy_select<=fy0;use_select<=use0;fallback_select<=fallback0;
            horizontal0<={blend(a_reg[23:16],b_reg[23:16],fx_select),blend(a_reg[15:8],b_reg[15:8],fx_select),blend(a_reg[7:0],b_reg[7:0],fx_select)};
            horizontal1<={blend(c_reg[23:16],d_reg[23:16],fx_select),blend(c_reg[15:8],d_reg[15:8],fx_select),blend(c_reg[7:0],d_reg[7:0],fx_select)};
            fy1<=fy_select;use1<=use_select;fallback1<=fallback_select;
            axis_data<=use1?{blend(horizontal0[23:16],horizontal1[23:16],fy1),blend(horizontal0[15:8],horizontal1[15:8],fy1),blend(horizontal0[7:0],horizontal1[7:0],fy1)}:fallback1;
            axis_valid<=valid_pipe[2];axis_user<=user_pipe[2];axis_last<=last_pipe[2];axis_x<=xp2;axis_y<=yp2;frame_start<=frame_pipe[2];
            if(axis_valid&&!hdmi_ready)protocol_error<=1;
        end
    end
endmodule
