`include "common/defs.svh"
// Character RAM for the OSD: DEPTH bytes, bit7 = highlight, bits6:0 = ASCII. Initialised to spaces
// (0x20) so an unwritten screen is fully transparent. Read latency 1 clock.
//
// Read/write ordering: the read port returns the old byte when the same address is written in the
// same clock (read-first), but nothing synchronises ui_ctrl writes with the raster. A string written
// while the display is scanning that row can show a torn glyph (old and new character mixed) for
// one frame; this is accepted, the next frame is consistent.
//
// Synthesis: Vivado infers BRAM or distributed LUTRAM depending on DEPTH (either is fine at this
// size) and honours the initial-fill below as the memory's power-up contents.
module osd_text_ram #(
  parameter int DEPTH = 1024
) (
  input  logic                     clk,
  input  logic                     we,
  input  logic [$clog2(DEPTH)-1:0] waddr,
  input  logic [7:0]               wdata,
  input  logic [$clog2(DEPTH)-1:0] raddr,
  output logic [7:0]               rdata
);
  `PARAM_CHECK(g_chk_depth, DEPTH < 2, ("osd_text_ram: DEPTH must be >= 2"))

  logic [7:0] mem [0:DEPTH-1];
  initial for (int i = 0; i < DEPTH; i++) mem[i] = 8'h20;

  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    rdata <= mem[raddr];
  end
endmodule
