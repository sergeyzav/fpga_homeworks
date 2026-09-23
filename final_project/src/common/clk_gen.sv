`timescale 1ns/1ps
`include "common/defs.svh"
// System clock generator: SYS_CLK_IN_HZ (board oscillator on pin N18) -> SYS_CLK_OUT_HZ via MMCME2_BASE.
// The M/D/O factors are solved at elaboration time so only SYS_CLK_IN_HZ needs to change per board.
// Under `SIM the MMCM is replaced by a free-running clock; `locked` rises after 16 output cycles.
module clk_gen #(
  parameter int SYS_CLK_IN_HZ  = 40_000_000,
  parameter int SYS_CLK_OUT_HZ = 100_000_000,
  // VCO ceiling used by the solver. The 7-series -1 datasheet limit is 1200 MHz; 1150 MHz leaves margin
  // against process/temperature spread instead of parking the VCO exactly on the ceiling.
  parameter int VCO_MAX_HZ     = 1_150_000_000
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic clk_in,   // only consumed by the MMCM branch; the `SIM shim free-runs
  // verilator lint_on UNUSEDSIGNAL
  output logic clk_out,
  output logic locked
);
  // ---- MMCM factor solver (7-series -1, MMCME2): D 1..8, M 2..64, O 1..128, all integer.
  // Constraints: fin/D (PFD input) in [PFD_MIN_HZ, PFD_MAX_HZ], VCO = fin*M/D in [VCO_MIN_HZ, VCO_MAX_HZ], VCO/fout integer.
  // Policy: d ascends 1..8, m descends 64..2, so the first hit is the highest legal VCO for the smallest
  // input divider (lower output jitter, farthest from the VCO floor). `solve` is a SV keyword, hence the prefix.
  localparam int PFD_MIN_HZ =  19_000_000;
  localparam int PFD_MAX_HZ = 450_000_000;
  localparam int VCO_MIN_HZ = 600_000_000;

  function automatic int mmcm_solve(input int fin, input int fout, input int which);
    for (int d = 1; d <= 8; d++) begin
      longint pfd = longint'(fin) / longint'(d);
      if (longint'(fin) % longint'(d) != 0 || pfd < longint'(PFD_MIN_HZ) || pfd > longint'(PFD_MAX_HZ)) continue;
      for (int m = 64; m >= 2; m--) begin
        longint vco = pfd * longint'(m);
        if (vco >= longint'(VCO_MIN_HZ) && vco <= longint'(VCO_MAX_HZ) &&
            vco % longint'(fout) == 0 && vco / longint'(fout) >= 1 && vco / longint'(fout) <= 128)
          return (which == 0) ? d : (which == 1) ? m : int'(vco / longint'(fout));
      end
    end
    return -1;
  endfunction

  // verilator lint_off UNUSEDPARAM
  localparam int MMCM_D = mmcm_solve(SYS_CLK_IN_HZ, SYS_CLK_OUT_HZ, 0);
  localparam int MMCM_M = mmcm_solve(SYS_CLK_IN_HZ, SYS_CLK_OUT_HZ, 1);
  localparam int MMCM_O = mmcm_solve(SYS_CLK_IN_HZ, SYS_CLK_OUT_HZ, 2);
  // verilator lint_on UNUSEDPARAM

  // MMCME2 CLKIN1 range for 7-series -1 is 10..800 MHz.
  `PARAM_CHECK(g_chk_clkin, SYS_CLK_IN_HZ < 10_000_000 || SYS_CLK_IN_HZ > 800_000_000,
               ("clk_gen: SYS_CLK_IN_HZ outside MMCM CLKIN range"))
  `PARAM_CHECK(g_chk_mmcm, MMCM_D < 0, ("clk_gen: no MMCM solution for %0d -> %0d Hz", SYS_CLK_IN_HZ, SYS_CLK_OUT_HZ))

`ifdef SIM
  localparam real HALF_NS = 0.5e9 / SYS_CLK_OUT_HZ;
  initial clk_out = 1'b0;
  always #(HALF_NS) clk_out = ~clk_out;
  // `locked` is a flop, not a compare on lock_cnt: it drives rst_sync's async reset downstream, and a
  // registered source keeps lock_cnt out of that sensitivity list (Verilator SYNCASYNCNET). On hardware
  // LOCKED comes straight from the MMCM primitive, so this only concerns the shim.
  int lock_cnt;
  initial begin lock_cnt = 0; locked = 1'b0; end
  always @(posedge clk_out) begin
    if (lock_cnt < 16)  lock_cnt <= lock_cnt + 1;
    if (lock_cnt == 15) locked   <= 1'b1;       // 16th output edge
  end
`else
  logic clk_fb, clk_fb_buf, clk0;
  // verilator lint_off PINCONNECTEMPTY
  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKIN1_PERIOD(1.0e9 / SYS_CLK_IN_HZ),
    .DIVCLK_DIVIDE(MMCM_D),
    .CLKFBOUT_MULT_F(MMCM_M),
    .CLKOUT0_DIVIDE_F(MMCM_O),
    .CLKOUT0_PHASE(0.0), .CLKOUT0_DUTY_CYCLE(0.5),
    .STARTUP_WAIT("FALSE")
  ) u_mmcm (
    .CLKIN1(clk_in), .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKFBOUTB(),
    .CLKOUT0(clk0), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    // RST tied low: there is no upstream reset domain to drive it (this block *creates* the system clock).
    // The MMCM free-runs from CLKIN and reports LOCKED downstream; rst_sync derives the system reset from it.
    .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0)
  );
  // verilator lint_on PINCONNECTEMPTY
  BUFG u_bufg_fb  (.I(clk_fb), .O(clk_fb_buf));
  BUFG u_bufg_out (.I(clk0),   .O(clk_out));
`endif
endmodule
