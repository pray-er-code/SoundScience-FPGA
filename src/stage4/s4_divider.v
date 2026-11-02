`timescale 1ns/1ps
// 无符号迭代除法器
module s4_divider(input clk,rst,start,input [31:0] numerator,input [15:0] denominator,
    output reg busy,done,output reg [31:0] quotient);
    reg [31:0] dividend;reg [16:0] remainder;reg [15:0] divisor;reg [5:0] count;
    wire [16:0] shifted={remainder[15:0],dividend[31]};
    always @(posedge clk)begin
        if(rst)begin busy<=0;done<=0;quotient<=0;dividend<=0;remainder<=0;divisor<=1;count<=0;end
        else begin done<=0;
            if(start&&!busy)begin busy<=1;dividend<=numerator;divisor<=denominator==0?1:denominator;remainder<=0;quotient<=0;count<=0;end
            else if(busy)begin
                dividend<={dividend[30:0],1'b0};
                if(shifted>=divisor)begin remainder<=shifted-divisor;quotient<={quotient[30:0],1'b1};end
                else begin remainder<=shifted;quotient<={quotient[30:0],1'b0};end
                if(count==31)begin busy<=0;done<=1;end else count<=count+1'b1;
            end
        end
    end
endmodule

// 图像到 720p 的比例适配计算
module s4_fit(input clk,rst,start,input [10:0] width,height,input [15:0] source_width,source_height,
    output reg busy,done,output reg [10:0] output_width,output_height,
    output reg [31:0] x_step,y_step);
    reg ds;reg [31:0] numerator;reg [15:0] denominator;wire dd,db;wire [31:0] quotient;
    reg [2:0] state;reg wide;reg [10:0] w,h;
    reg [15:0] source_w,source_h;reg [31:0] fit_lhs,fit_rhs;
    s4_divider divide(.clk(clk),.rst(rst),.start(ds),.numerator(numerator),.denominator(denominator),.busy(db),.done(dd),.quotient(quotient));
    always @(posedge clk)begin
        if(rst)begin busy<=0;done<=0;ds<=0;state<=0;wide<=0;w<=1;h<=1;source_w<=1;source_h<=1;fit_lhs<=0;fit_rhs<=0;
            numerator<=0;denominator<=1;output_width<=1;output_height<=1;x_step<=0;y_step<=0;end
        else begin ds<=0;done<=0;
            if(start&&!busy)begin
                busy<=1;w<=width;h<=height;source_w<=source_width;source_h<=source_height;state<=6;
            end else case(state)
                6:begin fit_lhs<=source_w*720;fit_rhs<=source_h*1280;state<=7;end
                7:begin
                    wide<=fit_lhs>=fit_rhs;numerator<=fit_lhs>=fit_rhs?fit_rhs:fit_lhs;
                    denominator<=fit_lhs>=fit_rhs?source_w:source_h;ds<=1;state<=1;
                end
                1:if(dd)begin
                    output_width<=wide?1280:(quotient==0?1:quotient);
                    output_height<=wide?(quotient==0?1:quotient):720;state<=2;
                end
                2:begin numerator<=(w-32'd1)<<16;denominator<=output_width>1?output_width-1'b1:1;ds<=1;state<=3;end
                3:if(dd)begin x_step<=output_width>1?quotient:0;state<=4;end
                4:begin numerator<=(h-32'd1)<<16;denominator<=output_height>1?output_height-1'b1:1;ds<=1;state<=5;end
                5:if(dd)begin y_step<=output_height>1?quotient:0;state<=0;busy<=0;done<=1;end
            endcase
        end
    end
endmodule
