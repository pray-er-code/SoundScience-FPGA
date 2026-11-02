create_clock -name clk_50m -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
derive_clocks
rename_clock -name pixel_clk -source [get_ports {clk}] -master_clock {clk_50m} [get_pins {u_av_pll/u_pll.clkc[0]}]
rename_clock -name serial_clk -source [get_ports {clk}] -master_clock {clk_50m} [get_pins {u_av_pll/u_pll.clkc[1]}]
rename_clock -name mem_clk -source [get_ports {clk}] -master_clock {clk_50m} [get_pins {u_mem_pll/u_pll.clkc[0]}]
rename_clock -name mem_clk_sft -source [get_ports {clk}] -master_clock {clk_50m} [get_pins {u_mem_pll/u_pll.clkc[1]}]
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {HDMI_DDC_SDA}]
set_false_path -from [get_ports {key_next_n}]
set_false_path -from [get_ports {key_auto_n}]
set_false_path -from [get_ports {key_diag_n}]
set_false_path -from [get_ports {switches[*]}]
# Only external MISO -> first synchronizer is asynchronous. Two stages precede
# the SPI sample; 6.25 MHz gives an 80 ns half-cycle for this latency.
set_false_path -from [get_ports {tf_miso}]
# Named control synchronizers and held request/ack mailboxes only.
set_false_path -from [get_regs {u_cache/request_*}] -to [get_regs {u_cache/req_s1*}]
set_false_path -from [get_regs {u_cache/request_*}] -to [get_regs {u_cache/fill_*}]
set_false_path -from [get_regs {u_cache/request_row*}] -to [get_pins {u_cache/mult*.a*}]
set_false_path -from [get_regs {u_cache/commit_ack*}] -to [get_regs {u_control/ack_sync*}]
set_false_path -from [get_regs {u_cache/commit_ack*}] -to [get_regs {visible_ack_sync*}]
set_false_path -from [get_regs {u_control/commit_*}] -to [get_regs {u_cache/commit_sync*}]
set_false_path -from [get_regs {u_control/commit_*}] -to [get_regs {u_cache/fit/*}]
set_false_path -from [get_regs {u_control/commit_*}] -to [get_regs {u_cache/current_*}]
set_false_path -from [get_regs {u_control/commit_*}] -to [get_regs {u_cache/source_*}]
set_false_path -from [get_regs {u_control/commit_*}] -to [get_regs {u_cache/w*}]
set_false_path -from [get_regs {u_control/commit_*}] -to [get_regs {u_cache/height*}]
set_false_path -from [get_regs {u_cache/ack_toggle*}] -to [get_regs {u_cache/ack_s1*}]
set_false_path -from [get_regs {controls_mem*}] -to [get_regs {controls_s1*}]
# controls_mem is a wire; actual control registers are the source.
set_false_path -from [get_regs {u_controls/*}] -to [get_regs {controls_s1*}]
# C03 cache readiness is observational only, crossing into the first stage
# of the same two-flop/frame-latched UI snapshot. It never controls playback
# or buffer ownership. Do not cut any functional controller/video path.
set_false_path -from [get_regs {u_control/*}] -to [get_regs {controls_s1*}]
set_false_path -from [get_regs {u_controls/paused*}] -to [get_regs {u_player/pause_sync*}]
set_false_path -from [get_regs {u_controls/test_tone*}] -to [get_regs {u_player/pause_sync*}]
set_false_path -from [get_regs {u_controls/volume*}] -to [get_regs {u_player/vol_s1*}]
set_false_path -from [get_regs {u_player/wr_gray*}] -to [get_regs {u_player/wr_g1*}]
set_false_path -from [get_regs {u_player/rd_gray*}] -to [get_regs {u_player/rd_g1*}]
set_false_path -from [get_regs {u_player/flush_req*}] -to [get_regs {u_player/req_sync*}]
set_false_path -from [get_regs {u_player/flush_ack*}] -to [get_regs {u_player/ack_sync*}]
set_false_path -from [get_regs {u_player/token_mail*}] -to [get_regs {u_player/active_token*}]
set_false_path -from [get_regs {u_media/pcm_eof*}] -to [get_regs {u_player/eof_sync*}]
set_false_path -from [get_regs {u_sub/publish*}] -to [get_regs {u_sub/publish_sync*}]
set_false_path -from [get_regs {u_sub/start_toggle*}] -to [get_regs {u_sub/start_sync*}]
set_false_path -from [get_regs {u_sub/id_mail*}] -to [get_regs {u_sub/page_id*}]
set_false_path -from [get_regs {u_sub/length_mail*}] -to [get_regs {u_sub/length*}]
set_false_path -from [get_regs {u_telemetry/published*}] -to [get_regs {u_telemetry/ready_sync*}]
set_false_path -from [get_regs {u_telemetry/acknowledged*}] -to [get_regs {u_telemetry/ack_sync*}]
set_false_path -from [get_regs {u_hdmi_core/*O_video_locked*}] -to [get_regs {video_lock_sync*}]

# C12 added monotonic single-bit diagnostic fault synchronizers. Only the
# asynchronous first stage is cut; sync1 -> sync2 and status logic stay timed.
set_false_path -from [get_regs {pixel_fault_sticky*}] -to [get_regs {pixel_fault_sync1*}]
# Stable switch settings join the existing first-stage/frame-latched UI
# snapshot; never cut controls_s1 -> controls_s2 or the display pipeline.
set_false_path -from [get_regs {u_switches/value*}] -to [get_regs {controls_s1*}]
# Full diagnostics is compile-time optional and now has a named generate scope.
set_false_path -from [get_regs {gen_debug/u_telemetry/published*}] -to [get_regs {gen_debug/u_telemetry/ready_sync*}]
set_false_path -from [get_regs {gen_debug/u_telemetry/acknowledged*}] -to [get_regs {gen_debug/u_telemetry/ack_sync*}]
# C15 coherent content-status mailbox: held bus is captured only after the
# request synchronizer plus two settle clocks, then ack returns before reuse.
set_false_path -from [get_regs {u_playback/mailbox/published*}] -to [get_regs {u_playback/mailbox/request_sync*}]
set_false_path -from [get_regs {u_playback/mailbox/acknowledged*}] -to [get_regs {u_playback/mailbox/ack_sync*}]
set_false_path -from [get_regs {u_playback/mailbox/held*}] -to [get_regs {u_playback/mailbox/dest_data*}]
# C15 precomputed clamp boundaries are part of the SAME held commit geometry
# as w/height. They are latched only after commit_sync and fit_done in blanking.
# Limit this exception to mem-clock launch -> these20 boundary capture flops;
# their pixel-clock fanout and all pixel data/read paths remain timed.
set_false_path -from [get_clocks mem_clk] -to [get_regs {u_cache/last_column* u_cache/last_row*}]
# C16 all display commits use one held request/ack geometry mailbox; frame
# epoch is separate from audio content token. Capture occurs after fit_done.
set_false_path -from [get_regs {u_display/commit_*}] -to [get_regs {u_cache/commit_sync*}]
set_false_path -from [get_regs {u_display/commit_*}] -to [get_regs {u_cache/fit/*}]
set_false_path -from [get_regs {u_display/commit_*}] -to [get_regs {u_cache/current_*}]
set_false_path -from [get_regs {u_display/commit_*}] -to [get_regs {u_cache/source_*}]
set_false_path -from [get_regs {u_display/commit_*}] -to [get_regs {u_cache/w* u_cache/height*}]
set_false_path -from [get_regs {u_cache/commit_ack*}] -to [get_regs {u_display/ack_sync*}]

# C19 new registered startup-pause source joins the existing two-flop pause
# synchronizer. Only this asynchronous source-to-first-stage path is cut;
# pause_sync[0] -> pause_sync[1] and all PCM/data paths remain timed.
set_false_path -from [get_regs {manual_start_hold*}] -to [get_regs {u_player/pause_sync*}]

