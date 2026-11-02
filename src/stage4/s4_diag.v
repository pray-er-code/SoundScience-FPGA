`timescale 1ns/1ps

// 完整分页诊断数码管
module s4_diag(input clk,rst,next_page,input [7:0] sd_error,fat_error,image_error,wav_error,sub_error,
    input mem_fault,refresh_fault,video_fault,input [3:0] image_count,input [2:0] displayed_id,
    input display_valid,auto_play,input [31:0] sectors,bytes,decoded,written,underflows,commits,lba,
    input [15:0] source_width,source_height,load_ms,response_ms,input [4:0] valid_slots,protected_slots,input [14:0] tags,
    input [31:0] hits,misses,cancels,token_cycles,transfer_cycles,drain_cycles,stall_cycles,fat_sectors,fat_hits,scan_cycles,
    input [31:0] refresh_requests,refresh_acks,pcm_enqueued,pcm_consumed,pcm_nonzero,pcm_underflows,
    input [12:0] pcm_level,pcm_high,pcm_low,input [15:0] active_token,input [2:0] pcm_mode,input [1:0] stage,
    input [31:0] stage_samples,analysis_blocks,hdmi_audio,hdmi_nonzero,hdmi_acr,hdmi_avi,hdmi_errors,
    input [19:0] n,cts,input [7:0] analysis_error,input [15:0] subtitle_identity,
    input [31:0] generated,scale_stalls,current_cluster,enqueued_nonzero,startup_wait,wav_samples,wav_nonzero,
    input [31:0] image_sectors,audio_sectors,audio_wait,mem_read_words,mem_write_words,mem_first_address,mem_first_data,hdmi_infoframes,
    input [31:0] identity_status,
    input [31:0] pixel_word,debug_job,output reg [4:0] pixel_index,
    output reg [5:0] seg_sel,output reg [7:0] seg_data
);
    reg [6:0] page;reg [15:0] snapshot;reg [23:0] value;reg [15:0] page_value;
    reg [15:0] scan;reg [2:0] digit;reg saved;
    reg [7:0] first_sd,first_fat,first_image,first_wav,first_sub;reg [3:0] first_flags;
    reg [31:0] first_lba,first_bytes,first_decoded,first_written,first_sectors;
    reg [15:0] first_w,first_h;
    wire [31:0] showbytes=saved?first_bytes:bytes,showdecoded=saved?first_decoded:decoded,showwritten=saved?first_written:written;
    // 先选高低半字再选诊断页，减少宽位选择器。
    reg [15:0] extended;reg [6:0] next;
    wire [6:0] pair_offset=next-7'd19;
    function [15:0] half;input [31:0] word;input low_half;begin
        half=low_half?word[15:0]:word[31:16];
    end endfunction
    always @*begin
        next=page==127?0:page+1'b1;extended=0;pixel_index=0;
        case(pair_offset[6:1])
            0:extended=half(hits,next[0]);1:extended=half(misses,next[0]);2:extended=half(cancels,next[0]);3:extended=half(token_cycles,next[0]);4:extended=half(transfer_cycles,next[0]);
            5:extended=half(drain_cycles,next[0]);6:extended=half(stall_cycles,next[0]);7:extended=half(fat_sectors,next[0]);8:extended=half(fat_hits,next[0]);9:extended=half(scan_cycles,next[0]);
            10:extended=half(refresh_requests,next[0]);11:extended=half(refresh_acks,next[0]);12:extended=half(pcm_enqueued,next[0]);13:extended=half(pcm_consumed,next[0]);
            14:extended=half(pcm_nonzero,next[0]);15:extended=half(pcm_underflows,next[0]);16:extended=half({3'b0,pcm_high,3'b0,pcm_low},next[0]);
            17:extended=half({active_token,3'b0,pcm_level},next[0]);18:extended=half(stage_samples,next[0]);19:extended=half(analysis_blocks,next[0]);
            20:extended=half(hdmi_audio,next[0]);21:extended=half(hdmi_nonzero,next[0]);22:extended=half(hdmi_acr,next[0]);23:extended=half(hdmi_avi,next[0]);24:extended=half(hdmi_errors,next[0]);
            25:extended=half({12'b0,n},next[0]);26:extended=half({12'b0,cts},next[0]);27:extended=half({8'b0,first_sub,first_wav,analysis_error},next[0]);
            28:extended=half({subtitle_identity,8'b0,1'b0,stage,2'b0,pcm_mode},next[0]);
            29:extended=half({7'b0,protected_slots,valid_slots,tags},next[0]);
            30:extended=half(generated,next[0]);31:extended=half(scale_stalls,next[0]);32:extended=half(current_cluster,next[0]);33:extended=half(enqueued_nonzero,next[0]);
            34:extended=half(startup_wait,next[0]);35:extended=half(wav_samples,next[0]);36:extended=half(wav_nonzero,next[0]);37:extended=half(image_sectors,next[0]);
            38:extended=half(audio_sectors,next[0]);39:extended=half(audio_wait,next[0]);40:extended=half(mem_read_words,next[0]);41:extended=half(mem_write_words,next[0]);
            42:extended=half(mem_first_address,next[0]);43:extended=half(mem_first_data,next[0]);44:extended=half(hdmi_infoframes,next[0]);45:extended=half(identity_status,next[0]);
            46:extended=half(debug_job,next[0]);
        endcase
        case(pair_offset[6:1])
            13:begin pixel_index=3;extended=half(pixel_word,next[0]);end
            14:begin pixel_index=4;extended=half(pixel_word,next[0]);end
            16:begin pixel_index=5;extended=half({3'b0,pcm_high,3'b0,pixel_word[12:0]},next[0]);end
            17:begin pixel_index=6;extended=half(pixel_word,next[0]);end
            18:begin pixel_index=7;extended=half(pixel_word,next[0]);end
            19:begin pixel_index=8;extended=half(pixel_word,next[0]);end
            20:begin pixel_index=9;extended=half(pixel_word,next[0]);end
            21:begin pixel_index=10;extended=half(pixel_word,next[0]);end
            22:begin pixel_index=11;extended=half(pixel_word,next[0]);end
            23:begin pixel_index=12;extended=half(pixel_word,next[0]);end
            24:begin pixel_index=13;extended=half(pixel_word,next[0]);end
            25:begin pixel_index=14;extended=half(pixel_word,next[0]);end
            26:begin pixel_index=15;extended=half(pixel_word,next[0]);end
            28:begin pixel_index=16;extended=half(pixel_word,next[0]);end
            34:begin pixel_index=17;extended=half(pixel_word,next[0]);end
            44:begin pixel_index=18;extended=half(pixel_word,next[0]);end
        endcase
        page_value=extended;
        case(next)
            0:page_value=0;1:page_value={first_sd,first_fat};2:page_value={first_image,4'b0,first_flags};
            3:page_value=saved?first_sectors[15:0]:sectors[15:0];4:page_value=showbytes[15:0];5:page_value=showbytes[31:16];
            6:page_value=showdecoded[15:0];7:page_value=showdecoded[31:16];8:page_value=showwritten[15:0];9:page_value=showwritten[31:16];
            10:page_value=underflows[15:0];11:page_value=commits[15:0];12:page_value=saved?first_lba[15:0]:lba[15:0];
            13:page_value=saved?first_w:source_width;14:page_value=saved?first_h:source_height;15:page_value=16'hf403;
            16:page_value=load_ms;17:page_value=response_ms;
            18:page_value={8'b0,(valid_slots&~protected_slots)!=0,3'd0,1'b0,tags[2:0]};
        endcase
        value={1'b0,page,snapshot};
        if(page==0)begin
            value={4'ha,image_count,4'b0,auto_play,display_valid,2'b0,displayed_id,5'b0};
            if(sd_error)value={8'he1,8'b0,sd_error};else if(fat_error)value={8'he2,8'b0,fat_error};
            else if(mem_fault||refresh_fault)value={8'he4,12'b0,2'b0,refresh_fault,mem_fault};
            else if(video_fault||underflows)value={8'he5,underflows[15:0]};else if(pcm_underflows)value={8'he6,pcm_underflows[15:0]};
        end
    end
    function [7:0] hex;input [3:0] n;begin case(n)
        0:hex=8'hc0;1:hex=8'hf9;2:hex=8'ha4;3:hex=8'hb0;4:hex=8'h99;5:hex=8'h92;6:hex=8'h82;7:hex=8'hf8;
        8:hex=8'h80;9:hex=8'h90;10:hex=8'h88;11:hex=8'h83;12:hex=8'hc6;13:hex=8'ha1;14:hex=8'h86;15:hex=8'h8e;
    endcase end endfunction
    always @(posedge clk)begin
        if(rst)begin page<=0;snapshot<=0;scan<=0;digit<=0;seg_sel<=63;seg_data<=255;saved<=0;
            first_sd<=0;first_fat<=0;first_image<=0;first_wav<=0;first_sub<=0;first_flags<=0;
            first_lba<=0;first_bytes<=0;first_decoded<=0;first_written<=0;first_sectors<=0;first_w<=0;first_h<=0;
        end else begin
            if(!saved&&(sd_error||fat_error||image_error||wav_error||sub_error||mem_fault||refresh_fault||video_fault||underflows||pcm_underflows||analysis_error))begin
                saved<=1;first_sd<=sd_error;first_fat<=fat_error;first_image<=image_error;first_wav<=wav_error;first_sub<=sub_error;
                first_flags<={underflows!=0,video_fault,refresh_fault,mem_fault};first_lba<=lba;first_bytes<=bytes;first_decoded<=decoded;first_written<=written;
                first_sectors<=sectors;first_w<=source_width;first_h<=source_height;
            end
            if(next_page)begin page<=next;snapshot<=page_value;end
            if(scan==41666)begin scan<=0;digit<=digit==5?0:digit+1'b1;seg_sel<=~(6'b1<<digit);
                case(digit)0:seg_data<=hex(value[23:20]);1:seg_data<=hex(value[19:16])&8'h7f;2:seg_data<=hex(value[15:12]);
                    3:seg_data<=hex(value[11:8]);4:seg_data<=hex(value[7:4]);5:seg_data<=hex(value[3:0]);endcase
            end else scan<=scan+1'b1;
        end
    end
endmodule
