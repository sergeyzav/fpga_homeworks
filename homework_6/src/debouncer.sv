`timescale 1ns / 1ps

module debouncer #(
    parameter WIDTH = 16
) (
    input  logic i_clk,
    input  logic i_rst, 
    input  logic i_btn,
    output logic o_btn
);

    logic [1:0]       btn_state;
    logic [WIDTH-1:0] counter;

    always_ff @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            btn_state <= '0;
            counter   <= '0;
            o_btn     <= 1'b0;
        end else begin
            btn_state[0] <= i_btn;
            btn_state[1] <= btn_state[0];

            if (btn_state[1] != o_btn) begin
                counter <= counter + 1'b1;
                if (&counter) begin
                    o_btn   <= btn_state[1];
                    counter <= '0;
                end
            end else begin
                counter <= '0;
            end
        end
    end
    
endmodule