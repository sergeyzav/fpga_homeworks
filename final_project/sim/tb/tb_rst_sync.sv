`timescale 1ns/1ps
module tb_rst_sync;
  localparam int N_STAGES = 4;

  // arst_n starts high and is asserted at t=1 from the initial block: a time-0 declaration
  // initialiser races the always_ff process start in Icarus, so the negedge would be missed.
  logic clk = 0, arst_n = 1, rst_n;
  always #5 clk = ~clk;

  rst_sync #(.N_STAGES(N_STAGES)) dut (.clk(clk), .arst_n(arst_n), .rst_n(rst_n));

  // global watchdog
  initial begin #1000; $fatal(1, "timeout"); end

  int cycles;
  initial begin
    // asynchronous assertion: rst_n must be low immediately, without a clock
    #1 arst_n = 0;
    #1 if (rst_n !== 1'b0) $fatal(1, "rst_n not low while arst_n low");
    repeat (3) @(posedge clk);
    #1 arst_n = 1;
    // deassertion must take exactly N_STAGES rising edges
    cycles = 0;
    while (rst_n !== 1'b1) begin @(posedge clk); #1 cycles++; if (cycles > 10) $fatal(1, "never deasserted"); end
    if (cycles != N_STAGES) $fatal(1, "deasserted after %0d cycles, expected %0d", cycles, N_STAGES);
    // re-assert asynchronously mid-cycle
    #2 arst_n = 0;
    #1 if (rst_n !== 1'b0) $fatal(1, "async re-assert failed");
    $display("PASS tb_rst_sync");
    $finish;
  end
endmodule
