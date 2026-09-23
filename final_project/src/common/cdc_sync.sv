`include "common/defs.svh"
// N-bit level synchroniser (2 flops by default). Only for quasi-static / single-bit signals:
// individual bits may arrive in different cycles.
module cdc_sync #(
  parameter int WIDTH  = 1,
  parameter int STAGES = 2
) (
  input  logic             clk,
  input  logic [WIDTH-1:0] d,
  output logic [WIDTH-1:0] q
);
  `PARAM_CHECK(g_chk_stages, STAGES < 2, ("cdc_sync: STAGES must be >= 2"))

  (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] stage [STAGES];

  always_ff @(posedge clk) begin
    stage[0] <= d;
    for (int i = 1; i < STAGES; i++) stage[i] <= stage[i-1];
  end
  assign q = stage[STAGES-1];
endmodule
