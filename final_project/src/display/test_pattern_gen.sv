`include "common/defs.svh"
// Writes a static test image into the framebuffer once per `start` pulse:
// 1-pixel white border, rows 0..(2/3 H): 8 SMPTE-style colour bars, remaining rows: horizontal grey gradient.
//
// Timing: `done` is a one-clock pulse in the same cycle as the last `wr_en`; that final write commits
// on the following clock edge, so consumers must wait one more clock after `done` before reading the
// last pixel. `start` is ignored while `busy`.
//
// No per-pixel division: the bar index and the gradient level are tracked incrementally as `cx`
// advances along a row. A per-bar pixel counter bumps the bar index every BAR_W pixels, and the
// gradient level floor(x*64/WIDTH) comes from an accumulator that adds 64 per pixel and gives up one
// level per WIDTH taken out of it (integer division by repeated subtraction, exact for any WIDTH).
// The 5-bit level floor(x*32/WIDTH) is that value halved, since floor(floor(n/d)/2) == floor(n/(2d)).
module test_pattern_gen #(
  parameter int WIDTH  = 320,
  parameter int HEIGHT = 240
) (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic                      start,
  output logic                      busy,
  output logic                      done,
  output logic                      wr_en,
  output logic [$clog2(WIDTH)-1:0]  wr_x,
  output logic [$clog2(HEIGHT)-1:0] wr_y,
  output logic [15:0]               wr_data
);
  localparam int BAR_W    = WIDTH / 8;
  localparam int BARS_END = (HEIGHT * 2) / 3;

  `PARAM_CHECK(g_chk_geom, WIDTH < 8 || HEIGHT < 8 || WIDTH % 8 != 0,
               ("test_pattern_gen: WIDTH/HEIGHT must be >= 8 and WIDTH a multiple of 8"))

  function automatic logic [15:0] bar_colour(input logic [2:0] idx);
    case (idx)
      3'd0: return 16'hFFFF; 3'd1: return 16'hFFE0; 3'd2: return 16'h07FF; 3'd3: return 16'h07E0;
      3'd4: return 16'hF81F; 3'd5: return 16'hF800; 3'd6: return 16'h001F; default: return 16'h0000;
    endcase
  endfunction

  // cx/cy are the pattern coordinates; the write port is registered one cycle later so that
  // address and data stay aligned. done pulses in the same cycle as the last wr_en.
  localparam int XW = $clog2(WIDTH), YW = $clog2(HEIGHT);
  logic [XW-1:0] cx;
  logic [YW-1:0] cy;

  // Row state for x = cx, all zero at x = 0 and stepped once per cx increment.
  // acc6 is (cx*64) mod WIDTH and lvl6 is floor(cx*64/WIDTH); per step acc6 grows by 64 and each WIDTH
  // taken out of it is one level. One subtraction per step suffices when WIDTH >= 64; smaller
  // geometries need up to ceil(64/WIDTH), unrolled by the constant-bound loop below.
  localparam int STEPS6 = (64 + WIDTH - 1) / WIDTH;
  localparam int AW     = $clog2(WIDTH + 64);      // acc6 < WIDTH before the add, < WIDTH + 64 after
  logic [XW-1:0] bar_px;                           // pixel index within the current bar, 0..BAR_W-1
  logic [2:0]    bar_idx;
  logic [AW-1:0] acc6;
  logic [5:0]    lvl6;
  logic [AW-1:0] acc6_n;
  logic [5:0]    lvl6_n;
  always_comb begin
    acc6_n = acc6 + AW'(64);
    lvl6_n = lvl6;
    for (int i = 0; i < STEPS6; i++)
      if (acc6_n >= AW'(WIDTH)) begin acc6_n = acc6_n - AW'(WIDTH); lvl6_n = lvl6_n + 1'b1; end
  end

  // Grey gradient: R and B use the 5-bit level, G the full 6-bit one, so x=1 -> 0x0000 and x=WIDTH-2 -> 0xFFFF.
  function automatic logic [15:0] pixel(input logic [XW-1:0] x, input logic [YW-1:0] y,
                                        input logic [2:0] bar, input logic [5:0] l6);
    if (x == '0 || y == '0 || x == XW'(WIDTH - 1) || y == YW'(HEIGHT - 1)) return 16'hFFFF;
    if (y < YW'(BARS_END)) return bar_colour(bar);
    return {l6[5:1], l6, l6[5:1]};
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0; done <= 1'b0; wr_en <= 1'b0; cx <= '0; cy <= '0; wr_x <= '0; wr_y <= '0; wr_data <= '0;
      bar_px <= '0; bar_idx <= '0; acc6 <= '0; lvl6 <= '0;
    end else begin
      done  <= 1'b0;
      wr_en <= busy;
      wr_x  <= cx; wr_y <= cy; wr_data <= pixel(cx, cy, bar_idx, lvl6);
      if (!busy) begin
        if (start) begin
          busy <= 1'b1; cx <= '0; cy <= '0;
          bar_px <= '0; bar_idx <= '0; acc6 <= '0; lvl6 <= '0;
        end
      end else begin
        if (cx == XW'(WIDTH - 1)) begin
          cx <= '0;
          bar_px <= '0; bar_idx <= '0; acc6 <= '0; lvl6 <= '0;     // row start: x = 0
          if (cy == YW'(HEIGHT - 1)) begin cy <= '0; busy <= 1'b0; done <= 1'b1; end
          else cy <= cy + 1'b1;
        end else begin
          cx <= cx + 1'b1;
          if (bar_px == XW'(BAR_W - 1)) begin bar_px <= '0; bar_idx <= bar_idx + 1'b1; end
          else bar_px <= bar_px + 1'b1;
          acc6 <= acc6_n; lvl6 <= lvl6_n;
        end
      end
    end
  end
endmodule
