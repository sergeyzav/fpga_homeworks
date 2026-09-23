// Shared compile-time definitions. Include with `include "common/defs.svh" (include path = src/).
`ifndef DEFS_SVH
`define DEFS_SVH
// Directory holding $readmemh images, relative to where the simulator / Vivado is launched (repo root).
`ifndef MEM_DIR
`define MEM_DIR "mem"
`endif

// Parameter guard, used at module scope: `PARAM_CHECK(g_chk_x, COND, ("module: message %0d", VAL))
// with COND true meaning "bad parameters". `msg` is a parenthesised $error argument list so formatted
// messages keep working; no trailing semicolon at the call site.
`ifdef SIM
  // simulation: non-fatal so TBs can test bad parameters deliberately (tb_clk_gen dut27, tb_ui_ctrl idx 17)
  `define PARAM_CHECK(name, cond, msg) initial if (cond) $error msg;
`else
  // synthesis: IEEE 1800-2012 20.11 elaboration task at generate scope so Vivado stops on a bad parameter
  // (an `initial` block is treated as init-only there and the check would be silently dropped)
  `define PARAM_CHECK(name, cond, msg) if (cond) begin : name $error msg; end
`endif
`endif
