`timescale 1ns/1ps

// 按键短按与长按识别
module s4_key_event #(
    parameter integer LONG_CYCLES=30000000,DEBOUNCE_CYCLES=1000000,ENABLE_LONG=1
)(input clk,rst,key_n,output pressed,output reg short_pulse,long_pulse);
    reg [1:0] sync_key;reg stable,long_sent;reg [19:0] debounce;reg [25:0] held;
    assign pressed=!stable;
    always @(posedge clk)begin
        if(rst)begin sync_key<=3;stable<=1;long_sent<=0;debounce<=0;held<=0;short_pulse<=0;long_pulse<=0;end
        else begin
            sync_key<={sync_key[0],key_n};short_pulse<=0;long_pulse<=0;
            if(sync_key[1]==stable)debounce<=0;
            else if(debounce>=DEBOUNCE_CYCLES-1)begin
                debounce<=0;stable<=sync_key[1];
                if(!sync_key[1])begin held<=0;long_sent<=0;end
                else begin if(!long_sent)short_pulse<=1;held<=0;end
            end else debounce<=debounce+1'b1;
            if(ENABLE_LONG&&!stable&&!sync_key[1]&&!long_sent)begin
                if(held>=LONG_CYCLES-1)begin long_pulse<=1;long_sent<=1;end
                else held<=held+1'b1;
            end
        end
    end
endmodule

// 按键拨码与菜单参数控制
module s4_controls #(
    parameter integer LONG_CYCLES=35000000,DEBOUNCE_CYCLES=1000000
)(input clk,rst,key_next_n,key_auto_n,key_dec_n,menu_switch,
    output reg next_pulse,prev_pulse,auto_pulse,replay_pulse,movie_pulse,
    output reg paused,menu,output reg [3:0] selection,volume,brightness,contrast,
    output reg [1:0] transition,view,output reg low_frequency,freeze,zero_trigger,test_tone,color_bars,
    output reg [2:0] period_setting,output reg light_ui,full_demo);
    wire np,ap,dp,ns,as,ds,nl,al,dl;reg [1:0] ms;reg armed,chord;
    s4_key_event #(.LONG_CYCLES(LONG_CYCLES),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) kn(
        .clk(clk),.rst(rst),.key_n(key_next_n),.pressed(np),.short_pulse(ns),.long_pulse(nl));
    s4_key_event #(.LONG_CYCLES(LONG_CYCLES),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) ka(
        .clk(clk),.rst(rst),.key_n(key_auto_n),.pressed(ap),.short_pulse(as),.long_pulse(al));
    s4_key_event #(.LONG_CYCLES(LONG_CYCLES),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) kd(
        .clk(clk),.rst(rst),.key_n(key_dec_n),.pressed(dp),.short_pulse(ds),.long_pulse(dl));
    // 长按触发后抑制释放短按，组合键触发后等待全部松开。
    wire released=!np&&!ap&&!dp;
    wire multiple=(np&&ap)||(dp&&(np||ap));
    always @(posedge clk)begin
        if(rst)begin
            ms<=0;armed<=0;chord<=0;next_pulse<=0;prev_pulse<=0;auto_pulse<=0;replay_pulse<=0;movie_pulse<=0;
            paused<=0;menu<=0;selection<=0;volume<=8;brightness<=8;contrast<=8;transition<=1;view<=1;
            low_frequency<=0;freeze<=0;zero_trigger<=1;test_tone<=0;color_bars<=0;period_setting<=4;light_ui<=1;full_demo<=1;
        end else begin
            ms<={ms[0],menu_switch};menu<=ms[1];
            next_pulse<=0;prev_pulse<=0;auto_pulse<=0;replay_pulse<=0;movie_pulse<=0;
            if(menu!=ms[1])begin armed<=0;chord<=0;end
            else begin
                if(!armed&&released&&!ns&&!as&&!ds)armed<=1;
                if(released&&!ns&&!as&&!ds)chord<=0;
                if(armed&&!chord)begin
                    if(multiple)begin
                        chord<=1;
                        if(np&&dp&&!ap&&!menu)begin replay_pulse<=1;paused<=0;end
                    end else if(!menu)begin
                        if(ns)next_pulse<=1;if(ds)prev_pulse<=1;
                        if(nl)freeze<=~freeze;
                        if(as)paused<=~paused;if(al)auto_pulse<=1;
                        if(dl)begin movie_pulse<=1;paused<=0;end
                    end else begin
                        if(ns)selection<=selection==(full_demo?6:7)?0:selection+1'b1;
                        if(as||ds)case(selection)
                            0:volume<=ds?(volume==0?0:volume-1'b1):(volume==8?8:volume+1'b1);
                            1:brightness<=ds?(brightness==0?0:brightness-1'b1):(brightness==15?15:brightness+1'b1);
                            2:contrast<=ds?(contrast==0?0:contrast-1'b1):(contrast==15?15:contrast+1'b1);
                            3:transition<=ds?transition-1'b1:transition+1'b1;
                            4:view<=view==1?2:1;
                            5:low_frequency<=!ds;
                            6:full_demo<=!ds;
                            7:if(!full_demo)period_setting<=ds?(period_setting==0?0:period_setting-1'b1):(period_setting==7?7:period_setting+1'b1);
                        endcase
                    end
                end
            end
        end
    end
endmodule
