`include "common/defs.svh"
// Overlays 8x16 text on the framebuffer while the display controller scans pixels.
//
// Latency pix_x/pix_y -> pix_data: exactly 3 clocks. Two parallel paths meet in stage 2:
//   framebuffer: fb_rd_x/y (= pix_x/y, combinational) -> fb_rd_data after 2 clocks
//   text:        text RAM (1 clock) -> font ROM (1 clock)
// and the composed pixel is registered once more. pix_data is stable from the 3rd clock after an
// address change for as long as the address is held (st7789_ctrl holds it >= PIX_LAT = 6 clocks).
// All pipeline stages except the pix_data output register are intentionally reset-free: they carry
// only data derived from the current address and flush within 3 clocks of reset release.
//
// Text RAM byte: bit7 = highlight, bits6:0 = ASCII. Characters <= 0x20 are transparent (framebuffer
// shows through). Glyph ink: white, or green when highlighted. Background inside a non-space cell:
// framebuffer pixel dimmed by half per channel.
module osd_compositor #(
  parameter int WIDTH  = 320,
  parameter int HEIGHT = 240,
  parameter     FONT_FILE = {`MEM_DIR, "/font8x16.hex"}
) (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic [$clog2(WIDTH)-1:0]  pix_x,
  input  logic [$clog2(HEIGHT)-1:0] pix_y,
  output logic [15:0]               pix_data,
  // framebuffer read port (2-cycle latency)
  output logic [$clog2(WIDTH)-1:0]  fb_rd_x,
  output logic [$clog2(HEIGHT)-1:0] fb_rd_y,
  input  logic [15:0]               fb_rd_data,
  // text RAM write port (from ui_ctrl): address = row * COLS + col
  input  logic                      txt_we,
  input  logic [9:0]                txt_waddr,
  input  logic [7:0]                txt_wdata
);
  localparam int COLS      = WIDTH / 8;    // 40 for 320
  localparam int ROWS      = HEIGHT / 16;  // 15 for 240
  localparam int TXT_DEPTH = 1024;
  localparam logic [15:0] C_WHITE = 16'hFFFF, C_GREEN = 16'h07E0;

  `PARAM_CHECK(g_chk_geom, WIDTH % 8 != 0 || HEIGHT % 16 != 0, ("osd_compositor: WIDTH must be a multiple of 8 and HEIGHT of 16"))
  `PARAM_CHECK(g_chk_cells, COLS * ROWS > TXT_DEPTH, ("osd_compositor: %0d text cells exceed the %0d-byte text RAM", COLS * ROWS, TXT_DEPTH))

  assign fb_rd_x = pix_x;
  assign fb_rd_y = pix_y;

  // stage 0: text cell address = (pix_y / 16) * COLS + pix_x / 8, all terms sized to the RAM address
  logic [9:0] txt_raddr;
  assign txt_raddr = 10'(pix_y >> 4) * 10'(COLS) + 10'(pix_x >> 3);
  logic [7:0] txt_rdata;
  osd_text_ram #(.DEPTH(TXT_DEPTH)) u_txt (.clk(clk), .we(txt_we), .waddr(txt_waddr), .wdata(txt_wdata),
                                           .raddr(txt_raddr), .rdata(txt_rdata));
  logic [2:0] x_d1; logic [3:0] y_d1; logic in_range_d1;
  always_ff @(posedge clk) begin
    x_d1 <= pix_x[2:0]; y_d1 <= pix_y[3:0];
    in_range_d1 <= (int'(pix_x) < WIDTH) && (int'(pix_y) < HEIGHT);
  end

  // stage 1: font address from the character (txt_rdata is the cell for the address of stage 0).
  // Blank cells look up glyph 0 (space) so the ROM address always stays < 96*16.
  logic [6:0]  ch_d1; logic hl_d1, blank_d1; logic [6:0] glyph_d1; logic [10:0] font_addr;
  assign ch_d1     = txt_rdata[6:0];
  assign hl_d1     = txt_rdata[7];
  assign blank_d1  = (ch_d1 <= 7'h20) || !in_range_d1;
  assign glyph_d1  = blank_d1 ? 7'd0 : ch_d1 - 7'h20;
  assign font_addr = 11'(glyph_d1) * 11'd16 + 11'(y_d1);
  logic [7:0] font_row;
  rom_init #(.WIDTH(8), .DEPTH(1536), .INIT_FILE(FONT_FILE)) u_font (.clk(clk), .addr(font_addr), .data(font_row));
  logic [2:0] x_d2; logic hl_d2, blank_d2;
  always_ff @(posedge clk) begin x_d2 <= x_d1; hl_d2 <= hl_d1; blank_d2 <= blank_d1; end

  // stage 2: compose (fb_rd_data and font_row both belong to the same pixel here)
  logic ink; logic [15:0] dim;
  assign ink = font_row[3'd7 - x_d2];
  assign dim = {1'b0, fb_rd_data[15:12], 1'b0, fb_rd_data[10:6], 1'b0, fb_rd_data[4:1]};
  always_ff @(posedge clk) begin
    if (!rst_n)        pix_data <= '0;
    else if (blank_d2) pix_data <= fb_rd_data;
    else if (ink)      pix_data <= hl_d2 ? C_GREEN : C_WHITE;
    else               pix_data <= dim;
  end
endmodule
