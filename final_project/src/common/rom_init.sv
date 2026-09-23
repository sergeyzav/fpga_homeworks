`include "common/defs.svh"
// Generic synchronous ROM initialised from a hex file (one word per line, $readmemh format).
// One clock of read latency. Infers BRAM or distributed ROM depending on size.
//
// addr must stay < DEPTH. $clog2(DEPTH) rounds the address width up to the next power of
// two, so when DEPTH itself is not a power of two, addr values in [DEPTH, 2**$clog2(DEPTH)-1]
// are out of range: reads return X in simulation and are undefined in synthesis. The
// simulation-only check below flags any such out-of-range access.
module rom_init #(
  parameter int    WIDTH     = 16,
  parameter int    DEPTH     = 256,
  parameter        INIT_FILE = ""   // untyped: Icarus 13 cannot bind a parent parameter to a `parameter string`
) (
  input  logic                     clk,
  input  logic [$clog2(DEPTH)-1:0] addr,
  output logic [WIDTH-1:0]         data
);
  (* rom_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  `PARAM_CHECK(g_chk_depth, DEPTH < 2, ("rom_init: DEPTH must be >= 2"))

  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

`ifdef SIM
  // Elaborate the range check only when DEPTH is not a power of two: when it is, addr's
  // width exactly spans [0:DEPTH-1], so "addr >= DEPTH" would be a constant-false compare
  // (a Verilator lint warning) rather than a real hazard.
  if (DEPTH != (1 << $clog2(DEPTH))) begin : g_range_check
    // Plain `always`, not `always_ff`: this block is simulation-only ($error is not
    // synthesizable), so the synthesis-intent keyword would just trigger an Icarus warning.
    always @(posedge clk)
      if (int'(addr) >= DEPTH) $error("rom_init: addr %0d >= DEPTH %0d", addr, DEPTH);
  end
`endif

  always_ff @(posedge clk) data <= mem[addr];
endmodule
