`timescale 1ns / 1ps

module tb_led_blinker;

    logic clk;
    logic btn;
    logic led;

    led_blinker #(
        .DEBOUNCE_WIDTH(4)
    ) uut (
        .i_clk(clk),
        .i_btn(btn),
        .o_led(led)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        btn = 0;
        
        #20;

        if (led !== 0)
            $error("FAIL: Initial LED value is not 0");
        else
            $display("PASS: Initial LED value is 0");

        $display("Simulating Button Press 1 (with contact bounce)...");
        btn = 1; #10;
        btn = 0; #20; 
        btn = 1; #15; 
        btn = 0; #10; 
        
        btn = 1;
        #250;

        if (led !== 1)
            $error("FAIL: LED did not toggle to 1 after first press. Current value: %b", led);
        else
            $display("PASS: LED successfully toggled to 1 after first press");

        $display("Simulating Button Release 1 (with contact bounce)...");
        btn = 0; #10;
        btn = 1; #15; 
        btn = 0; #10;
        btn = 1; #10; 
        

        btn = 0;

        #250;


        if (led !== 1)
            $error("FAIL: LED changed state on button release. Current value: %b", led);
        else
            $display("PASS: LED remained 1 after button release");


        $display("Simulating Button Press 2 (with contact bounce)...");
        btn = 1; #15;
        btn = 0; #10; 
        
        btn = 1;
        #250;

        if (led !== 0)
            $error("FAIL: LED did not toggle to 0 after second press. Current value: %b", led);
        else
            $display("PASS: LED successfully toggled back to 0 after second press");

        $finish; 
    end

endmodule