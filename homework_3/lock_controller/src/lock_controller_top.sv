`timescale 1ns / 1ps

module lock_controller_top (
     input logic clk,
     input logic rst,
     input logic [3:0] digit_in,
     output logic unlocked_led
    );

    
    logic [3:0] digit_in_reg;

    debouncer debouncer_inst0 (
        .i_clk(clk),
        .i_rst(rst),
        .i_btn(digit_in[0]),
        .o_btn(digit_in_reg[0])
    );

    debouncer debouncer_inst1 (
        .i_clk(clk),
        .i_rst(rst),
        .i_btn(digit_in[1]),
        .o_btn(digit_in_reg[1])
    );

    debouncer debouncer_inst2 (
        .i_clk(clk),
        .i_rst(rst),
        .i_btn(digit_in[2]),
        .o_btn(digit_in_reg[2])
    );

    debouncer debouncer_inst3 (
        .i_clk(clk),
        .i_rst(rst),
        .i_btn(digit_in[3]),
        .o_btn(digit_in_reg[3])
    );

    lock_controller lock_controller_inst(
          .clk(clk),
          .rst(rst),
          .digit_in(digit_in_reg),
          .unlocked_led(unlocked_led)
    );
     
    


    
endmodule
