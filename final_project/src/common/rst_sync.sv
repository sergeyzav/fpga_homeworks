`include "common/defs.svh"
// Reset synchroniser: asynchronous assertion, synchronous deassertion after N_STAGES clocks.
// N_STAGES must be >= 2 (one stage cannot filter metastability on the deassertion edge).
module rst_sync #(
  parameter int N_STAGES = 4
) (
  input  logic clk,
  input  logic arst_n,   // asynchronous active-low reset (e.g. ~mmcm_locked)
  output logic rst_n     // synchronous active-low reset for this clock domain
);
  (* ASYNC_REG = "TRUE" *) logic [N_STAGES-1:0] shreg;

  `PARAM_CHECK(g_chk_stages, N_STAGES < 2, ("rst_sync: N_STAGES must be >= 2"))

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) shreg <= '0;
    else         shreg <= N_STAGES'({shreg, 1'b1});  // explicit truncation to N_STAGES bits
  end

  assign rst_n = shreg[N_STAGES-1];
endmodule
