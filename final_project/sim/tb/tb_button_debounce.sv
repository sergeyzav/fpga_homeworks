`timescale 1ns/1ps
// btn is driven at negedge clk so the DUT samples a stable value (no same-timestep race).
module tb_button_debounce;
  // 1 MHz clock, 1 ms debounce = 1000 cycles, 5 ms long press = 5000 cycles
  localparam int CLK_HZ = 1_000_000, DEBOUNCE_MS = 1, LONG_MS = 5;
  localparam int DEB_CYC  = (CLK_HZ / 1000) * DEBOUNCE_MS;
  localparam int LONG_CYC = (CLK_HZ / 1000) * LONG_MS;
  // Release latency: btn=1 (set after edge E_n) is sampled at E_n+1, crosses 2 sync flops and
  // DEB_CYC debounce edges, so pressed falls at E_n+DEB_CYC+2. The hold counter runs the whole
  // time pressed is high, i.e. hold = n + DEB_CYC + 2 cycles when n is measured from pressed rising.
  // long_press fires when the hold reaches LONG_CYC, so the boundary in n is:
  localparam int N_BOUND = LONG_CYC - DEB_CYC - 2; // n >= N_BOUND -> long, n < N_BOUND -> short

  logic clk = 0, rst_n = 0, btn = 1; // active-low button, idle high
  always #500 clk = ~clk;

  logic pressed, short_press, long_press;
  button_debounce #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS), .LONG_MS(LONG_MS), .ACTIVE_LOW(1)) dut
    (.clk(clk), .rst_n(rst_n), .btn(btn), .pressed(pressed), .short_press(short_press), .long_press(long_press));

  int n_short = 0, n_long = 0;
  always @(posedge clk) begin n_short += short_press; n_long += long_press; end

  task drive(input logic v);
    @(negedge clk); btn = v;
  endtask

  task press_for(input int cycles);
    drive(0); repeat (cycles) @(posedge clk); drive(1); repeat (1500) @(posedge clk);
  endtask

  // hold btn low until pressed rises, then for exactly n more clk edges before releasing
  task hold_from_pressed(input int n);
    drive(0); @(posedge pressed); repeat (n) @(posedge clk); drive(1); repeat (1500) @(posedge clk);
  endtask

  initial begin
    repeat (3) @(posedge clk); rst_n = 1;
    // glitch shorter than debounce -> ignored
    press_for(300);
    if (n_short != 0 || n_long != 0 || pressed) $fatal(1, "glitch not filtered");
    // 2 ms press -> one short press on release
    press_for(2000);
    if (n_short != 1 || n_long != 0) $fatal(1, "short press: short=%0d long=%0d", n_short, n_long);
    // 8 ms press -> one long press, no short
    press_for(8000);
    if (n_short != 1 || n_long != 1) $fatal(1, "long press: short=%0d long=%0d", n_short, n_long);
    // bouncing edge: 5 toggles of 100 cycles then held 3 ms -> exactly one short
    repeat (5) begin drive(0); repeat (100) @(posedge clk); drive(1); repeat (100) @(posedge clk); end
    press_for(3000);
    if (n_short != 2 || n_long != 1) $fatal(1, "bounce: short=%0d long=%0d", n_short, n_long);
    // exact boundary: hold of LONG_CYC-1 cycles -> short only
    hold_from_pressed(N_BOUND - 1);
    if (n_short != 3 || n_long != 1) $fatal(1, "boundary-1: short=%0d long=%0d", n_short, n_long);
    // exact boundary: hold of LONG_CYC cycles -> long only (pressed falls on the same edge long fires)
    hold_from_pressed(N_BOUND);
    if (n_short != 3 || n_long != 2) $fatal(1, "boundary: short=%0d long=%0d", n_short, n_long);
    $display("PASS tb_button_debounce");
    $finish;
  end
endmodule
