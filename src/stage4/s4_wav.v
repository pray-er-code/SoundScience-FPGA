`timescale 1ns/1ps

// WAV 格式解析与 PCM 拆包
module s4_wav(
    input clk,rst,start,cancel,input [31:0] file_size,
    input byte_valid,input [7:0] byte_data,output byte_ready,input byte_last,
    output reg sample_valid,output reg [15:0] sample_left,sample_right,input sample_ready,
    output reg format_ready,done,output reg [7:0] error_code,
    output reg stereo,output reg [31:0] expected_samples,samples_out,nonzero_samples
);
    // 依次解析文件头和格式块，跳过未知块及奇数长度填充。
    localparam RIFF=0,HEADER=1,FMT=2,SKIP=3,PCM=4,PAD=5,TRAILER=6;
    reg active,fmt_seen,data_seen;reg [2:0] state;
    reg [31:0] pos,magic,wave_id,riff_size,chunk_id,chunk_size,remaining,chunk_pos;
    reg [15:0] format,channels,align,bits;
    reg [31:0] rate,byte_rate;
    reg [7:0] first_byte,third_byte;reg [15:0] left_hold;
    reg [1:0] phase;
    wire [31:0] incoming_size={byte_data,chunk_size[23:0]};
    assign byte_ready=active && (!sample_valid || sample_ready);
    task fail;input [7:0] e;begin error_code<=e;active<=0;sample_valid<=0;done<=1;end endtask
    always @(posedge clk)begin
        if(rst || start)begin
            active<=start;state<=RIFF;pos<=0;magic<=0;wave_id<=0;riff_size<=0;chunk_id<=0;chunk_size<=0;remaining<=0;chunk_pos<=0;
            format<=0;channels<=0;align<=0;bits<=0;rate<=0;byte_rate<=0;fmt_seen<=0;data_seen<=0;
            format_ready<=0;done<=0;error_code<=0;stereo<=0;expected_samples<=0;samples_out<=0;nonzero_samples<=0;
            sample_valid<=0;sample_left<=0;sample_right<=0;first_byte<=0;third_byte<=0;left_hold<=0;phase<=0;
        end else if(cancel)begin active<=0;sample_valid<=0;done<=1;end
        else begin
            if(sample_valid && sample_ready)begin
                sample_valid<=0;
                if(samples_out!=32'hffffffff)samples_out<=samples_out+1'b1;
                if((sample_left!=0 || sample_right!=0) && nonzero_samples!=32'hffffffff)nonzero_samples<=nonzero_samples+1'b1;
            end
            if(byte_valid&&byte_ready)begin
                pos<=pos+1'b1;
                case(state)
                    RIFF:begin
                        case(pos)
                            0,1,2,3:magic<={byte_data,magic[31:8]};
                            4,5,6,7:riff_size<={byte_data,riff_size[31:8]};
                            8,9,10,11:wave_id<={byte_data,wave_id[31:8]};
                        endcase
                        if(pos==11)begin
                            if(magic!=32'h46464952 || {byte_data,wave_id[31:8]}!=32'h45564157 || riff_size+8>file_size || riff_size<36)fail(8'h61);
                            else begin state<=HEADER;chunk_pos<=0;end
                        end
                    end
                    HEADER:begin
                        if(chunk_pos<4)chunk_id[chunk_pos*8+:8]<=byte_data;
                        else chunk_size[(chunk_pos-4)*8+:8]<=byte_data;
                        if(chunk_pos==7)begin
                            chunk_pos<=0;remaining<=incoming_size;
                            if(incoming_size>file_size-pos-1)fail(8'h63);
                            else if(chunk_id==32'h20746d66 && !data_seen)begin
                                if(incoming_size<16)fail(8'h62);else state<=FMT;
                            end else if(chunk_id==32'h61746164 && !data_seen)begin
                                if(!fmt_seen || incoming_size==0 || (stereo?incoming_size[1:0]!=0:incoming_size[0]))fail(8'h62);
                                else begin state<=PCM;data_seen<=1;format_ready<=1;phase<=0;
                                    expected_samples<=stereo?(incoming_size>>2):(incoming_size>>1);end
                            end else if(incoming_size==0)state<=HEADER;else state<=SKIP;
                        end else chunk_pos<=chunk_pos+1'b1;
                    end
                    FMT:begin
                        remaining<=remaining-1'b1;chunk_pos<=chunk_pos+1'b1;
                        case(chunk_pos)
                            0:format[7:0]<=byte_data;1:format[15:8]<=byte_data;2:channels[7:0]<=byte_data;3:channels[15:8]<=byte_data;
                            4:rate[7:0]<=byte_data;5:rate[15:8]<=byte_data;6:rate[23:16]<=byte_data;7:rate[31:24]<=byte_data;
                            8:byte_rate[7:0]<=byte_data;9:byte_rate[15:8]<=byte_data;10:byte_rate[23:16]<=byte_data;11:byte_rate[31:24]<=byte_data;
                            12:align[7:0]<=byte_data;13:align[15:8]<=byte_data;14:bits[7:0]<=byte_data;15:bits[15:8]<=byte_data;
                        endcase
                        if(chunk_pos==15)begin
                            if(format!=1 || (channels!=1 && channels!=2) || rate!=48000 ||
                                align!=(channels<<1) || {byte_data,bits[7:0]}!=16 || byte_rate!=(channels==1?96000:192000))fail(8'h62);
                            else begin fmt_seen<=1;stereo<=channels==2;end
                        end
                        if(remaining==1)begin state<=chunk_size[0]?PAD:HEADER;chunk_pos<=0;end
                    end
                    SKIP:begin remaining<=remaining-1'b1;if(remaining==1)begin state<=chunk_size[0]?PAD:HEADER;chunk_pos<=0;end end
                    PAD:begin state<=HEADER;chunk_pos<=0;end
                    PCM:begin
                        remaining<=remaining-1'b1;
                        case(phase)
                            0:begin first_byte<=byte_data;phase<=1;end
                            1:if(stereo)begin left_hold<={byte_data,first_byte};phase<=2;end
                                else begin sample_left<={byte_data,first_byte};sample_right<={byte_data,first_byte};sample_valid<=1;phase<=0;end
                            2:begin third_byte<=byte_data;phase<=3;end
                            3:begin sample_left<=left_hold;sample_right<={byte_data,third_byte};sample_valid<=1;phase<=0;end
                        endcase
                        if(remaining==1)state<=TRAILER;
                    end
                    TRAILER:begin end
                endcase
                if(byte_last)begin
                    active<=0;done<=1;
                    if(!data_seen || (state!=TRAILER && !(state==PCM && remaining==1)))fail(8'h63);
                end
            end
        end
    end
endmodule
