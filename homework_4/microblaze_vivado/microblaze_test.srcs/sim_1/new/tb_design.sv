`timescale 1 ns / 1 ps

module tb_design();

  reg clk;
  reg rst;
  tri [1:0] gpio_leds_tri_io;
  tri gpio_btn_tri_io;
  tri [3:0]gpio_sw_tri_io;
  
  reg [1:0] gpio_leds;
  reg gpio_btn;
  reg [3:0]gpio_sw;
  
  assign gpio_leds_tri_io = gpio_leds;
  assign gpio_btn_tri_io = gpio_btn;
  assign gpio_sw_tri_io = gpio_sw;


  always #5 clk = ~clk;

  design_1_wrapper dut (
    .clk(clk),
    .gpio_btn_tri_io(gpio_btn_tri_io),
    .gpio_leds_tri_io(gpio_leds_tri_io),
    .gpio_sw_tri_io(gpio_sw_tri_io),
    .rst(rst)
  );

  initial begin
    clk = 1'b0;
    rst = 1'b0;
    gpio_btn = 1'b1;
    gpio_sw = 4'b1111;
    gpio_leds <= 2'b11;
   
    $display("=== Simulation Started ===");
   
    #100;
    rst = 1'b1; 
    $display("=== Reset Released. MicroBlaze starting execution ===");
    #5000;
    
    $display("=== Current LEDs State: gpio_leds = %b ===", gpio_leds_tri_io);

    #1000000;
    $display("=== Simulation Finished ===");
    //$finish;
  end

  initial begin
    $monitor("Time = %0t ns | Reset = %b | LEDs (gpio_leds) = %b", $time, rst, gpio_leds_tri_io);
  end

endmodule