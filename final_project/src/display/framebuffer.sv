`include "common/defs.svh"
// WIDTH x HEIGHT x RGB565 frame store in BRAM. Simple dual port, both ports on clk.
// Read latency: 2 clocks (address register + BRAM output register).
// Write: wr_en/wr_x/wr_y/wr_data are sampled on one edge and the location is updated on that edge;
// a read of the same location issued on that same edge still returns the old contents (read-first).
module framebuffer #(
  parameter int WIDTH  = 320,
  parameter int HEIGHT = 240
) (
  input  logic                      clk,
  input  logic                      wr_en,
  input  logic [$clog2(WIDTH)-1:0]  wr_x,
  input  logic [$clog2(HEIGHT)-1:0] wr_y,
  input  logic [15:0]               wr_data,
  input  logic [$clog2(WIDTH)-1:0]  rd_x,
  input  logic [$clog2(HEIGHT)-1:0] rd_y,
  output logic [15:0]               rd_data
);
  localparam int DEPTH = WIDTH * HEIGHT;
  localparam int AW    = $clog2(DEPTH);

  `PARAM_CHECK(g_chk_geom, WIDTH < 8 || HEIGHT < 8 || WIDTH % 8 != 0,
               ("framebuffer: WIDTH/HEIGHT must be >= 8 and WIDTH a multiple of 8"))

  (* ram_style = "block" *) logic [15:0] mem [0:DEPTH-1];

  // Linear address = y * WIDTH + x. Operands are widened to AW bits before the multiply so the
  // product is sized explicitly; y * WIDTH + x < DEPTH <= 2**AW, so nothing is truncated.
  logic [AW-1:0] wr_addr, rd_addr;
  always_comb begin
    wr_addr = AW'(wr_y) * AW'(WIDTH) + AW'(wr_x);
    rd_addr = AW'(rd_y) * AW'(WIDTH) + AW'(rd_x);
  end

  logic [15:0] rd_q;
  always_ff @(posedge clk) begin
    if (wr_en) mem[wr_addr] <= wr_data;
    rd_q    <= mem[rd_addr];
    rd_data <= rd_q;
  end
endmodule
