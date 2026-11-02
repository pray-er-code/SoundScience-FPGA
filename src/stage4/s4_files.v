`timescale 1ns/1ps

// FAT32 多媒体目录与文件上下文
module s4_files(
    input clk,rst,card_ready,input [7:0] card_error,
    output reg sd_req,output reg [31:0] sd_lba,input sd_ready,
    input sd_valid,input [7:0] sd_data,output sd_take,input sd_done,
    output reg mounted,catalog_done,output reg [7:0] bmp_mask,wav_mask,sub_mask,vid_mask,output reg music_available,
    input request,input [1:0] request_kind,input [2:0] request_id,input reopen,request_music,
    output ready,output reg response_start,response_done,
    output [1:0] response_kind,output [2:0] response_id,
    output byte_valid,output [7:0] byte_data,input byte_take,output byte_last,
    output reg [31:0] file_size,file_offset,output reg [7:0] error_code,file_error,
    output reg [31:0] sectors_data,sectors_fat,fat_hits,scan_cycles,io_cycles,
    output [31:0] current_cluster
);
    // 图片、音频、字幕、视频分别保存读取进度，每次调度最多读取一个数据扇区。
    localparam WAIT=0,REQ=1,RX=2,PROCESS=3,IDLE=4,SELECT=5,LOOK_PRE=6,LOOK=7,ERROR=8;
    localparam BPB=0,DIR=1,FAT=2,DATA=3;
    reg [4:0] state;reg [1:0] purpose,chain_purpose,client;
    reg [2:0] selected_id;reg opening,audio_ctx_music;
    reg [9:0] pos;reg [255:0] entry;
    reg [31:0] partition,fat_start,data_start,total_sectors,fat_sectors,root;
    reg [15:0] bps,reserved,signature;reg [7:0] spc,nfats;reg [2:0] spc_shift;
    reg [31:0] cluster,chain,walk_count;reg [7:0] sector_in_cluster;
    reg [31:0] fat_span,capacity_after_reserved,capacity_sum,cluster_limit;
    wire [63:0] descriptor_data;
    reg [31:0] ctx_cluster[0:3],ctx_offset[0:3],ctx_size[0:3],ctx_walk[0:3];
    reg [7:0] ctx_sector[0:3];reg [2:0] ctx_id[0:3];reg [3:0] ctx_valid,ctx_need_chain;
    reg [31:0] chosen_partition,mbr_lba;reg [7:0] partition_type;
    reg have_partition,partition_used,dir_end;
    reg [31:0] fat_tag;reg fat_valid;reg [1:0] lookup_byte;
    wire [8:0] fat_address={cluster[6:0],2'b0}+lookup_byte;
    wire [7:0] cached_fat;
    wire [3:0] mbr_offset=pos[3:0]+4'd2;
    wire accept=sd_valid && sd_take;
    wire music_request=request_kind==1&&request_music;
    wire [5:0] descriptor_index=music_request?6'd32:{1'b0,request_kind,request_id};
    wire [7:0] present_mask=(request_kind==0)?bmp_mask:(request_kind==1)?wav_mask:request_kind==2?sub_mask:vid_mask;
    wire [7:0] name0=entry[7:0],name1=entry[15:8];
    wire numbered=name0==8'h30 && name1>=8'h31 && name1<=8'h38 && entry[63:16]==48'h202020202020;
    wire [2:0] entry_id=name1-8'h31;
    wire bmp_ext=entry[87:64]==24'h504d42;
    wire wav_ext=entry[87:64]==24'h564157;
    wire music_name=entry[63:0]==64'h202020434953554d&&wav_ext;
    wire sub_ext=entry[87:64]==24'h425553;
    wire vid_ext=entry[87:64]==24'h444956;
    wire [1:0] entry_kind=bmp_ext?0:wav_ext?1:sub_ext?2:3;
    wire [31:0] entry_cluster={4'b0,entry[171:160],entry[223:208]};
    wire entry_present=music_name?music_available:((entry_kind==0?bmp_mask:entry_kind==1?wav_mask:entry_kind==2?sub_mask:vid_mask)&(8'b1<<entry_id))!=0;
    wire store_descriptor=state==RX&&purpose==DIR&&accept&&pos[4:0]==31&&!dir_end&&entry[7:0]!=8'he5&&
        (entry[95:88]&8'h18)==0&&entry[95:88]!=8'h0f&&(numbered||music_name)&&(bmp_ext||wav_ext||sub_ext||vid_ext)&&entry_cluster>=2&&!entry_present;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(64),.DATA_WIDTH_B(64),.ADDR_WIDTH_A(6),.ADDR_WIDTH_B(6),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) descriptors(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(store_descriptor),.addra(music_name?6'd32:{1'b0,entry_kind,entry_id}),.dia({{sd_data,entry[247:224]},entry_cluster}),.rsta(1'b0),.bea(1'b1),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(descriptor_index),.dib(64'b0),.rstb(1'b0),.beb(1'b1),.dob(descriptor_data));
    assign ready=state==IDLE && catalog_done && error_code==0;
    assign response_kind=client;assign response_id=selected_id;
    assign byte_valid=state==RX && purpose==DATA && sd_valid && file_offset<file_size;
    assign byte_data=sd_data;assign byte_last=byte_valid && file_offset==file_size-1;
    assign sd_take=state==RX && (purpose!=DATA || file_offset>=file_size || byte_take);
    assign current_cluster=cluster;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) u_fat_cache(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(state==RX&&purpose==FAT&&accept),.addra(pos[8:0]),.dia(sd_data),.rsta(1'b0),.bea(1'b1),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(fat_address),.dib(8'b0),.rstb(1'b0),.beb(1'b1),.dob(cached_fat));
    function valid_cluster;input [31:0] c;begin
        valid_cluster=c>=2 && c<32'h0ffffff0 && c-2<cluster_limit;
    end endfunction
    task sector;input [31:0] lba;input [1:0] kind;begin
        sd_req<=1;sd_lba<=lba;purpose<=kind;state<=REQ;pos<=0;signature<=0;entry<=0;dir_end<=0;
    end endtask
    task fault;input [7:0] code;begin
        sd_req<=0;
        if(catalog_done)begin file_error<=code;response_done<=1;state<=IDLE;ctx_valid[client]<=0;end
        else begin error_code<=code;state<=ERROR;end
    end endtask
    task follow;input [1:0] destination;begin
        chain_purpose<=destination;chain<=0;lookup_byte<=0;
        if(fat_valid && fat_tag==(cluster>>7))begin
            if(fat_hits!=32'hffffffff)fat_hits<=fat_hits+1'b1;state<=LOOK_PRE;
        end else begin fat_valid<=0;sector(fat_start+(cluster>>7),FAT);end
    end endtask
    integer i;
    always @(posedge clk)begin
        if(rst)begin
            state<=WAIT;purpose<=0;chain_purpose<=0;client<=0;selected_id<=0;opening<=0;sd_req<=0;sd_lba<=0;
            mounted<=0;catalog_done<=0;bmp_mask<=0;wav_mask<=0;sub_mask<=0;vid_mask<=0;music_available<=0;audio_ctx_music<=0;error_code<=0;file_error<=0;
            response_start<=0;response_done<=0;file_size<=0;file_offset<=0;pos<=0;entry<=0;
            partition<=0;fat_start<=0;data_start<=0;total_sectors<=0;fat_sectors<=0;root<=0;
            fat_span<=0;capacity_after_reserved<=0;capacity_sum<=0;cluster_limit<=0;
            bps<=0;reserved<=0;signature<=0;spc<=1;spc_shift<=0;nfats<=0;cluster<=0;chain<=0;walk_count<=0;sector_in_cluster<=0;
            chosen_partition<=0;mbr_lba<=0;partition_type<=0;have_partition<=0;partition_used<=0;dir_end<=0;
            fat_tag<=0;fat_valid<=0;lookup_byte<=0;ctx_valid<=0;ctx_need_chain<=0;
            sectors_data<=0;sectors_fat<=0;fat_hits<=0;scan_cycles<=0;io_cycles<=0;
            for(i=0;i<4;i=i+1)begin ctx_cluster[i]<=0;ctx_offset[i]<=0;ctx_size[i]<=0;ctx_walk[i]<=0;ctx_sector[i]<=0;ctx_id[i]<=0;end
        end else begin
            response_start<=0;response_done<=0;
            if(!catalog_done && scan_cycles!=32'hffffffff)scan_cycles<=scan_cycles+1'b1;
            if(catalog_done && state!=IDLE && io_cycles!=32'hffffffff)io_cycles<=io_cycles+1'b1;
            if(card_error!=0)begin error_code<=8'h10;state<=ERROR;sd_req<=0;end
            else case(state)
                WAIT:if(card_ready)sector(0,BPB);
                REQ:if(sd_req&&sd_ready)begin sd_req<=0;state<=RX;end
                RX:begin
                    if(accept)begin
                        pos<=pos+1'b1;
                        if(pos==510)signature[7:0]<=sd_data;if(pos==511)signature[15:8]<=sd_data;
                        if(purpose==BPB)begin
                            case(pos)
                                11:bps[7:0]<=sd_data;12:bps[15:8]<=sd_data;13:spc<=sd_data;
                                14:reserved[7:0]<=sd_data;15:reserved[15:8]<=sd_data;16:nfats<=sd_data;
                                32:total_sectors[7:0]<=sd_data;33:total_sectors[15:8]<=sd_data;34:total_sectors[23:16]<=sd_data;35:total_sectors[31:24]<=sd_data;
                                36:fat_sectors[7:0]<=sd_data;37:fat_sectors[15:8]<=sd_data;38:fat_sectors[23:16]<=sd_data;39:fat_sectors[31:24]<=sd_data;
                                44:root[7:0]<=sd_data;45:root[15:8]<=sd_data;46:root[23:16]<=sd_data;47:root[31:24]<=sd_data;
                            endcase
                            if(pos>=446 && pos<510)begin
                                case(mbr_offset)
                                    4:partition_type<=sd_data;8:mbr_lba[7:0]<=sd_data;9:mbr_lba[15:8]<=sd_data;
                                    10:mbr_lba[23:16]<=sd_data;
                                    11:if(!have_partition && (partition_type==11 || partition_type==12))begin
                                        chosen_partition<={sd_data,mbr_lba[23:0]};have_partition<=1;
                                    end
                                endcase
                            end
                        end else if(purpose==DIR)begin
                            entry[pos[4:0]*8+:8]<=sd_data;
                            if(pos[4:0]==0 && sd_data==0)dir_end<=1;
                            if(pos[4:0]==31 && !dir_end && entry[7:0]!=8'he5 &&
                                (entry[95:88]&8'h18)==0 && entry[95:88]!=8'h0f && (numbered||music_name) &&
                                (bmp_ext||wav_ext||sub_ext||vid_ext) && entry_cluster>=2)begin
                                // 重复编号同类型文件只采用第一个。
                                if(!entry_present)begin
                                    if(music_name)music_available<=1;
                                    else
                                    if(bmp_ext)bmp_mask[entry_id]<=1;else if(wav_ext)wav_mask[entry_id]<=1;else if(sub_ext)sub_mask[entry_id]<=1;else vid_mask[entry_id]<=1;
                                end
                            end
                        end else if(purpose==DATA && file_offset<file_size)file_offset<=file_offset+1'b1;
                    end
                    if(sd_done)state<=PROCESS;
                end
                PROCESS:case(purpose)
                    BPB:if(signature!=16'haa55)fault(8'h21);
                        else if(bps==512 && spc!=0 && (spc&(spc-1))==0 && spc<=128 && reserved!=0 &&
                            nfats>=1 && nfats<=2 && fat_sectors!=0 && root>=2 && total_sectors>reserved)begin
                            fat_start<=partition+reserved;
                            case(spc)1:spc_shift<=0;2:spc_shift<=1;4:spc_shift<=2;8:spc_shift<=3;
                                16:spc_shift<=4;32:spc_shift<=5;64:spc_shift<=6;128:spc_shift<=7;endcase
                            cluster<=root;sector_in_cluster<=0;walk_count<=0;state<=12;
                        end else if(!partition_used && have_partition && chosen_partition!=0)begin
                            partition<=chosen_partition;partition_used<=1;sector(chosen_partition,BPB);
                        end else fault(8'h22);
                    DIR:if(dir_end)begin catalog_done<=1;state<=IDLE;end
                        else if(sector_in_cluster+1<spc)begin sector_in_cluster<=sector_in_cluster+1'b1;sector(sd_lba+1,DIR);end
                        else follow(DIR);
                    FAT:begin
                        if(sectors_fat!=32'hffffffff)sectors_fat<=sectors_fat+1'b1;
                        fat_tag<=cluster>>7;fat_valid<=1;lookup_byte<=0;chain<=0;state<=LOOK_PRE;
                    end
                    DATA:begin
                        ctx_cluster[client]<=cluster;ctx_offset[client]<=file_offset;ctx_walk[client]<=walk_count;
                        if(sector_in_cluster+1>=spc)begin ctx_sector[client]<=0;ctx_need_chain[client]<=1;end
                        else begin ctx_sector[client]<=sector_in_cluster+1'b1;ctx_need_chain[client]<=0;end
                        if(sectors_data!=32'hffffffff)sectors_data<=sectors_data+1'b1;
                        response_done<=1;state<=IDLE;
                    end
                endcase
                IDLE:if(request && ready)begin
                    client<=request_kind;selected_id<=request_id;file_error<=0;opening<=reopen;state<=SELECT;
                    if(request_kind==1)audio_ctx_music<=music_request;
                    if(music_request?!music_available:!present_mask[request_id])begin
                        ctx_valid[request_kind]<=0;
                        file_error<=8'h25;response_start<=1;response_done<=1;state<=IDLE;file_size<=0;file_offset<=0;
                    end else if(reopen || !ctx_valid[request_kind] || ctx_id[request_kind]!=request_id || (request_kind==1&&audio_ctx_music!=music_request))begin
                        state<=11;
                    end
                end
                11:begin
                    ctx_id[client]<=selected_id;ctx_valid[client]<=1;ctx_need_chain[client]<=0;
                    ctx_size[client]<=descriptor_data[63:32];ctx_offset[client]<=0;
                    ctx_cluster[client]<=descriptor_data[31:0];ctx_sector[client]<=0;ctx_walk[client]<=0;state<=SELECT;
                end
                12:begin fat_span<=nfats==2?(fat_sectors<<1):fat_sectors;capacity_after_reserved<=total_sectors-reserved;state<=13;end
                13:begin data_start<=fat_start+fat_span;capacity_sum<=capacity_after_reserved-fat_span;state<=14;end
                14:if(capacity_after_reserved<=fat_span)fault(8'h22);else begin cluster_limit<=capacity_sum>>spc_shift;state<=15;end
                15:begin mounted<=1;sector(data_start+((root-2)<<spc_shift),DIR);end
                SELECT:begin
                    file_size<=ctx_size[client];file_offset<=ctx_offset[client];cluster<=ctx_cluster[client];
                    sector_in_cluster<=ctx_sector[client];walk_count<=ctx_walk[client];response_start<=1;
                    if(ctx_offset[client]>=ctx_size[client])begin response_done<=1;state<=IDLE;end
                    else if(ctx_need_chain[client])begin chain_purpose<=DATA;state<=LOOK_PRE;lookup_byte<=0;chain<=0;
                        // 先恢复文件上下文，再查找簇链。
                        state<=9;
                    end else sector(data_start+((ctx_cluster[client]-2)<<spc_shift)+ctx_sector[client],DATA);
                end
                9:follow(DATA);
                LOOK_PRE:state<=LOOK;
                LOOK:begin
                    case(lookup_byte)
                        0:chain[7:0]<=cached_fat;1:chain[15:8]<=cached_fat;2:chain[23:16]<=cached_fat;
                        3:chain[31:24]<={4'b0,cached_fat[3:0]};
                    endcase
                    if(lookup_byte==3)state<=10;
                    else begin lookup_byte<=lookup_byte+1'b1;state<=LOOK_PRE;end
                end
                10:if(chain>=32'h0ffffff8 && chain_purpose==DIR)begin catalog_done<=1;state<=IDLE;end
                    else if(chain==cluster || walk_count>=1048576)fault(8'h23);
                    else if(!valid_cluster(chain))fault(8'h24);
                    else state<=16;
                16:begin cluster<=chain;sector_in_cluster<=0;walk_count<=walk_count+1'b1;sector(data_start+((chain-2)<<spc_shift),chain_purpose);end
                ERROR:sd_req<=0;
                default:fault(8'hff);
            endcase
        end
    end
endmodule
