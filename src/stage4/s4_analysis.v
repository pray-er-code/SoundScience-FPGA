`timescale 1ns/1ps

// 实际播放音频的波形与频谱分析
module s4_analysis #(parameter SHORT_LESSONS=0)(
    input clk,rst,consumed,input signed [15:0] sample,input [15:0] token,
    input low_frequency,freeze,zero_trigger,frame_start,comparison_scale,
    input [7:0] wave_address,input [4:0] spectrum_address,
    output wire signed [15:0] wave_value,output wire [15:0] spectrum_value,
    output reg [31:0] blocks,output reg [1:0] stage,output reg [31:0] stage_samples,
    output reg [15:0] analysis_token,output reg frozen,output reg [7:0] first_error,
    output reg [2:0] wave_range,
    input short_lesson,output example_hold
);
    // 输入为实际播放的 PCM；全频分析 256 点，低频模式先按八点平均抽取。
    reg hold_example;
    // 示例淡出前保持分析结果，音频消费和阶段计数继续。
    assign example_hold=SHORT_LESSONS&&short_lesson&&hold_example;
    wire signed [31:0] s1,s2;wire [63:0] state_data;reg signed [31:0] s1_reg,s2_reg;
    wire [15:0] spectrum_data;
    reg wave_front,spectrum_front,write_page;
    reg [7:0] sample_index;reg [4:0] bin;
    reg [2:0] decimation;reg [4:0] state;reg low_old,freeze_old,previous_negative,triggered;
    reg signed [15:0] held_sample;
    reg signed [19:0] low_sum;
    wire signed [19:0] low_total=low_sum+$signed(sample);
    reg signed [15:0] analysis_sample;
    reg analysis_sample_valid,trigger_old;
    reg [7:0] trigger_wait;
    wire trigger_accept=triggered||!zero_trigger||
        (previous_negative&&analysis_sample>=16'sd128)||trigger_wait==8'hff;
    reg signed [17:0] coefficient;reg signed [15:0] sine;
    reg signed [31:0] final_s1,final_s2,real_part,imag_part;
    reg signed [49:0] multiply_reg;
    wire signed [17:0] selected_coefficient=state==4?{{2{sine[15]}},sine}:coefficient;
    wire signed [31:0] selected_state=state==2||state==4?final_s2:s1_reg;
    wire signed [49:0] recurrence_product=selected_coefficient*selected_state;
    wire signed [31:0] next_state=(multiply_reg>>>14)-s2_reg+($signed(held_sample)>>>4);
    assign s1=state_data[31:0];assign s2=state_data[63:32];
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(64),.DATA_WIDTH_B(64),.ADDR_WIDTH_A(5),.ADDR_WIDTH_B(5),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) recurrence_ram(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(state==1||state==3||state==6),.addra(bin),.dia(state==1?{s1_reg,next_state}:64'b0),.rsta(1'b0),.bea(1'b1),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(bin),.dib(64'b0),.rstb(1'b0),.beb(1'b1),.dob(state_data));
    wire capture_wave=analysis_sample_valid&&!freeze&&state==0&&trigger_accept;
    wire [15:0] wave_data;
    reg results_valid;
    reg [15:0] wave_peak,peak_history;
    wire [15:0] absolute_sample=analysis_sample[15]?(~analysis_sample+16'd1):analysis_sample;
    wire [15:0] released_peak=peak_history-(peak_history>>4);
    wire [15:0] range_peak=wave_peak>released_peak?wave_peak:released_peak;
    function [2:0] select_range;input [15:0] peak;begin
        if(peak>28672)select_range=0;
        else if(peak>14336)select_range=1;
        else if(peak>7168)select_range=2;
        else if(peak>3584)select_range=3;
        else if(peak>1792)select_range=4;
        else if(peak>896)select_range=5;
        else select_range=6;
    end endfunction
    assign wave_value=results_valid?wave_data:16'b0;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) waveform_ram(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(capture_wave),.addra({write_page,sample_index}),.dia(analysis_sample),.rsta(1'b0),.bea(1'b1),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb({wave_front,wave_address}),.dib(16'b0),.rstb(1'b0),.beb(1'b1),.dob(wave_data));
    wire [31:0] abs_real=real_part[31]?-real_part:real_part;
    wire [31:0] abs_imag=imag_part[31]?-imag_part:imag_part;
    wire [31:0] maximum=abs_real>abs_imag?abs_real:abs_imag;
    wire [31:0] minimum=abs_real>abs_imag?abs_imag:abs_real;
    // 用较大值加较小值的 3/8 近似计算幅值。
    wire [32:0] magnitude={1'b0,maximum}+(minimum>>2)+(minimum>>3);
    reg [31:0] abs_real_reg,abs_imag_reg;reg [32:0] magnitude_reg;
    reg [31:0] maximum_reg,minimum_reg,fraction_reg;
    wire [31:0] max_reg=abs_real_reg>abs_imag_reg?abs_real_reg:abs_imag_reg;
    wire [31:0] min_reg=abs_real_reg>abs_imag_reg?abs_imag_reg:abs_real_reg;
    assign spectrum_value=results_valid?spectrum_data:16'b0;
    // 保存上一块频谱供平滑处理。
    wire [15:0] spectrum_history;
    wire [15:0] raw_magnitude=magnitude_reg[32:5]>65535?16'hffff:magnitude_reg[20:5];
    reg history_valid;reg [17:0] smooth_sum;reg [15:0] smooth_value;
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(5),.ADDR_WIDTH_B(5),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) history_ram(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(state==13),.addra(bin),.dia(smooth_value),.rsta(1'b0),.bea(1'b1),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(bin),.dib(16'b0),.rstb(1'b0),.beb(1'b1),.dob(spectrum_history));
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(6),.ADDR_WIDTH_B(6),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("9K")) spectrum_ram(
        .clka(clk),.cea(1'b1),.ocea(1'b1),.wea(state==13),.addra({~spectrum_front,bin}),
        .dia(smooth_value),.rsta(1'b0),.bea(1'b1),
        .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb({spectrum_front,spectrum_address}),.dib(16'b0),.rstb(1'b0),.beb(1'b1),.dob(spectrum_data));
    // 频点系数由 tools/make_analysis_coefficients.py 生成。
    always @*begin
        case(bin)
            0:begin coefficient=32758;sine=402;end 1:begin coefficient=32729;sine=804;end
            2:begin coefficient=32679;sine=1205;end 3:begin coefficient=32610;sine=1606;end
            4:begin coefficient=32522;sine=2006;end 5:begin coefficient=32413;sine=2404;end
            6:begin coefficient=32286;sine=2801;end 7:begin coefficient=32138;sine=3196;end
            8:begin coefficient=31972;sine=3590;end 9:begin coefficient=31786;sine=3981;end
            10:begin coefficient=31581;sine=4370;end 11:begin coefficient=31357;sine=4756;end
            12:begin coefficient=31114;sine=5139;end 13:begin coefficient=30853;sine=5520;end
            14:begin coefficient=30572;sine=5897;end 15:begin coefficient=30274;sine=6270;end
            16:begin coefficient=29957;sine=6639;end 17:begin coefficient=29622;sine=7005;end
            18:begin coefficient=29269;sine=7366;end 19:begin coefficient=28899;sine=7723;end
            20:begin coefficient=28511;sine=8076;end 21:begin coefficient=28106;sine=8423;end
            22:begin coefficient=27684;sine=8765;end 23:begin coefficient=27246;sine=9102;end
            24:begin coefficient=26791;sine=9434;end 25:begin coefficient=26320;sine=9760;end
            26:begin coefficient=25833;sine=10080;end 27:begin coefficient=25330;sine=10394;end
            28:begin coefficient=24812;sine=10702;end 29:begin coefficient=24279;sine=11003;end
            30:begin coefficient=23732;sine=11297;end default:begin coefficient=23170;sine=11585;end
        endcase
    end
    integer i;
    always @(posedge clk)begin
        if(rst)begin
            blocks<=0;stage<=0;stage_samples<=0;analysis_token<=0;frozen<=0;first_error<=0;hold_example<=0;
            wave_front<=0;spectrum_front<=0;write_page<=1;sample_index<=0;bin<=0;decimation<=0;state<=6;
            low_old<=0;freeze_old<=0;previous_negative<=0;triggered<=0;held_sample<=0;final_s1<=0;final_s2<=0;real_part<=0;imag_part<=0;
            multiply_reg<=0;
            s1_reg<=0;s2_reg<=0;
            low_sum<=0;
            abs_real_reg<=0;abs_imag_reg<=0;magnitude_reg<=0;
            maximum_reg<=0;minimum_reg<=0;fraction_reg<=0;
            results_valid<=0;wave_peak<=0;peak_history<=0;wave_range<=1;
            analysis_sample<=0;analysis_sample_valid<=0;trigger_old<=0;trigger_wait<=0;
            history_valid<=0;smooth_sum<=0;smooth_value<=0;
        end else begin
            low_old<=low_frequency;freeze_old<=freeze;trigger_old<=zero_trigger;
            analysis_sample_valid<=0;
            if(consumed&&!freeze&&state!=11)begin
                if(low_frequency)begin
                    decimation<=decimation+1'b1;
                    low_sum<=decimation==7?0:low_total;
                    if(decimation==7)begin analysis_sample<=low_total>>>3;analysis_sample_valid<=1;end
                end else begin analysis_sample<=sample;analysis_sample_valid<=1;end
            end
            if(consumed)begin
                if(stage_samples!=32'hffffffff)stage_samples<=stage_samples+1'b1;
                if(SHORT_LESSONS&&short_lesson&&stage_samples>=566399)hold_example<=1;
                if(stage_samples>=((SHORT_LESSONS&&short_lesson)?575999:815999))stage<=3;else if(stage_samples>=431999)stage<=2;else if(stage_samples>=383999)stage<=1;else stage<=0;
            end
            if(token!=analysis_token || low_old!=low_frequency || trigger_old!=zero_trigger || (freeze_old&&!freeze))begin
                analysis_token<=token;sample_index<=0;bin<=0;state<=6;decimation<=0;triggered<=0;previous_negative<=0;
                if(token!=analysis_token)begin stage_samples<=0;stage<=0;blocks<=0;frozen<=0;hold_example<=0;end
                if(low_old!=low_frequency)blocks<=0;
                results_valid<=0;wave_peak<=0;peak_history<=0;wave_range<=1;
                low_sum<=0;
                analysis_sample_valid<=0;trigger_wait<=0;history_valid<=0;
            end else begin
                if(capture_wave&&absolute_sample>wave_peak)wave_peak<=absolute_sample;
                frozen<=freeze;
                if(analysis_sample_valid && !freeze && state!=11)begin
                    if(!triggered)begin
                        if(analysis_sample<=-16'sd128)previous_negative<=1;
                        if(trigger_wait!=8'hff)trigger_wait<=trigger_wait+1'b1;
                    end
                    if(trigger_accept)begin
                        if(state!=0)begin if(first_error==0)first_error<=8'h91;end
                        else begin
                            held_sample<=analysis_sample;bin<=0;state<=7;triggered<=1;
                        end
                    end
                end
                case(state)
                    1:begin
                        if(sample_index==255)begin final_s1<=next_state;final_s2<=s1_reg;state<=2;end
                        else if(bin==31)begin sample_index<=sample_index+1'b1;state<=0;end else begin bin<=bin+1'b1;state<=7;end
                    end
                    2:begin multiply_reg<=recurrence_product;state<=9;end
                    9:begin real_part<=final_s1-(multiply_reg>>>15);state<=4;end
                    4:begin multiply_reg<=recurrence_product;state<=10;end
                    10:begin imag_part<=multiply_reg>>>14;state<=3;end
                    3:begin abs_real_reg<=abs_real;abs_imag_reg<=abs_imag;state<=12;end
                    12:begin maximum_reg<=max_reg;minimum_reg<=min_reg;state<=15;end
                    15:begin fraction_reg<=(minimum_reg>>2)+(minimum_reg>>3);state<=16;end
                    16:begin magnitude_reg<={1'b0,maximum_reg}+fraction_reg;state<=17;end
                    17:begin
                        smooth_sum<=history_valid?({2'b0,spectrum_history}<<1)+spectrum_history+raw_magnitude:({2'b0,raw_magnitude}<<2);
                        state<=18;
                    end
                    18:begin smooth_value<=smooth_sum[17:2];state<=13;end
                    13:begin
                        if(bin==31)begin
                            state<=11;
                        end else begin bin<=bin+1'b1;state<=7;end
                    end
                    6:if(bin==31)begin state<=0;bin<=0;end else bin<=bin+1'b1;
                    7:state<=8;
                    8:begin s1_reg<=s1;s2_reg<=s2;state<=14;end
                    14:begin multiply_reg<=recurrence_product;state<=1;end
                    11:if(frame_start&&!freeze)begin
                        wave_range<=comparison_scale?(wave_peak>28672?3'd0:3'd1):select_range(range_peak);
                        peak_history<=range_peak;wave_peak<=0;
                        results_valid<=1;
                        history_valid<=1;
                        spectrum_front<=~spectrum_front;wave_front<=write_page;write_page<=~write_page;sample_index<=0;triggered<=0;previous_negative<=0;trigger_wait<=0;
                        if(blocks!=32'hffffffff)blocks<=blocks+1'b1;state<=0;
                    end
                endcase
            end
        end
    end
endmodule
