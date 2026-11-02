`timescale 1ns/1ps

// 双时钟 PCM 缓冲与音频输出
module s4_pcm_player #(
    parameter integer ADDR_BITS=12,START_LEVEL=1024,RECOVER_LEVEL=512,
    parameter integer PIXEL_HZ=74242424,SAMPLE_HZ=48000
)(
    input mem_clk,mem_rst,flush,input [15:0] track_token,
    input pcm_valid,input [15:0] pcm_left,pcm_right,output pcm_ready,
    input producer_eof,input paused,input [3:0] volume,
    output flush_busy,output [ADDR_BITS:0] write_level,
    output reg [31:0] enqueued,enqueued_nonzero,output reg [ADDR_BITS:0] high_water,
    input pixel_clk,pixel_rst,
    output reg sample_valid,output reg [23:0] sample_left,sample_right,
    output reg consumed,output reg [15:0] consumed_left,consumed_right,
    output reg [31:0] consumed_samples,consumed_nonzero,underflows,startup_wait,output reg underflow_seen,
    output reg [15:0] active_token,output reg [2:0] playback_mode,
    output reg [ADDR_BITS:0] low_water,output [ADDR_BITS:0] read_level
);
    // 读写指针用格雷码跨域，清空缓冲须等待读取端确认后才能重新写入。
    localparam DEPTH=1<<ADDR_BITS;
    reg [ADDR_BITS:0] wr_bin,wr_gray,rd_bin,rd_gray;
    reg [ADDR_BITS:0] rd_g1,rd_g2,wr_g1,wr_g2;
    reg flush_req,flush_ack;reg [1:0] req_sync,ack_sync;
    reg [1:0] eof_sync,pause_sync;
    reg [3:0] vol_s1,vol_s2;
    reg [15:0] token_mail;
    wire [31:0] ram_data;
    function [ADDR_BITS:0] from_gray;input [ADDR_BITS:0] g;integer b;begin
        from_gray[ADDR_BITS]=g[ADDR_BITS];
        for(b=ADDR_BITS-1;b>=0;b=b-1)from_gray[b]=from_gray[b+1]^g[b];
    end endfunction
    assign flush_busy=flush_req!=ack_sync[1];
    assign write_level=flush_busy?0:wr_bin-from_gray(rd_g2);
    assign read_level=(req_sync[1]!=flush_ack)?0:from_gray(wr_g2)-rd_bin;
    wire full=write_level>=DEPTH;
    wire empty=rd_gray==wr_g2;
    assign pcm_ready=!mem_rst && !flush && !flush_busy && !full;
    wire put=pcm_valid&&pcm_ready;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(ADDR_BITS),.ADDR_WIDTH_B(ADDR_BITS),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K")) u_pcm(
        .clka(mem_clk),.cea(1'b1),.ocea(1'b1),.wea(put),.addra(wr_bin[ADDR_BITS-1:0]),.dia({pcm_right,pcm_left}),.rsta(1'b0),.bea(1'b1),
        .clkb(pixel_clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(rd_bin[ADDR_BITS-1:0]),.dib(32'b0),.rstb(1'b0),.beb(1'b1),.dob(ram_data));
    always @(posedge mem_clk)begin
        if(mem_rst)begin
            wr_bin<=0;wr_gray<=0;rd_g1<=0;rd_g2<=0;flush_req<=0;ack_sync<=0;token_mail<=0;
            enqueued<=0;enqueued_nonzero<=0;high_water<=0;
        end else begin
            rd_g1<=rd_gray;rd_g2<=rd_g1;ack_sync<={ack_sync[0],flush_ack};
            if(flush && !flush_busy)begin
                wr_bin<=0;wr_gray<=0;flush_req<=~flush_req;token_mail<=track_token;
                enqueued<=0;enqueued_nonzero<=0;high_water<=0;
            end else if(!flush_busy)begin
                if(write_level>high_water)high_water<=write_level;
                if(put)begin
                    wr_bin<=wr_bin+1'b1;wr_gray<=((wr_bin+1'b1)>>1)^(wr_bin+1'b1);
                    if(enqueued!=32'hffffffff)enqueued<=enqueued+1'b1;
                    if((pcm_left!=0 || pcm_right!=0) && enqueued_nonzero!=32'hffffffff)enqueued_nonzero<=enqueued_nonzero+1'b1;
                end
            end
        end
    end
    reg [31:0] phase;
    wire [32:0] phase_sum={1'b0,phase}+SAMPLE_HZ;
    wire tick=phase_sum>=PIXEL_HZ;
    wire signed [20:0] scaled_l=$signed(ram_data[15:0])*$signed({1'b0,vol_s2});
    wire signed [20:0] scaled_r=$signed(ram_data[31:16])*$signed({1'b0,vol_s2});
    reg started,recover;
    reg nonzero_pending;
    always @(posedge pixel_clk)begin
        if(pixel_rst)begin
            rd_bin<=0;rd_gray<=0;wr_g1<=0;wr_g2<=0;req_sync<=0;flush_ack<=0;eof_sync<=0;pause_sync<=0;vol_s1<=8;vol_s2<=8;
            sample_valid<=0;sample_left<=0;sample_right<=0;consumed<=0;consumed_left<=0;consumed_right<=0;
            consumed_samples<=0;consumed_nonzero<=0;underflows<=0;underflow_seen<=0;startup_wait<=0;active_token<=0;playback_mode<=0;
            phase<=0;started<=0;recover<=0;low_water<=DEPTH;nonzero_pending<=0;
        end else begin
            wr_g1<=wr_gray;wr_g2<=wr_g1;req_sync<={req_sync[0],flush_req};
            eof_sync<={eof_sync[0],producer_eof};pause_sync<={pause_sync[0],paused};vol_s1<=volume;vol_s2<=vol_s1>8?8:vol_s1;
            sample_valid<=0;consumed<=0;nonzero_pending<=0;
            if(nonzero_pending&&consumed_nonzero!=32'hffffffff)consumed_nonzero<=consumed_nonzero+1'b1;
            phase<=tick?(phase_sum-PIXEL_HZ):phase_sum;
            // 清空请求到达后先复位读指针，再确认新音轨。
            if(req_sync[1]!=flush_ack)begin
                rd_bin<=0;rd_gray<=0;wr_g1<=0;wr_g2<=0;flush_ack<=req_sync[1];active_token<=token_mail;
                consumed_samples<=0;consumed_nonzero<=0;nonzero_pending<=0;underflows<=0;startup_wait<=0;started<=0;recover<=0;low_water<=DEPTH;playback_mode<=0;
            end else begin
                // 预充到启动水位再播放，欠载后先补充到恢复水位。
                if(!started && (read_level>=START_LEVEL || (eof_sync[1]&&!empty)))begin started<=1;recover<=0;end
                if(recover && (read_level>=RECOVER_LEVEL || eof_sync[1]))recover<=0;
                if(tick)begin
                    sample_valid<=1;sample_left<=0;sample_right<=0;
                    if(pause_sync[1])playback_mode<=2;
                    else if(!started)begin
                        playback_mode<=eof_sync[1]&&empty?4:0;
                        if(!(eof_sync[1]&&empty) && startup_wait!=32'hffffffff)startup_wait<=startup_wait+1'b1;
                    end
                    else if(!empty && !recover)begin
                        // 音量按 volume/8 缩放，再扩展为 24 位 HDMI 采样。
                        sample_left<={scaled_l[18:3],8'b0};sample_right<={scaled_r[18:3],8'b0};
                        consumed<=1;consumed_left<=scaled_l[18:3];consumed_right<=scaled_r[18:3];
                        rd_bin<=rd_bin+1'b1;rd_gray<=((rd_bin+1'b1)>>1)^(rd_bin+1'b1);
                        if(consumed_samples!=32'hffffffff)consumed_samples<=consumed_samples+1'b1;
                        nonzero_pending<=scaled_l!=0 || scaled_r!=0;
                        if(read_level<low_water)low_water<=read_level;
                        playback_mode<=1;
                    end else if(empty && eof_sync[1])playback_mode<=4;
                    else begin
                        playback_mode<=3;
                        if(!recover)begin recover<=1;underflow_seen<=1;if(underflows!=32'hffffffff)underflows<=underflows+1'b1;end
                    end
                end
            end
        end
    end
endmodule
