

`timescale 1ns / 1ps

module tb_microblaze_wrapper;

    localparam integer RESET_NS = 1000;

    localparam integer RUN_NS   = 800000;

    localparam integer EXTERNAL_CLOCK_TICK = 50;

    reg clk_100 = 0;
    reg aclk_external = 0;
    reg reset_rtl = 0;  
    reg gpio_btn_tri_i = 0;  
    reg [7:0] data = 8'b0;  
    
    always #5 clk_100 = ~clk_100;  // 100 Mhz
    always #(EXTERNAL_CLOCK_TICK) aclk_external = ~aclk_external;  // 10 Mhz
    always #(EXTERNAL_CLOCK_TICK*100) gpio_btn_tri_i = ~gpio_btn_tri_i; 
    
     always @(posedge aclk_external) data <= data + 1;  // 1 Mhz

    

    microblaze_wrapper dut (
        .clk_100 (clk_100),
        .aclk_external (aclk_external),
        .reset_rtl(reset_rtl),
        .gpio_btn_tri_i(gpio_btn_tri_i),
        .data(data)
    );

    initial begin
        reset_rtl = 0;
        #(RESET_NS);
        reset_rtl = 1;
        $display("[%0t] Reset знято, MicroBlaze має почати виконувати програму", $time);
        $display("[%0t] Симуляція завершена", $time);
        #(150000000);
        $finish;
    end

//    initial begin
//        #(15000000);
//        $display("TIMEOUT");
//        $finish;
//    end

endmodule