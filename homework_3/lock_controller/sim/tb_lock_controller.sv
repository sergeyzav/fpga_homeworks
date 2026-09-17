`timescale 1ns / 1ps

module tb_lock_controller;

    reg clk;
    reg rst;
    reg [3:0] data_in;
    reg unlocked_led;

    lock_controller lc (
        .clk(clk),
        .rst(rst),
        .digit_in(data_in),
        .unlocked_led(unlocked_led)
    );

    always #5 clk = ~clk;

    task automatic check_locker(input state, input expected_led, input string name);
        if (state !== lc.current_state || expected_led !== unlocked_led)
            $error("Fail %s expected_state=%d, got_state=%d; expected_led=%d, got_led=%d;", name, state, lc.current_state, expected_led, unlocked_led);
        else
            $display("PASS %s", name);
    endtask

    

    initial begin
        clk = 0;
        
        rst = 1;
        #1;
        rst = 0;
        check_locker(lc.LOCKED, 1'b0, "async reset test");
        
        data_in = 4'd3;
        @(posedge clk); #1;
        check_locker(lc.WAIT_D2, 1'b0, "first number correct");

        data_in = 4'd5;
        @(posedge clk); #1;
        check_locker(lc.WAIT_D3, 1'b0, "second number correct");

        data_in = 4'd7;
        @(posedge clk); #1;
        check_locker(lc.UNLOCKED, 1'b1, "third number correct");

        data_in = 4'd9;
        @(posedge clk); #1;
        check_locker(lc.UNLOCKED, 1'b1, "random number after unlocking");

        rst = 1;
        #1;
        rst = 0;

        data_in = 4'd2;
        @(posedge clk); #1;
        check_locker(lc.LOCKED, 1'b0, "first number incorrect");

        data_in = 4'd3;
        @(posedge clk); #1;
        data_in = 4'd6;
        @(posedge clk); #1;
        check_locker(lc.LOCKED, 1'b0, "second number incorrect");

        data_in = 4'd3;
        @(posedge clk); #1;
        data_in = 4'd5;
        @(posedge clk); #1;
        data_in = 4'd8;
        @(posedge clk); #1;
        check_locker(lc.LOCKED, 1'b0, "third number incorrect");
        
        #5;
        $finish; 
    end

endmodule