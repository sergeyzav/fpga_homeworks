`timescale 1ns / 1ps

module tb_led;

    logic [3:0] led;
    logic clk;
    logic rst;

    led led1 (
        .clk(clk),
        .rst(rst),
        .led1(led[0]),
        .led2(led[1]),
        .led3(led[2]),
        .led4(led[3])
    );

    always #5 clk = ~clk;

    task automatic check_led(
        input logic rst_val,
        input logic [3:0] expected_led
    );
        
        rst = rst_val;

        @(negedge clk);
        if (led === expected_led)
            $display("PASS expected=%04b got=%04b", expected_led, led);
        else
             $error("Fail expected=%04b got=%04b", expected_led, led);
    endtask

    initial begin
        clk = 0;
        rst = 1;

        #20;
        rst = 0;
        
        check_led(0, 4'd0);
        check_led(0, 4'd1);
        check_led(0, 4'd2);
        check_led(0, 4'd3);
        check_led(0, 4'd4);
        check_led(0, 4'd5);
        check_led(0, 4'd6);
        check_led(0, 4'd7);
        check_led(0, 4'd8);
        check_led(0, 4'd9);
        check_led(0, 4'd10);
        check_led(0, 4'd11);
        check_led(0, 4'd12);
        check_led(0, 4'd13);
        check_led(0, 4'd14);
        check_led(0, 4'd15);
        check_led(0, 4'd0);
        check_led(0, 4'd1);

        check_led(1, 4'd0);
        check_led(0, 4'd1);

        check_led(1, 4'd0);
        check_led(1, 4'd0);

        $finish; 
    end

endmodule