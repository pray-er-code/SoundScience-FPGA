`timescale 1ns/1ps
// C26 最终作品系统顶层
module top_stage4_media #(parameter integer FULL_DIAGNOSTICS=0,SWITCH_STABLE_CYCLES=1000000,MANUAL_VIDEO_STEP=1,TEACHING_SAMPLES=960000)(
    input clk,rst_n,key_next_n,key_auto_n,key_diag_n,
    input [3:0] switches,input tf_miso,output tf_sck,tf_mosi,tf_cs_n,
    output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,
    inout HDMI_DDC_SDA,output [7:0] seg_data,output [5:0] seg_sel
);
    wire pixel_clk,serial_clk,av_lock,video_reset,phy_reset;
    wire mem_clk,mem_clk_sft,mem_lock,mem_reset;
    wire axis_user,axis_valid,axis_last,axis_ready;wire [23:0] axis_data;
    wire audio_valid,acr_valid;wire [23:0] audio_left,audio_right;wire [19:0] acr_cts,acr_n;
    wire edid_trigger,edid_valid,video_locked;wire [7:0] edid_data;
    wire [9:0] tmds0,tmds1,tmds2,tmdsclk;
    // 各时钟域分别释放复位，沿用已验证的时钟与移相配置。
    stage1_av_pll u_av_pll(.refclk(clk),.reset(~rst_n),.locked(av_lock),.pixel_clk(pixel_clk),.serial_clk(serial_clk));
    reset_release #(.HOLD_BITS(20)) u_video_reset(.clk(pixel_clk),.async_reset(~rst_n|~av_lock),.reset_out(video_reset));
    reset_bridge u_phy_reset(.clk(serial_clk),.async_reset(video_reset),.reset_out(phy_reset));
    stage2_sdram_pll u_mem_pll(.refclk(clk),.reset(~rst_n),.mem_clk(mem_clk),.mem_clk_sft(mem_clk_sft),.locked(mem_lock));
    reset_release #(.HOLD_BITS(16)) u_mem_reset(.clk(mem_clk),.async_reset(~rst_n|~mem_lock),.reset_out(mem_reset));
    acr_generator u_acr(.clk(pixel_clk),.reset(video_reset),.sample_valid(audio_valid),.acr_valid(acr_valid),.acr_cts(acr_cts),.acr_n(acr_n));
    startup_pulse #(.COUNT_MAX(100000)) u_edid(.clk(pixel_clk),.reset(video_reset),.pulse(edid_trigger));
    hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
        .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.VIDEO_VIC(4),
        .AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(125)) u_hdmi_core(
        .I_pixel_clk(pixel_clk),.I_rst(video_reset),.I_edid_read_trig(edid_trigger),.O_edid_read_valid(edid_valid),.O_edid_read_data(edid_data),
        .I_axis_s_user(axis_user),.I_axis_s_valid(axis_valid),.I_axis_s_last(axis_last),.I_axis_s_data(axis_data),.O_axis_s_ready(axis_ready),
        .I_audio_valid(audio_valid),.I_audio_left_data(audio_left),.I_audio_right_data(audio_right),.I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),
        .O_video_locked(video_locked),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),.O_ch0_tmds_data(tmds0),.O_ch1_tmds_data(tmds1),
        .O_ch2_tmds_data(tmds2),.O_clk_tmds_data(tmdsclk));
    hdmi_phy_stage1 u_hdmi_phy(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.pixel_reset(video_reset),.serial_reset(phy_reset),
        .channel0(tmds0),.channel1(tmds1),.channel2(tmds2),.channel_clock(tmdsclk),.tmds_d0_p(HDMI_D0_P),.tmds_d1_p(HDMI_D1_P),.tmds_d2_p(HDMI_D2_P),.tmds_clk_p(HDMI_CLK_P));

    wire next_pulse,prev_pulse,auto_pulse,replay_pulse,movie_pulse,paused,menu,low_frequency,freeze,zero_trigger,test_tone,color_bars;
    wire [3:0] selection,volume,brightness,contrast;wire [1:0] transition,view;wire light_ui,full_demo,content_done_mem;
    wire music_available,commit_showcase,cache_showcase,video_showcase;
    reg manual_start_hold;
    wire [7:0] vid_mask,movie_error,movie_file_error,movie_byte;wire movie_pause,movie_display;
    always @(posedge mem_clk)begin
        if(mem_reset)manual_start_hold<=0;
        else manual_start_hold<=commit_showcase&&music_available&&vid_mask[7]&&movie_error==0&&!movie_display;
    end
    wire movie_media_start,movie_media_cancel,movie_need,movie_file_start,movie_valid,movie_last,movie_take;
    wire [10:0] movie_width,movie_height;wire [31:0] movie_file_size,movie_decoded;wire [10:0] movie_fifo_level;wire [7:0] movie_shown;
    wire movie_commit_valid,movie_commit_ready,movie_commit_done,movie_restore;wire [2:0] movie_commit_slot;wire [15:0] movie_commit_token;
    wire image_writer_cmd,image_writer_ready,image_writer_done,image_write_active,movie_write_active;
    wire [20:0] image_writer_addr;wire [6:0] image_writer_words;wire [31:0] image_write_data;
    wire movie_writer_cmd,movie_writer_ready,movie_writer_done;wire [20:0] movie_writer_addr;wire [6:0] movie_writer_words;wire [31:0] movie_write_data;
    wire cache_commit_toggle,cache_commit_ack,cache_read_idle;wire [2:0] cache_commit_slot,cache_commit_id;
    wire [15:0] cache_commit_token,cache_commit_epoch,cache_source_width,cache_source_height;wire [10:0] cache_width,cache_height;
    wire [3:0] sw_s2;wire [2:0] period_setting;
    reg [1:0] video_lock_sync;
    always @(posedge mem_clk)begin if(mem_reset)video_lock_sync<=0;else video_lock_sync<={video_lock_sync[0],video_locked};end
    s4_switch_filter #(.STABLE_CYCLES(SWITCH_STABLE_CYCLES)) u_switches(.clk(mem_clk),.rst(mem_reset),.switches(switches),.value(sw_s2));
    s4_controls u_controls(.clk(mem_clk),.rst(mem_reset),.key_next_n(key_next_n),.key_auto_n(key_auto_n),.key_dec_n(key_diag_n),.menu_switch(sw_s2[3]),
        .next_pulse(next_pulse),.prev_pulse(prev_pulse),.auto_pulse(auto_pulse),.replay_pulse(replay_pulse),.movie_pulse(movie_pulse),.paused(paused),.menu(menu),
        .selection(selection),.volume(volume),.brightness(brightness),.contrast(contrast),.transition(transition),.view(view),
        .low_frequency(low_frequency),.freeze(freeze),.zero_trigger(zero_trigger),.test_tone(test_tone),.color_bars(color_bars),.period_setting(period_setting),.light_ui(light_ui),.full_demo(full_demo));
    wire sd_initialized,sd_req,sd_ready,sd_valid,sd_take,sd_done;
    wire [31:0] sd_lba,sectors,token_cycles,transfer_cycles,drain_cycles,sd_stalls;
    wire [7:0] sd_data,sd_error;reg [1:0] miso_sync;
    always @(posedge mem_clk)begin if(mem_reset)miso_sync<=3;else miso_sync<={miso_sync[0],tf_miso};end
    s4_sd_read #(.FAST_DIV(4)) u_sd(.clk(mem_clk),.rst(mem_reset),.sd_miso(miso_sync[1]),.sd_sck(tf_sck),.sd_mosi(tf_mosi),.sd_cs_n(tf_cs_n),
        .initialized(sd_initialized),.error_code(sd_error),.req_valid(sd_req),.req_lba(sd_lba),.req_ready(sd_ready),.data_valid(sd_valid),.data(sd_data),.data_ready(sd_take),
        .sector_done(sd_done),.sectors_read(sectors),.token_cycles(token_cycles),.transfer_cycles(transfer_cycles),.drain_cycles(drain_cycles),.stall_cycles(sd_stalls));
    wire catalog_done,fs_request,fs_reopen,fs_music,fs_ready,fs_start,fs_done,fs_valid,fs_take,fs_last;
    wire [7:0] bmp_mask,wav_mask,sub_mask,fs_byte,fat_error,file_error;wire [31:0] fs_size,fs_offset,fat_sectors,fat_hits,scan_cycles,current_cluster;
    wire [1:0] fs_kind,response_kind;wire [2:0] fs_id;
    s4_files u_fs(.clk(mem_clk),.rst(mem_reset),.card_ready(sd_initialized),.card_error(sd_error),.sd_req(sd_req),.sd_lba(sd_lba),.sd_ready(sd_ready),
        .sd_valid(sd_valid),.sd_data(sd_data),.sd_take(sd_take),.sd_done(sd_done),.catalog_done(catalog_done),.bmp_mask(bmp_mask),.wav_mask(wav_mask),.sub_mask(sub_mask),.vid_mask(vid_mask),.music_available(music_available),
        .request(fs_request),.request_kind(fs_kind),.request_id(fs_id),.reopen(fs_reopen),.request_music(fs_music),.ready(fs_ready),.response_start(fs_start),.response_done(fs_done),.response_kind(response_kind),
        .byte_valid(fs_valid),.byte_data(fs_byte),.byte_take(fs_take),.byte_last(fs_last),.file_size(fs_size),.file_offset(fs_offset),.error_code(fat_error),.file_error(file_error),
        .sectors_fat(fat_sectors),.fat_hits(fat_hits),.scan_cycles(scan_cycles),.current_cluster(current_cluster));
    wire load_start,load_cancel,loader_idle,load_done,load_aborted;wire [2:0] load_id,displayed_id,commit_id,requested_id,load_slot,commit_slot,front_slot;
    wire [15:0] load_epoch,commit_token,load_ms,response_ms;wire [10:0] image_width,image_height,commit_width,commit_height;
    wire [15:0] source_width,source_height,commit_source_width,commit_source_height;
    wire [7:0] image_error,first_media_error;wire ct,commit_ack,display_valid,auto_play;
    // 手动第八页结束后，KEY2 进入视频。
    wire next_movie=MANUAL_VIDEO_STEP&&next_pulse&&!auto_play&&display_valid&&displayed_id==7&&!commit_showcase&&content_done_mem;
    wire [4:0] valid_slots,protected_slots;wire [14:0] tags;wire [31:0] hits,misses,cancels,commits;wire [1:0] prefetch_ready;
    s4_frame_manager u_control(.clk(mem_clk),.rst(mem_reset),.catalog_done(catalog_done),.image_mask(bmp_mask),
        .next_pulse(next_pulse&&!next_movie),.prev_pulse(prev_pulse),.auto_pulse(auto_pulse),.replay_pulse(replay_pulse),.movie_pulse(movie_pulse||next_movie),.paused(paused),.full_demo(full_demo),.content_done(content_done_mem),.prefetch_pause(movie_pause),.period_setting(period_setting),
        .load_start(load_start),.load_cancel(load_cancel),.load_id(load_id),.load_slot(load_slot),.load_epoch(load_epoch),.loader_idle(loader_idle),.load_done(load_done),.load_aborted(load_aborted),.load_error(image_error),
        .loaded_width(image_width),.loaded_height(image_height),.loaded_source_width(source_width),.loaded_source_height(source_height),
        .commit_toggle(ct),.commit_slot(commit_slot),.commit_id(commit_id),.commit_token(commit_token),.commit_showcase(commit_showcase),.commit_width(commit_width),.commit_height(commit_height),
        .commit_source_width(commit_source_width),.commit_source_height(commit_source_height),.commit_ack(commit_ack),.front_slot(front_slot),.displayed_id(displayed_id),
        .display_valid(display_valid),.auto_play(auto_play),.valid_slots(valid_slots),.protected_slots(protected_slots),.slot_tags(tags),.hits(hits),.misses(misses),.cancellations(cancels),
        .commits(commits),.last_load_ms(load_ms),.response_ms(response_ms),.first_error(first_media_error),.requested_id(requested_id),.prefetch_ready(prefetch_ready));
    // 画面提交确认后才启动对应音轨，避免图音错配。
    reg [1:0] visible_ack_sync;reg [15:0] track_seen;reg track_start;
    always @(posedge mem_clk)begin
        if(mem_reset)begin visible_ack_sync<=0;track_seen<=0;track_start<=0;end
        else begin visible_ack_sync<={visible_ack_sync[0],commit_ack};track_start<=0;
            if(display_valid&&visible_ack_sync[1]==ct&&track_seen!=commit_token)begin track_seen<=commit_token;track_start<=1;end
        end
    end
    wire pcm_flush,pcm_flush_busy,pcm_valid,pcm_ready,pcm_eof;wire [15:0] pcm_left,pcm_right,pcm_token;
    wire [12:0] pcm_level,pcm_high;wire [31:0] enqueued,enqueued_nonzero,wav_samples,wav_nonzero;
    wire [7:0] wav_error;wire sub_start,sub_valid,sub_last;wire [7:0] sub_byte;wire [2:0] sub_id;
    wire writer_cmd,writer_ready,writer_done;wire [20:0] writer_addr;wire [6:0] writer_words;wire [5:0] write_index;wire [31:0] write_data,decoded,generated,written,scale_stalls;
    wire [31:0] image_sectors,audio_sectors,audio_wait;wire [7:0] media_first_file_error;
    wire wr_en;
    s4_media_io u_media(.clk(mem_clk),.rst(mem_reset),.catalog_done(catalog_done),.wav_mask(wav_mask),.sub_mask(sub_mask),.music_available(music_available),
        .movie_start(movie_media_start),.movie_cancel(movie_media_cancel),.movie_need(movie_need),.movie_file_start(movie_file_start),.movie_file_size(movie_file_size),
        .movie_valid(movie_valid),.movie_data(movie_byte),.movie_last(movie_last),.movie_take(movie_take),.movie_file_error(movie_file_error),
        .image_start(load_start),.image_cancel(load_cancel),.image_id(load_id),.image_slot(load_slot),.image_epoch(load_epoch),.image_idle(loader_idle),.image_done(load_done),.image_aborted(load_aborted),.image_error(image_error),
        .image_width(image_width),.image_height(image_height),.source_width(source_width),.source_height(source_height),.track_start(track_start),.track_showcase(commit_showcase),.track_id(commit_id),.track_token(track_seen),
        .pcm_flush(pcm_flush),.pcm_token(pcm_token),.pcm_flush_busy(pcm_flush_busy),.pcm_level(pcm_level),.pcm_valid(pcm_valid),.pcm_left(pcm_left),.pcm_right(pcm_right),.pcm_ready(pcm_ready),.pcm_eof(pcm_eof),
        .wav_samples(wav_samples),.wav_nonzero(wav_nonzero),.wav_error(wav_error),.subtitle_start(sub_start),.subtitle_valid(sub_valid),.subtitle_byte(sub_byte),.subtitle_last(sub_last),.subtitle_id(sub_id),
        .fs_request(fs_request),.fs_kind(fs_kind),.fs_id(fs_id),.fs_reopen(fs_reopen),.fs_music(fs_music),.fs_ready(fs_ready),.fs_start(fs_start),.fs_done(fs_done),.fs_response_kind(response_kind),
        .fs_valid(fs_valid),.fs_byte(fs_byte),.fs_take(fs_take),.fs_last(fs_last),.fs_size(fs_size),.fs_offset(fs_offset),.fs_error(file_error),
        .writer_cmd(image_writer_cmd),.writer_addr(image_writer_addr),.writer_words(image_writer_words),.writer_ready(image_writer_ready),.writer_done(image_writer_done),.write_index(write_index),.write_active(image_write_active),.write_data(image_write_data),
        .decoded_pixels(decoded),.generated_pixels(generated),.written_pixels(written),.scale_stalls(scale_stalls),
        .image_sector_count(image_sectors),.audio_sector_count(audio_sectors),.audio_wait_cycles(audio_wait),.first_file_error(media_first_file_error));
    wire display_cmd,display_priority,display_ready,display_done;wire [20:0] display_addr;wire [6:0] display_words;wire read_valid;wire [5:0] read_index;wire [31:0] read_data;
    wire va,vu,vl,frame_start,video_fault,vd;wire [23:0] vrgb;wire [10:0] vx,vy;wire [2:0] video_slot,video_id;wire [15:0] video_token,video_epoch,video_sw,video_sh;
    wire [31:0] underflows,frames;wire [5:0] fade_level;
    // 目标页和等待状态仅用于界面显示。
    wire [42:0] controls_mem={requested_id,requested_id!=displayed_id,1'b0,full_demo,light_ui,menu,selection,volume,brightness,contrast,transition,view,low_frequency,freeze,zero_trigger,paused,auto_play,test_tone,color_bars,prefetch_ready,period_setting,sw_s2[2:0]};
    // 界面状态在帧起点统一锁存，避免一帧中途变化。
    reg [42:0] controls_s1,controls_s2,controls_pixel;
    always @(posedge pixel_clk)begin
        if(video_reset)begin controls_s1<=0;controls_s2<=0;controls_pixel<={4'b0,1'b0,1'b1,1'b1,1'b0,4'b0,4'd8,4'd8,4'd8,2'd1,2'd1,7'b0000000,2'b0,3'd4,3'b0};end
        else begin controls_s1<=controls_mem;controls_s2<=controls_s1;if(frame_start)controls_pixel<=controls_s2;end
    end
    wire p_menu=controls_pixel[35];wire [3:0] p_selection=controls_pixel[34:31],p_volume=controls_pixel[30:27],p_brightness=controls_pixel[26:23],p_contrast=controls_pixel[22:19];
    wire [1:0] p_transition=controls_pixel[18:17],p_view=controls_pixel[16:15];
    wire p_low=controls_pixel[14],p_freeze=controls_pixel[13],p_trigger=controls_pixel[12],p_paused=controls_pixel[11],p_auto=controls_pixel[10],p_tone=controls_pixel[9],p_bars=controls_pixel[8];
    wire video_underflow_seen,pcm_underflow_seen;
    s4_video u_cache(.mem_clk(mem_clk),.mem_rst(mem_reset),.pixel_clk(pixel_clk),.pixel_rst(video_reset),.commit_toggle(cache_commit_toggle),.commit_slot(cache_commit_slot),.commit_id(cache_commit_id),.commit_token(cache_commit_token),.commit_epoch(cache_commit_epoch),.commit_showcase(cache_showcase),
        .commit_width(cache_width),.commit_height(cache_height),.commit_source_width(cache_source_width),.commit_source_height(cache_source_height),.commit_ack(cache_commit_ack),
        .cmd_valid(display_cmd),.read_priority(display_priority),.cmd_addr(display_addr),.cmd_words(display_words),.cmd_ready(display_ready),.cmd_done(display_done),.read_valid(read_valid),.read_index(read_index),.read_data(read_data),
        .bypass(p_bars),.hdmi_ready(axis_ready),.transition(p_transition),.axis_valid(va),.axis_user(vu),.axis_last(vl),.axis_data(vrgb),.axis_x(vx),.axis_y(vy),.frame_start(frame_start),
        .underflow_lines(underflows),.underflow_seen(video_underflow_seen),.frames(frames),.protocol_error(video_fault),.current_slot(video_slot),.current_id(video_id),.current_token(video_token),.current_epoch(video_epoch),.read_idle(cache_read_idle),.source_width(video_sw),.source_height(video_sh),.display_valid(vd),.current_showcase(video_showcase),.fade_level(fade_level));
    wire player_valid,consumed;wire [23:0] player_left,player_right;wire [15:0] consumed_left,consumed_right,active_token;wire [31:0] consumed_samples,consumed_nonzero,pcm_underflows,startup_wait;
    wire [12:0] pcm_low,read_level;wire [2:0] pcm_mode;
    reg manual_end_hold;
    always @(posedge pixel_clk)begin
        if(video_reset)manual_end_hold<=0;
        else manual_end_hold<=MANUAL_VIDEO_STEP&&vd&&active_token==video_token&&video_id==7&&video_slot<5&&!video_showcase&&!p_auto&&consumed_samples>=TEACHING_SAMPLES;
    end
    s4_pcm_player u_player(.mem_clk(mem_clk),.mem_rst(mem_reset),.flush(pcm_flush),.track_token(pcm_token),.pcm_valid(pcm_valid),.pcm_left(pcm_left),.pcm_right(pcm_right),.pcm_ready(pcm_ready),
        .producer_eof(pcm_eof),.paused(paused||test_tone||p_tone||manual_start_hold||manual_end_hold),.volume(volume),.flush_busy(pcm_flush_busy),.write_level(pcm_level),.enqueued(enqueued),.enqueued_nonzero(enqueued_nonzero),.high_water(pcm_high),
        .pixel_clk(pixel_clk),.pixel_rst(video_reset),.sample_valid(player_valid),.sample_left(player_left),.sample_right(player_right),.consumed(consumed),.consumed_left(consumed_left),.consumed_right(consumed_right),
        .consumed_samples(consumed_samples),.consumed_nonzero(consumed_nonzero),.underflows(pcm_underflows),.underflow_seen(pcm_underflow_seen),.startup_wait(startup_wait),.active_token(active_token),.playback_mode(pcm_mode),.low_water(pcm_low),.read_level(read_level));
    wire tone_valid;wire [23:0] tone_left,tone_right;
    audio_tone_48k u_test_audio(.clk(pixel_clk),.reset(video_reset),.sample_valid(tone_valid),.sample_left(tone_left),.sample_right(tone_right));
    assign audio_valid=player_valid;
    assign audio_left=p_tone?tone_left:(active_token==video_token?player_left:24'b0);
    assign audio_right=p_tone?tone_right:(active_token==video_token?player_right:24'b0);
    wire [7:0] wave_address;wire [4:0] spectrum_address;wire signed [15:0] wave_value;wire [15:0] spectrum_value;
    wire [31:0] analysis_blocks,stage_samples;wire [1:0] stage;wire [7:0] analysis_error;wire [2:0] wave_range;wire example_hold;
    wire music_active,content_finished,prepare_video,mem_prepare_video,mem_music_active;wire [7:0] music_frame,mem_music_frame;
    s4_playback_progress #(.MANUAL_VIDEO_STEP(MANUAL_VIDEO_STEP)) u_playback(.pixel_clk(pixel_clk),.pixel_rst(video_reset),.display_valid(vd),.showcase(video_showcase),.page_id(video_id),
        .auto_play(p_auto),.video_token(video_token),.active_token(active_token),.consumed_samples(consumed_samples),.playback_mode(manual_end_hold?3'd4:pcm_mode),
        .music_active(music_active),.content_finished(content_finished),.prepare_video(prepare_video),.music_frame(music_frame),
        .mem_clk(mem_clk),.mem_rst(mem_reset),.requested_token(commit_token),.mem_finished(content_done_mem),
        .mem_prepare(mem_prepare_video),.mem_music(mem_music_active),.mem_frame(mem_music_frame));
    s4_movie u_movie(.clk(mem_clk),.rst(mem_reset),.content_token(commit_token),.prepare(mem_prepare_video),.music(mem_music_active),.finished(content_done_mem),
        .cancel(next_pulse||prev_pulse||replay_pulse||movie_pulse),.target_frame(mem_music_frame),.available(vid_mask[7]),.static_slot(front_slot),.cache_read_idle(cache_read_idle),
        .media_start(movie_media_start),.media_cancel(movie_media_cancel),.media_need(movie_need),.file_start(movie_file_start),.file_size(movie_file_size),
        .byte_valid(movie_valid),.byte_data(movie_byte),.byte_last(movie_last),.byte_ready(movie_take),.file_error(movie_file_error),
        .writer_cmd(movie_writer_cmd),.writer_addr(movie_writer_addr),.writer_words(movie_writer_words),.writer_ready(movie_writer_ready),.writer_done(movie_writer_done),
        .write_index(write_index),.write_active(movie_write_active),.write_data(movie_write_data),
        .commit_valid(movie_commit_valid),.commit_ready(movie_commit_ready),.commit_done(movie_commit_done),.commit_slot(movie_commit_slot),.commit_token(movie_commit_token),.commit_restore(movie_restore),
        .pause_prefetch(movie_pause),.error_code(movie_error),.movie_display(movie_display),.fifo_level(movie_fifo_level),.frame_width(movie_width),.frame_height(movie_height),.shown_frame(movie_shown),.decoded_frames(movie_decoded));
    s4_display_commit_mux u_display(.clk(mem_clk),.rst(mem_reset),.normal_toggle(ct),.normal_ack(commit_ack),
        .normal_slot(commit_slot),.normal_id(commit_id),.normal_token(commit_token),.normal_showcase(commit_showcase),.normal_width(commit_width),.normal_height(commit_height),.normal_source_width(commit_source_width),.normal_source_height(commit_source_height),
        .movie_valid(movie_commit_valid),.movie_ready(movie_commit_ready),.movie_done(movie_commit_done),.movie_slot(movie_commit_slot),.movie_token(movie_commit_token),.movie_restore(movie_restore),.movie_width(movie_width),.movie_height(movie_height),
        .commit_toggle(cache_commit_toggle),.cache_ack(cache_commit_ack),.commit_slot(cache_commit_slot),.commit_id(cache_commit_id),.commit_token(cache_commit_token),.commit_epoch(cache_commit_epoch),.commit_showcase(cache_showcase),
        .commit_width(cache_width),.commit_height(cache_height),.commit_source_width(cache_source_width),.commit_source_height(cache_source_height));
    s4_write_mux u_writes(.clk(mem_clk),.rst(mem_reset),.image_valid(image_writer_cmd),.image_addr(image_writer_addr),.image_words(image_writer_words),.image_ready(image_writer_ready),.image_done(image_writer_done),.image_data(image_write_data),
        .movie_valid(movie_writer_cmd),.movie_addr(movie_writer_addr),.movie_words(movie_writer_words),.movie_ready(movie_writer_ready),.movie_done(movie_writer_done),.movie_data(movie_write_data),
        .cmd_valid(writer_cmd),.cmd_addr(writer_addr),.cmd_words(writer_words),.cmd_ready(writer_ready),.cmd_done(writer_done),.write_data(write_data),.write_active(wr_en),
        .image_write_active(image_write_active),.movie_write_active(movie_write_active));
    // 只分析当前内容实际播放的 PCM，避免旧音轨混入图表。
    s4_analysis #(.SHORT_LESSONS(1)) u_analysis(.clk(pixel_clk),.rst(video_reset),.consumed(consumed&&active_token==video_token&&!p_tone),.sample(consumed_left),.token(video_token),
        .short_lesson(video_id<6),.example_hold(example_hold),
        .low_frequency(p_low),.freeze(p_freeze||example_hold||(stage==3&&!music_active)),.zero_trigger(p_trigger),.frame_start(frame_start),.comparison_scale(video_id<2&&stage!=0),.wave_address(wave_address),.spectrum_address(spectrum_address),.wave_range(wave_range),
        .wave_value(wave_value),.spectrum_value(spectrum_value),.blocks(analysis_blocks),.stage(stage),.stage_samples(stage_samples),.first_error(analysis_error));
    wire [5:0] sub_address;wire [8:0] sub_glyph;wire sub_ready;wire [2:0] subtitle_id;wire [6:0] sub_length;wire [7:0] sub_error;
    s4_subtitle u_sub(.mem_clk(mem_clk),.mem_rst(mem_reset),.start(sub_start),.requested_id(sub_id),.byte_valid(sub_valid),.byte_data(sub_byte),.byte_last(sub_last),.error_code(sub_error),
        .pixel_clk(pixel_clk),.pixel_rst(video_reset),.glyph_address(sub_address),.glyph(sub_glyph),.valid(sub_ready),.page_id(subtitle_id),.length(sub_length));
    s4_osd #(.FRAME_FADE(1),.CLEAN_UI(1),.VIDEO_INFO(1)) u_osd(.clk(pixel_clk),.rst(video_reset),.frame_start(frame_start),.valid(va),.user(vu),.last(vl),.rgb(vrgb),.x(vx),.y(vy),.page_id(video_id),.token(video_token),.source_width(video_sw),.source_height(video_sh),.frame_fade_level(fade_level),
        .menu(p_menu),.selection(p_selection),.volume(p_volume),.brightness(p_brightness),.contrast(p_contrast),.transition(p_transition),.view(p_view),.stage(stage),
        .show_header(controls_pixel[0]),.show_analysis(controls_pixel[1]),.show_subtitle(controls_pixel[2]&&!video_showcase&&video_slot<5&&!music_active),.period_setting(controls_pixel[5:3]),
        .video_mode(video_slot>=5),.video_ready(manual_end_hold),
        .wave_range(wave_range),.light_ui(controls_pixel[36]),
        .music_active(music_active),.content_finished(content_finished),.full_demo(controls_pixel[37]),
        .page_loading(controls_pixel[39]),.pending_page(controls_pixel[42:40]),
        .video_wait(!content_finished&&((video_showcase&&consumed_samples==0)||(prepare_video&&!music_active&&!video_showcase))),
        .low_frequency(p_low),.freeze(p_freeze),.zero_trigger(p_trigger),.paused(p_paused),.auto_play(p_auto),.test_tone(p_tone),.color_bars(p_bars),.cache_ready(controls_pixel[7:6]),
        .subtitle_valid(sub_ready),.subtitle_id(subtitle_id),.subtitle_length(sub_length),.subtitle_address(sub_address),.subtitle_glyph(sub_glyph),
        .wave_address(wave_address),.wave_value(wave_value),.spectrum_address(spectrum_address),.spectrum_value(spectrum_value),.out_valid(axis_valid),.out_user(axis_user),.out_last(axis_last),.out_rgb(axis_data));
    wire port_ready,port_done,port_fault,client_busy,core_init,core_refresh,core_busy,refresh_req,refresh_block,refresh_fault;
    wire rd_en,raw_valid,aligned_valid;wire [20:0] app_addr;wire [31:0] app_data,raw_data,aligned_data,refresh_requests,refresh_acks;
    reg owner_write;
    assign display_ready=port_ready&&display_priority;assign writer_ready=port_ready&&!display_priority;
    assign display_done=port_done&&!owner_write;assign writer_done=port_done&&owner_write;
    always @(posedge mem_clk)begin if(mem_reset)owner_write<=0;else if(port_ready&&(display_cmd||(writer_cmd&&!display_priority)))owner_write<=!display_priority;end
    // 显示读取和素材写入共享内存端口，刷新期间禁止新事务。
    s3_mem_port u_port(.clk(mem_clk),.rst(mem_reset),.init_done(core_init),.refresh_block(refresh_block),.core_busy(core_busy),
        .cmd_valid(display_cmd||(writer_cmd&&!display_priority)),.cmd_write(!display_priority),.cmd_addr(display_priority?display_addr:writer_addr),.cmd_words(display_priority?display_words:writer_words),
        .cmd_ready(port_ready),.done(port_done),.fault(port_fault),.write_index(write_index),.write_data(write_data),.read_valid(read_valid),.read_index(read_index),.read_data(read_data),
        .client_busy(client_busy),.app_wr_en(wr_en),.app_rd_en(rd_en),.app_addr(app_addr),.app_data(app_data),.core_rd_valid(aligned_valid),.core_rd_data(aligned_data));
    stage2_sdram_core u_sdram(.clk(mem_clk),.clk_sft(mem_clk_sft),.rst(mem_reset),.app_ref_req(refresh_req),.sdr_init_done(core_init),.sdr_init_ref_vld(core_refresh),.sdr_busy(core_busy),
        .app_wr_en(wr_en),.app_wr_addr(app_addr),.app_wr_dm(4'b0),.app_wr_din(app_data),.app_rd_en(rd_en),.app_rd_addr(app_addr),.sdr_rd_en(raw_valid),.sdr_rd_dout(raw_data));
    stage2_sdram_read_align u_align(.clk(mem_clk),.rst(mem_reset),.raw_valid(raw_valid),.raw_data(raw_data),.aligned_valid(aligned_valid),.aligned_data(aligned_data));
    stage2_sdram_refresh_mgr #(.REFRESH_PERIOD_CYCLES(1562),.REFRESH_MARGIN_CYCLES(160)) u_refresh(.clk(mem_clk),.rst(mem_reset),.init_done(core_init),.refresh_valid(core_refresh),.sdr_busy(core_busy),.client_busy(client_busy),
        .app_ref_req(refresh_req),.block_requests(refresh_block),.refresh_fault(refresh_fault),.request_count(refresh_requests),.ack_count(refresh_acks));
    // 正式版只跨域传递锁存故障位，完整遥测按参数选用。
    reg [3:0] pixel_fault_sticky,pixel_fault_sync1,pixel_fault_sync2;
    always @(posedge pixel_clk)begin
        if(video_reset)pixel_fault_sticky<=0;
        else pixel_fault_sticky<=pixel_fault_sticky|{analysis_error!=0,pcm_underflow_seen,video_underflow_seen,video_fault};
    end
    always @(posedge mem_clk)begin
        if(mem_reset)begin pixel_fault_sync1<=0;pixel_fault_sync2<=0;end
        else begin pixel_fault_sync1<=pixel_fault_sticky;pixel_fault_sync2<=pixel_fault_sync1;end
    end
    generate if(FULL_DIAGNOSTICS!=0)begin:gen_debug
    wire diag_pulse;
    s3_button u_diag_button(.clk(mem_clk),.rst(mem_reset),.key_n(key_next_n|key_diag_n),.pulse(diag_pulse));
    reg [31:0] mem_read_words,mem_write_words,mem_first_address,mem_first_data;reg mem_saved;
    always @(posedge mem_clk)begin
        if(mem_reset)begin mem_read_words<=0;mem_write_words<=0;mem_first_address<=0;mem_first_data<=0;mem_saved<=0;end
        else begin
            if(read_valid&&mem_read_words!=32'hffffffff)mem_read_words<=mem_read_words+1'b1;
            if(wr_en&&mem_write_words!=32'hffffffff)mem_write_words<=mem_write_words+1'b1;
            if(!mem_saved&&(port_fault||refresh_fault))begin mem_saved<=1;mem_first_address<={11'b0,app_addr};mem_first_data<=app_data;end
        end
    end
    wire [31:0] hdmi_audio,hdmi_nonzero,hdmi_acr,hdmi_avi,hdmi_errors,hdmi_infoframes;wire [19:0] hdmi_cts,hdmi_n;wire [7:0] hdmi_first_error;
    s4_hdmi_monitor u_hdmi_monitor(.clk(pixel_clk),.reset(video_reset),.channel0(tmds0),.channel1(tmds1),.channel2(tmds2),
        .audio_packet_count(hdmi_audio),.nonzero_audio_count(hdmi_nonzero),.acr_packet_count(hdmi_acr),.avi_packet_count(hdmi_avi),.decode_error_count(hdmi_errors),.last_cts(hdmi_cts),.last_n(hdmi_n),
        .audio_infoframe_count(hdmi_infoframes),.first_error(hdmi_first_error));
    wire [31:0] pixel_word,diag_underflows,diag_pcm_underflows,diag_flags;wire [4:0] pixel_index;
    wire [15:0] subtitle_identity={4'b0,subtitle_id,sub_ready,sub_length,1'b0};
    wire [639:0] pixel_records={frames,hdmi_infoframes,startup_wait,
        {subtitle_identity,8'b0,1'b0,stage,2'b0,pcm_mode},{12'b0,hdmi_cts},{12'b0,hdmi_n},hdmi_errors,hdmi_avi,hdmi_acr,hdmi_nonzero,hdmi_audio,
        analysis_blocks,stage_samples,{active_token,3'b0,read_level},{19'b0,pcm_low},consumed_nonzero,consumed_samples,
        {hdmi_first_error,analysis_error,15'b0,video_fault},pcm_underflows,underflows};
    s4_telemetry u_telemetry(.pixel_clk(pixel_clk),.pixel_rst(video_reset),.records(pixel_records),.mem_clk(mem_clk),.mem_rst(mem_reset),.index(pixel_index),
        .value(pixel_word),.underflows(diag_underflows),.pcm_underflows(diag_pcm_underflows),.flags(diag_flags));
    wire [3:0] image_count={3'b0,bmp_mask[0]}+bmp_mask[1]+bmp_mask[2]+bmp_mask[3]+bmp_mask[4]+bmp_mask[5]+bmp_mask[6]+bmp_mask[7];
    s4_diag u_diag(.clk(mem_clk),.rst(mem_reset),.next_page(diag_pulse),.sd_error(sd_error),.fat_error(fat_error!=0?fat_error:file_error),.image_error(first_media_error!=0?first_media_error:image_error),.wav_error(wav_error),.sub_error(sub_error),
        .mem_fault(port_fault),.refresh_fault(refresh_fault),.video_fault(diag_flags[0]),.image_count(image_count),.displayed_id(displayed_id),.display_valid(display_valid),.auto_play(auto_play),
        .sectors(sectors),.bytes(fs_offset),.decoded(decoded),.written(written),.underflows(diag_underflows),.commits(commits),.lba(sd_lba),
        .source_width(source_width),.source_height(source_height),.load_ms(load_ms),.response_ms(response_ms),.valid_slots(valid_slots),.protected_slots(protected_slots),.tags(tags),
        .hits(hits),.misses(misses),.cancels(cancels),.token_cycles(token_cycles),.transfer_cycles(transfer_cycles),.drain_cycles(drain_cycles),.stall_cycles(sd_stalls),.fat_sectors(fat_sectors),.fat_hits(fat_hits),.scan_cycles(scan_cycles),
        .refresh_requests(refresh_requests),.refresh_acks(refresh_acks),.pcm_enqueued(enqueued),.pcm_consumed(32'b0),.pcm_nonzero(32'b0),.pcm_underflows(diag_pcm_underflows),
        .pcm_level(pcm_level),.pcm_high(pcm_high),.pcm_low(13'b0),.active_token(16'b0),.pcm_mode(3'b0),.stage(2'b0),
        .stage_samples(32'b0),.analysis_blocks(32'b0),.hdmi_audio(32'b0),.hdmi_nonzero(32'b0),.hdmi_acr(32'b0),
        .hdmi_avi(32'b0),.hdmi_errors(32'b0),.n(20'b0),.cts(20'b0),.analysis_error(diag_flags[23:16]),.subtitle_identity(16'b0),
        .generated(generated),.scale_stalls(scale_stalls),.current_cluster(current_cluster),.enqueued_nonzero(enqueued_nonzero),.startup_wait(32'b0),
        .wav_samples(wav_samples),.wav_nonzero(wav_nonzero),.image_sectors(image_sectors),.audio_sectors(audio_sectors),.audio_wait(audio_wait),
        .mem_read_words(mem_read_words),.mem_write_words(mem_write_words),.mem_first_address(mem_first_address),.mem_first_data(mem_first_data),.hdmi_infoframes(32'b0),
        .identity_status({media_first_file_error,diag_flags[31:24],8'b0,4'b0,av_lock,mem_lock,video_lock_sync[1],core_init}),.pixel_word(pixel_word),.pixel_index(pixel_index),
        .debug_job({load_epoch,3'b0,load_slot,load_id,requested_id,front_slot,load_cancel}),
        .seg_sel(seg_sel),.seg_data(seg_data));
    end else begin:gen_show
        s4_mini_diag u_status(.clk(mem_clk),.rst(mem_reset),.display_valid(display_valid),.displayed_id(displayed_id),
            .sd_error(sd_error),.file_error(fat_error!=0?fat_error:media_first_file_error!=0?media_first_file_error:response_kind==3?8'b0:file_error),.movie_error(commit_showcase&&!music_available?8'hd8:movie_error),
            .image_error(first_media_error!=0?first_media_error:image_error),.wav_error(wav_error),.sub_error(sub_error),
            .mem_fault(port_fault),.refresh_fault(refresh_fault),.pixel_faults(pixel_fault_sync2),.seg_sel(seg_sel),.seg_data(seg_data));
    end endgenerate
endmodule

