`timescale 1ns/1ps

// 多媒体共享读卡与加载调度
module s4_media_io(
    input clk,rst,input catalog_done,input [7:0] wav_mask,sub_mask,input music_available,
    input movie_start,movie_cancel,movie_need,output reg movie_file_start,output reg [31:0] movie_file_size,
    output movie_valid,output [7:0] movie_data,output movie_last,input movie_take,output reg [7:0] movie_file_error,
    input image_start,image_cancel,input [2:0] image_id,image_slot,input [15:0] image_epoch,
    output image_idle,output reg image_done,image_aborted,output reg [7:0] image_error,
    output [10:0] image_width,image_height,output [15:0] source_width,source_height,
    input track_start,track_showcase,input [2:0] track_id,input [15:0] track_token,
    output reg pcm_flush,output reg [15:0] pcm_token,input pcm_flush_busy,input [12:0] pcm_level,
    output pcm_valid,output [15:0] pcm_left,pcm_right,input pcm_ready,output reg pcm_eof,
    output [31:0] wav_samples,wav_nonzero,output [7:0] wav_error,
    output reg subtitle_start,output subtitle_valid,output [7:0] subtitle_byte,output subtitle_last,output [2:0] subtitle_id,
    output reg fs_request,output reg [1:0] fs_kind,output reg [2:0] fs_id,output reg fs_reopen,fs_music,input fs_ready,
    input fs_start,fs_done,input [1:0] fs_response_kind,input fs_valid,input [7:0] fs_byte,output fs_take,input fs_last,
    input [31:0] fs_size,fs_offset,input [7:0] fs_error,
    output writer_cmd,output [20:0] writer_addr,output [6:0] writer_words,input writer_ready,writer_done,
    input [5:0] write_index,input write_active,output [31:0] write_data,
    output [31:0] decoded_pixels,generated_pixels,written_pixels,scale_stalls,
    output reg [31:0] image_sector_count,audio_sector_count,audio_wait_cycles,
    output reg [7:0] first_file_error
);
    reg img_active,img_first,img_eof,cancelled,img_decoder_started;
    reg movie_active,movie_first,movie_eof,movie_drop,movie_restart;
    reg [2:0] img_id,img_slot;reg [15:0] img_epoch;
    reg fs_busy;reg [1:0] owner;reg first_request;
    assign movie_valid=fs_valid&&owner==3&&movie_active&&!movie_drop&&!movie_cancel;
    assign movie_data=fs_byte;assign movie_last=fs_last;
    reg audio_active,audio_first,audio_file_eof,audio_restart,audio_decoder_started;
    reg sub_active,sub_first;reg [2:0] sub_id;
    reg audio_showcase,pending_showcase;reg [2:0] audio_id,pending_audio_id;reg [15:0] pending_audio_token;
    reg [2:0] audio_quota;reg [2:0] audio_state;
    reg bmp_start,wav_start;
    wire bmp_done,bmp_ready,ip,ir,down_ready,pv,pr,rl,orl,td,writer_idle,filter_idle;
    wire [23:0] pixel,input_pixel;wire [10:0] ix,iy,sw,sh;wire [9:0] px,py;
    wire [7:0] bmp_error;wire [31:0] filter_accepted;
    wire wav_byte_ready,wav_done,wav_format;wire decoder_pcm_valid;wire stereo;wire [31:0] expected_samples;
    wire abort_image=cancelled||image_cancel||image_error!=0;
    assign image_idle=!img_active;
    assign subtitle_valid=fs_valid&&owner==2;assign subtitle_byte=fs_byte;assign subtitle_last=fs_last;assign subtitle_id=sub_id;
    assign fs_take=owner==0?(abort_image||bmp_error!=0?1'b1:bmp_ready):owner==1?(audio_restart||wav_error!=0?1'b1:wav_byte_ready):owner==3?(movie_drop||movie_cancel?1'b1:movie_take):1'b1;
    // 图片依次完成解码、比例缩放和突发写入。
    s4_bmp_decode bmp(.clk(clk),.rst(rst),.start(bmp_start),.abort(abort_image),.file_size(fs_size),
        .byte_valid(fs_valid&&owner==0),.byte_data(fs_byte),.byte_ready(bmp_ready),.byte_last(fs_last),
        .pixel_valid(ip),.pixel(input_pixel),.pixel_x(ix),.pixel_y(iy),.row_last(rl),.pixel_ready(ir),
        .done(bmp_done),.error_code(bmp_error),.image_width(sw),.image_height(sh),.source_width(source_width),.source_height(source_height),.top_down(td),.pixels_out(decoded_pixels));
    s4_down2 down(.clk(clk),.rst(rst),.start(bmp_start),.abort(abort_image||bmp_error!=0),.width(sw),.height(sh),.top_down(td),
        .in_valid(ip),.in_pixel(input_pixel),.in_x(ix),.in_y(iy),.in_row_last(rl),.in_ready(ir),
        .out_valid(pv),.out_pixel(pixel),.out_x(px),.out_y(py),.out_row_last(orl),.out_ready(pr),
        .out_width(image_width),.out_height(image_height),.accepted(filter_accepted),.generated(generated_pixels),.stall_cycles(scale_stalls),.idle(filter_idle));
    s4_image_writer writer(.clk(clk),.rst(rst),.start(bmp_start),.abort(abort_image||bmp_error!=0),.buffer_id(img_slot),
        .pixel_valid(pv),.pixel(pixel),.pixel_x(px),.pixel_y(py),.row_last(orl),.pixel_ready(pr),.idle(writer_idle),
        .cmd_valid(writer_cmd),.cmd_addr(writer_addr),.cmd_words(writer_words),.cmd_ready(writer_ready),.cmd_done(writer_done),
        .write_index(write_index),.write_active(write_active),.write_data(write_data),.written_pixels(written_pixels));
    assign pcm_valid=decoder_pcm_valid&&!audio_restart&&!pcm_flush_busy;
    s4_wav wav(.clk(clk),.rst(rst),.start(wav_start),.cancel(audio_restart),.file_size(fs_size),
        .byte_valid(fs_valid&&owner==1&&!audio_restart),.byte_data(fs_byte),.byte_ready(wav_byte_ready),.byte_last(fs_last),
        .sample_valid(decoder_pcm_valid),.sample_left(pcm_left),.sample_right(pcm_right),.sample_ready(pcm_ready&&!audio_restart&&!pcm_flush_busy),
        .format_ready(wav_format),.done(wav_done),.error_code(wav_error),.stereo(stereo),.expected_samples(expected_samples),.samples_out(wav_samples),.nonzero_samples(wav_nonzero));
    // 音频紧急补充优先，高于紧急水位时限制连续配额，兼顾图片预读。
    wire want_audio=audio_active&&!audio_file_eof&&!audio_restart&&audio_state==0&&(audio_first||wav_error==0)&&pcm_level<3072;
    wire want_image=img_active&&!img_eof&&!abort_image;
    wire want_movie=movie_active&&!movie_eof&&!movie_restart&&movie_need;
    always @(posedge clk)begin
        if(rst)begin
            movie_active<=0;movie_first<=0;movie_eof<=0;movie_drop<=1;movie_restart<=0;movie_file_start<=0;movie_file_size<=0;movie_file_error<=0;
            img_active<=0;img_first<=0;img_eof<=0;cancelled<=0;img_decoder_started<=0;img_id<=0;img_slot<=0;img_epoch<=0;
            image_done<=0;image_aborted<=0;image_error<=0;fs_busy<=0;owner<=0;first_request<=0;
            audio_active<=0;audio_first<=0;audio_file_eof<=0;audio_restart<=0;audio_decoder_started<=0;audio_showcase<=0;pending_showcase<=0;audio_id<=0;pending_audio_id<=0;pending_audio_token<=0;
            sub_active<=0;sub_first<=0;sub_id<=0;subtitle_start<=0;
            audio_quota<=0;audio_state<=0;bmp_start<=0;wav_start<=0;pcm_flush<=0;pcm_token<=0;pcm_eof<=0;
            fs_request<=0;fs_kind<=0;fs_id<=0;fs_reopen<=0;fs_music<=0;image_sector_count<=0;audio_sector_count<=0;audio_wait_cycles<=0;first_file_error<=0;
        end else begin
            fs_request<=0;bmp_start<=0;wav_start<=0;image_done<=0;pcm_flush<=0;subtitle_start<=0;movie_file_start<=0;
            if(movie_start)begin movie_restart<=1;movie_active<=0;movie_drop<=1;movie_file_error<=0;end
            if(movie_restart&&!(fs_busy&&owner==3)&&!movie_cancel)begin
                movie_restart<=0;movie_active<=1;movie_first<=1;movie_eof<=0;movie_drop<=0;
            end
            if(movie_cancel)begin movie_active<=0;movie_restart<=0;movie_drop<=1;end
            if(want_audio && fs_busy && owner!=1 && audio_wait_cycles!=32'hffffffff)audio_wait_cycles<=audio_wait_cycles+1'b1;
            if(image_start&&!img_active)begin
                img_active<=1;img_first<=1;img_eof<=0;cancelled<=0;image_error<=0;image_aborted<=0;img_decoder_started<=0;
                img_id<=image_id;img_slot<=image_slot;img_epoch<=image_epoch;
            end
            if(image_cancel&&img_active)cancelled<=1;
            if(track_start)begin pending_showcase<=track_showcase;pending_audio_id<=track_id;pending_audio_token<=track_token;audio_restart<=1;end
            if(audio_restart && !fs_busy && audio_state==0)begin
                pcm_flush<=1;pcm_token<=pending_audio_token;audio_active<=0;audio_state<=1;
            end
            if(audio_state==1)audio_state<=2;
            if(audio_state==2 && !pcm_flush_busy)begin
                audio_state<=0;
                if(pcm_token==pending_audio_token && !track_start)begin
                    audio_showcase<=pending_showcase;audio_id<=pending_audio_id;audio_first<=1;audio_file_eof<=0;audio_restart<=0;audio_decoder_started<=0;
                    audio_active<=pending_showcase?music_available:wav_mask[pending_audio_id];pcm_eof<=pending_showcase?!music_available:!wav_mask[pending_audio_id];
                    sub_id<=pending_audio_id;sub_first<=1;sub_active<=sub_mask[pending_audio_id]&&!pending_showcase;
                end
            end
            if(!fs_busy && fs_ready && catalog_done && !fs_request)begin
                if(want_audio && (pcm_level<1024 || (!want_image&&!want_movie) || audio_quota<4))begin
                    fs_request<=1;fs_kind<=1;fs_music<=audio_showcase;fs_id<=audio_id;fs_reopen<=audio_first;first_request<=audio_first;audio_first<=0;
                    fs_busy<=1;owner<=1;if(audio_quota<7)audio_quota<=audio_quota+1'b1;
                end else if(sub_active)begin
                    fs_request<=1;fs_kind<=2;fs_music<=0;fs_id<=sub_id;fs_reopen<=sub_first;first_request<=sub_first;sub_first<=0;
                    fs_busy<=1;owner<=2;
                end else if(want_movie)begin
                    fs_request<=1;fs_kind<=3;fs_music<=0;fs_id<=7;fs_reopen<=movie_first;first_request<=movie_first;movie_first<=0;
                    fs_busy<=1;owner<=3;audio_quota<=0;
                end else if(want_image)begin
                    fs_request<=1;fs_kind<=0;fs_music<=0;fs_id<=img_id;fs_reopen<=img_first;first_request<=img_first;img_first<=0;
                    fs_busy<=1;owner<=0;audio_quota<=0;
                end
            end
            if(fs_start && first_request)begin
                if(owner==0 && !abort_image)begin bmp_start<=1;img_decoder_started<=1;end
                if(owner==1 && !audio_restart)begin wav_start<=1;audio_decoder_started<=1;end
                if(owner==2)subtitle_start<=1;
                if(owner==3&&!movie_drop)begin movie_file_start<=1;movie_file_size<=fs_size;end
            end
            if(fs_done && fs_busy)begin
                fs_busy<=0;
                if(owner==0)begin
                    if(image_sector_count!=32'hffffffff)image_sector_count<=image_sector_count+1'b1;
                    if(fs_offset>=fs_size || fs_error!=0)img_eof<=1;
                    if(fs_error!=0)begin image_error<=fs_error;if(first_file_error==0)first_file_error<=fs_error;end
                end else if(owner==1)begin
                    if(audio_sector_count!=32'hffffffff)audio_sector_count<=audio_sector_count+1'b1;
                    if(fs_offset>=fs_size || fs_error!=0)audio_file_eof<=1;
                    if(fs_error!=0)begin
                        pcm_eof<=1;audio_active<=0;if(first_file_error==0)first_file_error<=fs_error;
                    end
                end else if(owner==3)begin
                    if(fs_offset>=fs_size||fs_error!=0)movie_eof<=1;
                    if(fs_error!=0)begin movie_file_error<=fs_error;movie_active<=0;movie_drop<=1;end
                end else if(owner==2)begin
                    if(fs_offset>=fs_size || fs_error!=0)sub_active<=0;
                    if(fs_error!=0 && first_file_error==0)first_file_error<=fs_error;
                end
            end
            if(audio_active && audio_decoder_started && !wav_start && !audio_restart && ((audio_file_eof&&wav_done&&!decoder_pcm_valid) || wav_error!=0))pcm_eof<=1;
            if(img_active && !(fs_busy&&owner==0) && writer_idle && filter_idle && !pv && !ip &&
                (abort_image || (img_eof&&bmp_done&&img_decoder_started)))begin
                image_done<=1;img_active<=0;image_aborted<=cancelled||image_cancel;
                if(!cancelled&&!image_cancel)begin
                    if(bmp_error!=0)image_error<=bmp_error;
                    else if(image_error==0 && (generated_pixels!=image_width*image_height || written_pixels!=image_width*image_height))image_error<=8'h34;
                end
            end
        end
    end
endmodule
