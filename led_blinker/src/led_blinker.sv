`timescale 1ns / 1ps

module led_blinker #(
    parameter DEBOUNCE_WIDTH = 19
) (
     input logic i_clk,
     input logic i_btn, 
     output logic o_led = 1'b0
    );

    logic btn_debounced;
    logic btn_prev = 1'b0;

    debouncer #(.WIDTH(DEBOUNCE_WIDTH)) debouncer_inst (
        .i_clk(i_clk),
        .i_rst(1'b0),
        .i_btn(i_btn),
        .o_btn(btn_debounced)
    );

    always_ff @(posedge i_clk) begin
        btn_prev <= btn_debounced;

        if (btn_debounced && !btn_prev) begin
            o_led <= ~o_led;
        end
    end

endmodule
