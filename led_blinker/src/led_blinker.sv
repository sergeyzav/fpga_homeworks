`timescale 1ns / 1ps

module led_blinker (
     input logic i_clk,
     output logic o_led
    );

    localparam int COUNT_W = 27;

    logic [3:0]           rst_sr = '0;
    logic                 rst;
    logic [COUNT_W-1:0]   count;

    assign rst = ~&rst_sr;

    always_ff @(posedge i_clk) begin
        rst_sr <= {rst_sr[2:0], 1'b1};

        if (rst)
            count <= '0;
        else
            count <= count + 1;
    end

    always_ff @(negedge i_clk) begin
        if (rst)
            o_led <= 1'b0;
        else if (count == '0)
            o_led <= ~o_led;
    end

endmodule
