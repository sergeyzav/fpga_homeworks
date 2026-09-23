`timescale 1ns/1ps
// Stimulus uses nonblocking assignments at posedge so the DUT flops sample the
// previous value (avoids a same-timestep race with blocking assignments).
module tb_cdc;
  logic clk_a = 0, clk_b = 0, rst_a_n = 0, rst_b_n = 0;
  always #5  clk_a = ~clk_a;   // 100 MHz
  always #6.25 clk_b = ~clk_b; // 80 MHz

  logic [3:0] lvl_a = 0, lvl_b;
  cdc_sync #(.WIDTH(4)) u_lvl (.clk(clk_b), .d(lvl_a), .q(lvl_b));

  logic pulse_a = 0, pulse_b;
  cdc_pulse u_pulse (.clk_src(clk_a), .rst_src_n(rst_a_n), .pulse_src(pulse_a),
                     .clk_dst(clk_b), .rst_dst_n(rst_b_n), .pulse_dst(pulse_b));

  int got = 0;
  always @(posedge clk_b) if (pulse_b) got++;

  initial begin
    repeat (3) @(posedge clk_a); rst_a_n <= 1; rst_b_n <= 1;
    // level: value appears after 2 clk_b edges
    @(posedge clk_a); lvl_a <= 4'hA;
    // must NOT be visible before any clk_b edge (proves the flops are in the path)
    @(negedge clk_a);
    if (lvl_b !== 4'h0) $fatal(1, "cdc_sync bypassed: value visible before clk_b edges");
    repeat (3) @(posedge clk_b); #1;
    if (lvl_b !== 4'hA) $fatal(1, "cdc_sync did not pass value, got %h", lvl_b);
    // pulse: 5 well-separated pulses -> 5 single-cycle pulses in dst
    repeat (5) begin
      @(posedge clk_a); pulse_a <= 1; @(posedge clk_a); pulse_a <= 0;
      repeat (8) @(posedge clk_a);
    end
    repeat (10) @(posedge clk_b);
    if (got != 5) $fatal(1, "expected 5 dst pulses, got %0d", got);
    // pulse_dst must be exactly one clk_b wide
    got = 0;
    @(posedge clk_a); pulse_a <= 1; @(posedge clk_a); pulse_a <= 0;
    repeat (10) @(posedge clk_b);
    if (got != 1) $fatal(1, "pulse width wrong: counted %0d", got);
    $display("PASS tb_cdc");
    $finish;
  end
endmodule
