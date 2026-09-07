`timescale 1ns / 1ps

module tb_led_blinker;

    logic clk;
    logic led;

    led_blinker led_blinker (
        .i_clk(clk),
        .o_led(led)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        #5;

        if (led !== 0)
            $error("FAIL. init led=0");
        else
            $display("PASS.  init led=0");
        
        #50;
        
        if (led !== 1)
            $error("FAIL. led=1");
        else
            $display("PASS. led=1");
        $finish; 
    end

endmodule