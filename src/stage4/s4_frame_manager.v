`timescale 1ns/1ps

// 五帧槽图片预读和切换管理
module s4_frame_manager #(
    parameter integer CLOCKS_PER_MS=50000,AUTO_BASE_MS=5000,FULL_GAP_MS=1000
)(
    input clk,rst,catalog_done,input [7:0] image_mask,
    input next_pulse,prev_pulse,replay_pulse,auto_pulse,movie_pulse,paused,full_demo,content_done,prefetch_pause,input [2:0] period_setting,
    output reg load_start,load_cancel,output reg [2:0] load_id,load_slot,
    output reg [15:0] load_epoch,input loader_idle,load_done,load_aborted,input [7:0] load_error,
    input [10:0] loaded_width,loaded_height,input [15:0] loaded_source_width,loaded_source_height,
    output reg commit_toggle,output reg [2:0] commit_slot,commit_id,
    output reg [15:0] commit_token,output reg commit_showcase,output reg [10:0] commit_width,commit_height,
    output reg [15:0] commit_source_width,commit_source_height,input commit_ack,
    output reg [2:0] front_slot,displayed_id,output reg display_valid,auto_play,
    output [4:0] valid_slots,protected_slots,output [14:0] slot_tags,
    output reg [31:0] hits,misses,cancellations,commits,
    output reg [15:0] last_load_ms,response_ms,output reg [7:0] first_error,output [2:0] requested_id,
    output [1:0] prefetch_ready
);
    // 五个槽分别缓存当前页、后三页和上一页，显示或待提交的槽禁止覆盖。
    reg [4:0] valid;reg [2:0] tags[0:4];
    // 帧槽几何信息存入块存储器，仅在提交完整图片时读取。
    wire [63:0] geometry;
    reg [2:0] geometry_slot;reg geometry_valid;
    reg [7:0] bad;
    reg [2:0] desired,return_id;reg showcase_requested;reg request_pending,loading,committing,replay_pending,lookup_counted;
    reg [1:0] ack_sync;reg [15:0] timer,ms_div,request_elapsed,loading_elapsed;
    reg full_old;
    reg count_request;reg [4:0] protect;
    reg hit,found_victim,need_job;reg [2:0] hit_slot,victim;
    reg [2:0] job_id,neighbor_next,neighbor_prev,neighbor_far,neighbor_third;
    reg [2:0] neighbor_base,neighbor_base_next,neighbor_base_far;
    reg next_cached,prev_cached,far_cached,third_cached;
    // 统计连续就绪的后续页，绕回当前页前停止。
    assign prefetch_ready=next_cached&&neighbor_next!=displayed_id?
        (far_cached&&neighbor_far!=displayed_id&&neighbor_far!=neighbor_next?
        (third_cached&&neighbor_third!=displayed_id&&neighbor_third!=neighbor_next&&neighbor_third!=neighbor_far?2'd3:2'd2):2'd1):2'd0;
    wire tick=ms_div==CLOCKS_PER_MS-1;
    wire [15:0] interval_ms=AUTO_BASE_MS*(period_setting+16'd1);
    wire [7:0] usable=image_mask&~bad;
    assign requested_id=desired;
    reg [23:0] next_lookup,prev_lookup;
    assign valid_slots=valid;assign protected_slots=protect;
    assign slot_tags={tags[4],tags[3],tags[2],tags[1],tags[0]};
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(64),.DATA_WIDTH_B(64),.ADDR_WIDTH_A(5),.ADDR_WIDTH_B(5),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) slot_geometry(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(loading&&load_done&&!load_cancel&&!load_aborted&&load_error==0),.addra({2'd0,load_slot}),
        .dia({21'd0,loaded_source_height[9:0],loaded_source_width[10:0],loaded_height,loaded_width}),.rsta(1'b0),.bea(1'b1),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb({2'd0,hit_slot}),.dib(64'b0),.rstb(1'b0),.beb(1'b1),.dob(geometry));
    always @(posedge clk)begin
        if(rst)begin geometry_slot<=0;geometry_valid<=0;end
        else begin geometry_slot<=hit_slot;geometry_valid<=hit&&valid[hit_slot];end
    end
    function [2:0] calculate_neighbor;input [2:0] start_id;input backwards;integer j;reg found;reg [2:0] candidate;begin
        calculate_neighbor=start_id;found=0;
        for(j=1;j<=8;j=j+1)begin
            candidate=backwards?(start_id-j):(start_id+j);
            if(!found && usable[candidate])begin calculate_neighbor=candidate;found=1;end
        end
    end endfunction
    function [2:0] adjacent;input [2:0] start_id;input backwards;begin
        adjacent=backwards?prev_lookup[start_id*3+:3]:next_lookup[start_id*3+:3];
    end endfunction
    integer i,integer_slot,map_index;
    always @(posedge clk)begin
        for(map_index=0;map_index<8;map_index=map_index+1)begin
            next_lookup[map_index*3+:3]<=calculate_neighbor(map_index,0);
            prev_lookup[map_index*3+:3]<=calculate_neighbor(map_index,1);
        end
        neighbor_next<=adjacent(displayed_id,0);neighbor_prev<=adjacent(displayed_id,1);neighbor_far<=adjacent(neighbor_next,0);neighbor_third<=adjacent(neighbor_far,0);
        neighbor_base<=displayed_id;neighbor_base_next<=neighbor_next;neighbor_base_far<=neighbor_far;
    end
    always @* begin
        protect=0;if(display_valid)protect[front_slot]=1;if(committing)protect[commit_slot]=1;if(loading)protect[load_slot]=1;
        hit=0;hit_slot=0;next_cached=0;prev_cached=0;far_cached=0;third_cached=0;
        for(integer_slot=0;integer_slot<5;integer_slot=integer_slot+1)begin
            if(valid[integer_slot] && tags[integer_slot]==desired)begin hit=1;hit_slot=integer_slot;end
            if(valid[integer_slot] && tags[integer_slot]==neighbor_next)next_cached=1;
            if(valid[integer_slot] && tags[integer_slot]==neighbor_prev)prev_cached=1;
            if(valid[integer_slot] && tags[integer_slot]==neighbor_far)far_cached=1;
            if(valid[integer_slot] && tags[integer_slot]==neighbor_third)third_cached=1;
        end
        need_job=0;job_id=desired;
        if(request_pending && !hit)need_job=usable[desired];
        else if(display_valid && !request_pending && !committing&&!prefetch_pause)begin
            if(!next_cached)begin need_job=1;job_id=neighbor_next;end
            // 优先预读后三页，再预读上一页。
            else if(!far_cached)begin need_job=1;job_id=neighbor_far;end
            else if(!third_cached)begin need_job=1;job_id=neighbor_third;end
            else if(!prev_cached)begin need_job=1;job_id=neighbor_prev;end
        end
        found_victim=0;victim=0;
        for(integer_slot=4;integer_slot>=0;integer_slot=integer_slot-1)
            if(!protect[integer_slot] && (!valid[integer_slot] ||
                (tags[integer_slot]!=neighbor_next && tags[integer_slot]!=neighbor_prev && tags[integer_slot]!=neighbor_far && tags[integer_slot]!=neighbor_third) || request_pending))begin
                found_victim=1;victim=integer_slot;
            end
    end
    always @(posedge clk)begin
        if(rst)begin
            valid<=0;bad<=0;desired<=0;return_id<=0;showcase_requested<=0;commit_showcase<=0;request_pending<=1;loading<=0;committing<=0;replay_pending<=0;lookup_counted<=0;ack_sync<=0;full_old<=1;
            load_start<=0;load_cancel<=0;load_id<=0;load_slot<=0;load_epoch<=0;
            commit_toggle<=0;commit_slot<=0;commit_id<=0;commit_token<=0;commit_width<=640;commit_height<=480;commit_source_width<=0;commit_source_height<=0;
            front_slot<=0;displayed_id<=0;display_valid<=0;auto_play<=0;timer<=0;ms_div<=0;request_elapsed<=0;loading_elapsed<=0;
            count_request<=0;hits<=0;misses<=0;cancellations<=0;commits<=0;last_load_ms<=0;response_ms<=0;first_error<=0;
            for(i=0;i<5;i=i+1)tags[i]<=0;
        end else begin
            load_start<=0;ack_sync<={ack_sync[0],commit_ack};
            full_old<=full_demo;
            if(tick)begin
                ms_div<=0;
                if(loading && loading_elapsed!=16'hffff)loading_elapsed<=loading_elapsed+1'b1;
                if(count_request && request_elapsed!=16'hffff)request_elapsed<=request_elapsed+1'b1;
                if(auto_play && !paused && display_valid && !request_pending && !committing && full_old==full_demo)begin
                    if(full_demo&&!content_done)timer<=0;
                    else if(timer>=(full_demo?FULL_GAP_MS:interval_ms)-1)begin
                        timer<=0;
                        if(full_demo&&neighbor_next<=displayed_id)auto_play<=0;
                        else begin desired<=neighbor_next;request_pending<=1;lookup_counted<=0;end
                    end else timer<=timer+1'b1;
                end
            end else ms_div<=ms_div+1'b1;
            if(!auto_play)timer<=0;
            if(full_old!=full_demo)timer<=0;
            if(catalog_done && usable!=0 && request_pending && !usable[desired])desired<=adjacent(desired,0);
            if(catalog_done && request_pending && usable[desired] && !lookup_counted)begin
                lookup_counted<=1;
                if(hit)begin if(hits!=32'hffffffff)hits<=hits+1'b1;end
                else if(misses!=32'hffffffff)misses<=misses+1'b1;
            end
            if(!committing && request_pending && hit && geometry_valid && geometry_slot==hit_slot && !next_pulse && !prev_pulse && !replay_pulse && !movie_pulse)begin
                if(!display_valid || hit_slot!=front_slot || replay_pending)begin
                    commit_slot<=hit_slot;commit_id<=desired;commit_token<=commit_token+1'b1;
                    commit_showcase<=showcase_requested&&desired==7;
                    commit_width<=geometry[10:0];commit_height<=geometry[21:11];
                    commit_source_width<={5'd0,geometry[32:22]};commit_source_height<={6'd0,geometry[42:33]};
                    commit_toggle<=~commit_toggle;committing<=1;replay_pending<=0;
                end else begin request_pending<=0;count_request<=0;end
            end
            if(committing && ack_sync[1]==commit_toggle)begin
                front_slot<=commit_slot;displayed_id<=commit_id;display_valid<=1;committing<=0;timer<=0;
                if(commits!=32'hffffffff)commits<=commits+1'b1;
                if(desired==commit_id)begin request_pending<=0;
                    if(count_request)begin response_ms<=request_elapsed;count_request<=0;end
                end
            end
            // 目标命中缓存时立即提交，并保留仍有用的后台预读。
            if(loading && !load_cancel &&
                ((request_pending && !hit && load_id!=desired) ||
                 (display_valid && !request_pending && !committing &&
                  neighbor_base==displayed_id && neighbor_base_next==neighbor_next && neighbor_base_far==neighbor_far &&
                  load_id!=neighbor_next && load_id!=neighbor_far && load_id!=neighbor_third && load_id!=neighbor_prev)))begin
                load_cancel<=1;if(cancellations!=32'hffffffff)cancellations<=cancellations+1'b1;
            end
            if(loading && load_done)begin
                loading<=0;load_cancel<=0;last_load_ms<=loading_elapsed;
                if(!load_cancel && !load_aborted && load_error==0)begin
                    valid[load_slot]<=1;tags[load_slot]<=load_id;
                end else if(!load_aborted && load_error!=0)begin
                    bad[load_id]<=1;if(first_error==0)first_error<=load_error;
                end
            end
            if(!loading && loader_idle && catalog_done && usable!=0 && need_job && found_victim &&
                neighbor_base==displayed_id && neighbor_base_next==neighbor_next && neighbor_base_far==neighbor_far && !next_pulse && !prev_pulse && !replay_pulse && !movie_pulse)begin
                load_id<=job_id;load_slot<=victim;load_epoch<=load_epoch+1'b1;valid[victim]<=0;
                load_start<=1;load_cancel<=0;loading<=1;loading_elapsed<=0;
            end
            if(next_pulse || prev_pulse || replay_pulse)begin
                desired<=replay_pulse?displayed_id:adjacent(request_pending?desired:displayed_id,prev_pulse);
                request_pending<=1;replay_pending<=replay_pulse;lookup_counted<=0;timer<=0;request_elapsed<=0;count_request<=1;
                auto_play<=0;
                if(next_pulse||prev_pulse)showcase_requested<=0;
            end
            if(auto_pulse&&!showcase_requested)begin auto_play<=~auto_play;timer<=0;end
            if(movie_pulse&&catalog_done&&usable[7])begin
                if(!showcase_requested)return_id<=display_valid?displayed_id:desired;
                desired<=showcase_requested?return_id:3'd7;showcase_requested<=!showcase_requested;
                request_pending<=1;replay_pending<=1;lookup_counted<=0;timer<=0;request_elapsed<=0;count_request<=1;auto_play<=0;
            end
        end
    end
endmodule
