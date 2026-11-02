`timescale 1ns/1ps

// 正式版精简数码管状态
module s4_mini_diag #(parameter integer SCAN_CYCLES=41667)(
    input clk,rst,input display_valid,input [2:0] displayed_id,
    input [7:0] sd_error,file_error,image_error,wav_error,sub_error,movie_error,
    input mem_fault,refresh_fault,input [3:0] pixel_faults,
    output reg [5:0] seg_sel,output reg [7:0] seg_data);
    reg [23:0] first_error;reg [15:0] scan;reg [2:0] digit;reg [23:0] live_error;
    wire [3:0] page=display_valid?{1'b0,displayed_id}+4'd1:4'd0;
    wire [23:0] value=first_error!=0?first_error:{20'hc2600,page};
    always @*begin
        live_error=0;
        if(sd_error!=0)live_error={16'he100,sd_error};
        else if(file_error!=0)live_error={16'he200,file_error};
        else if(mem_fault||refresh_fault)live_error={20'he4000,2'b0,refresh_fault,mem_fault};
        else if(image_error!=0)live_error={16'he300,image_error};
        else if(pixel_faults[1:0]!=0)live_error={20'he5000,2'b0,pixel_faults[1:0]};
        else if(pixel_faults[2])live_error=24'he60001;
        else if(wav_error!=0)live_error={16'he700,wav_error};
        else if(sub_error!=0)live_error={16'he800,sub_error};
        else if(pixel_faults[3])live_error=24'he90091;
        else if(movie_error!=0)live_error={16'hea00,movie_error};
    end
    function [7:0] hex;input [3:0] n;begin case(n)
        0:hex=8'hc0;1:hex=8'hf9;2:hex=8'ha4;3:hex=8'hb0;4:hex=8'h99;5:hex=8'h92;6:hex=8'h82;7:hex=8'hf8;
        8:hex=8'h80;9:hex=8'h90;10:hex=8'h88;11:hex=8'h83;12:hex=8'hc6;13:hex=8'ha1;14:hex=8'h86;15:hex=8'h8e;
    endcase end endfunction
    always @(posedge clk)begin
        if(rst)begin first_error<=0;scan<=0;digit<=0;seg_sel<=63;seg_data<=255;end
        else begin
            if(first_error==0&&live_error!=0)first_error<=live_error;
            if(scan==SCAN_CYCLES-1)begin
                scan<=0;digit<=digit==5?0:digit+1'b1;seg_sel<=~(6'b1<<digit);
                case(digit)
                    0:seg_data<=hex(value[23:20]);1:seg_data<=hex(value[19:16])&8'h7f;2:seg_data<=hex(value[15:12]);
                    3:seg_data<=hex(value[11:8]);4:seg_data<=hex(value[7:4]);5:seg_data<=hex(value[3:0]);
                endcase
            end else scan<=scan+1'b1;
        end
    end
endmodule
