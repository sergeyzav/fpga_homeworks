`timescale 1ns/1ps
module tb_clk_gen;
  logic clk_in = 0; always #12.5 clk_in = ~clk_in; // 40 MHz
  logic clk_out, locked;
  clk_gen #(.SYS_CLK_IN_HZ(40_000_000), .SYS_CLK_OUT_HZ(100_000_000)) dut
    (.clk_in(clk_in), .clk_out(clk_out), .locked(locked));
  // second instance only for the static solver check (50 MHz board oscillator)
  clk_gen #(.SYS_CLK_IN_HZ(50_000_000), .SYS_CLK_OUT_HZ(100_000_000)) dut50
    (.clk_in(clk_in), .clk_out(), .locked());
  // 600 MHz input: D=1 would put the PFD at 600 MHz (> 450 MHz max), so the solver must fall back to D=2 (PFD 300 MHz)
  clk_gen #(.SYS_CLK_IN_HZ(600_000_000), .SYS_CLK_OUT_HZ(100_000_000)) dut600
    (.clk_in(clk_in), .clk_out(), .locked());
  // 27 MHz input: no integer M/D/O reaches 100 MHz -> solver returns -1. Its `$error` at time 0 is expected output.
  clk_gen #(.SYS_CLK_IN_HZ(27_000_000), .SYS_CLK_OUT_HZ(100_000_000)) dut27
    (.clk_in(clk_in), .clk_out(), .locked());

  realtime t0, t1;
  initial begin
    wait (locked);
    @(posedge clk_out); t0 = $realtime;
    repeat (100) @(posedge clk_out); t1 = $realtime;
    // 100 periods of 10 ns
    if (t1 - t0 < 999.0 || t1 - t0 > 1001.0) $fatal(1, "clk_out period wrong: %f ns per 100", t1 - t0);
    // static check of the MMCM parameter solver
    // highest VCO <= 1150 MHz: 40*25 = 1000, 50*22 = 1100, (600/2)*3 = 900
    if (dut.MMCM_D != 1 || dut.MMCM_M != 25 || dut.MMCM_O != 10)
      $fatal(1, "MMCM solver 40 MHz: D=%0d M=%0d O=%0d (expected 1/25/10)", dut.MMCM_D, dut.MMCM_M, dut.MMCM_O);
    if (dut50.MMCM_D != 1 || dut50.MMCM_M != 22 || dut50.MMCM_O != 11)
      $fatal(1, "MMCM solver 50 MHz: D=%0d M=%0d O=%0d (expected 1/22/11)", dut50.MMCM_D, dut50.MMCM_M, dut50.MMCM_O);
    if (dut600.MMCM_D != 2 || dut600.MMCM_M != 3 || dut600.MMCM_O != 9)
      $fatal(1, "MMCM solver 600 MHz: D=%0d M=%0d O=%0d (expected 2/3/9)", dut600.MMCM_D, dut600.MMCM_M, dut600.MMCM_O);
    if (dut27.MMCM_D != -1)
      $fatal(1, "MMCM solver 27 MHz: D=%0d (expected -1, no solution)", dut27.MMCM_D);
    $display("PASS tb_clk_gen");
    $finish;
  end
endmodule
