`timescale 1ns/1ps
module tb_osd;
  localparam int W = 320, H = 240;
  logic clk = 0; always #5 clk = ~clk;
  logic rst_n = 0;
  logic [8:0] pix_x = 0; logic [7:0] pix_y = 0;
  logic [15:0] pix_data;
  logic [8:0] fb_rd_x; logic [7:0] fb_rd_y;
  logic txt_we = 0; logic [9:0] txt_waddr = 0; logic [7:0] txt_wdata = 0;

  // framebuffer stand-in with the real 2-cycle latency: solid red in text rows 0..1 (y < 32),
  // a unique-per-pixel pattern below so that a misaligned fb/glyph pipeline shows up.
  function automatic logic [15:0] fb_pat(input logic [8:0] x, input logic [7:0] y);
    return (y < 32) ? 16'hF800 : {x, y[6:0]};
  endfunction
  logic [15:0] fb_q1, fb_rd_data;
  always_ff @(posedge clk) begin fb_q1 <= fb_pat(fb_rd_x, fb_rd_y); fb_rd_data <= fb_q1; end

  osd_compositor #(.WIDTH(W), .HEIGHT(H)) dut (.clk(clk), .rst_n(rst_n),
    .pix_x(pix_x), .pix_y(pix_y), .pix_data(pix_data),
    .fb_rd_x(fb_rd_x), .fb_rd_y(fb_rd_y), .fb_rd_data(fb_rd_data),
    .txt_we(txt_we), .txt_waddr(txt_waddr), .txt_wdata(txt_wdata));

  logic [7:0] font [0:1535];
  initial $readmemh("mem/font8x16.hex", font);

  // golden model: mirror of the whole 1024-byte text RAM + the compositing rule
  logic [7:0] txt [0:1023];
  initial for (int i = 0; i < 1024; i++) txt[i] = 8'h20;
  // "dimmed by half per channel", written per RGB565 channel rather than as the RTL's bit slice
  function automatic logic [15:0] dim(input logic [15:0] c);
    logic [4:0] r, b; logic [5:0] g;
    r = c[15:11] >> 1; g = c[10:5] >> 1; b = c[4:0] >> 1;
    return {r, g, b};
  endfunction
  function automatic logic [15:0] golden(input int x, input int y);
    logic [7:0] ch; logic [15:0] fb;
    fb = fb_pat(x[8:0], y[7:0]);
    if (x >= W || y >= H) return fb;                 // outside the panel: text never applies
    ch = txt[(y / 16) * (W / 8) + x / 8];
    if (ch[6:0] <= 7'h20) return fb;
    if (font[(ch[6:0] - 7'h20) * 16 + y % 16][7 - x % 8]) return ch[7] ? 16'h07E0 : 16'hFFFF;
    return dim(fb);
  endfunction

  task automatic write_char(input int row, input int col, input logic [7:0] ch);
    @(posedge clk); txt_we <= 1; txt_waddr <= 10'(row * 40 + col); txt_wdata <= ch;
    @(posedge clk); txt_we <= 0;
    txt[row * 40 + col] = ch;
  endtask
  // Drive a new address; pix_data must equal the golden value exactly 3 clocks later and stay
  // there through the 6-clock window st7789_ctrl allows (PIX_LAT). Returns the settled value.
  task automatic read_pix(input int x, input int y, output logic [15:0] v);
    logic [15:0] v3;
    pix_x <= x[8:0]; pix_y <= y[7:0];
    repeat (3) @(posedge clk); #1 v3 = pix_data;
    if (v3 !== golden(x, y)) $fatal(1, "(%0d,%0d): pix_data %h after 3 clocks, golden %h", x, y, v3, golden(x, y));
    repeat (3) @(posedge clk); #1 v = pix_data;
    if (v !== v3) $fatal(1, "(%0d,%0d): pix_data changed after settling: %h -> %h", x, y, v3, v);
  endtask

  logic [15:0] v; int ink;
  initial begin
    repeat (2) @(posedge clk); rst_n = 1;
    write_char(0, 0, 8'h80 | "A");   // highlighted 'A' at (row0,col0)
    write_char(0, 1, "#");           // normal '#' at (row0,col1)
    // cell (0,0): glyph pixels green, background dimmed red
    ink = 0;
    for (int y = 0; y < 16; y++) for (int x = 0; x < 8; x++) begin
      read_pix(x, y, v);
      if (font[("A" - 32) * 16 + y][7 - x]) begin ink++; if (v !== 16'h07E0) $fatal(1, "A ink (%0d,%0d) = %h", x, y, v); end
      else if (v !== 16'h7800) $fatal(1, "A bg (%0d,%0d) = %h", x, y, v);
    end
    if (ink < 10) $fatal(1, "glyph A has too little ink: %0d", ink);
    // cell (0,1): '#' white ink
    read_pix(8 + 3, 7, v);
    if (v !== 16'hFFFF && v !== 16'h7800) $fatal(1, "# pixel = %h", v);
    // empty cell (1,5) -> framebuffer untouched
    read_pix(5 * 8 + 2, 16 + 3, v);
    if (v !== 16'hF800) $fatal(1, "blank cell altered: %h", v);
    // fb address passthrough
    if (fb_rd_x !== 9'd42 || fb_rd_y !== 8'd19) $fatal(1, "fb address not passed through");
    // highlighted space (bit7 set, ASCII 0x20) is still transparent: pure pass-through, no dimming
    write_char(1, 6, 8'h80 | " ");
    read_pix(6 * 8 + 1, 16 + 5, v);
    if (v !== 16'hF800) $fatal(1, "highlighted blank cell altered: %h", v);
    // Patterned framebuffer region (y >= 32): text in row 2, cols 0..1; hop between glyph pixels,
    // dimmed background and blank cells so every read changes the fb value the pipeline must align.
    write_char(2, 0, 8'h80 | "W");
    write_char(2, 1, "g");
    for (int y = 32; y < 48; y++) for (int x = 0; x < 16; x++) begin
      read_pix(x, y, v);
      read_pix(200 + x, 100 + y, v);   // blank cell: passthrough of a different pattern value
    end
    // Out-of-range addresses (never produced by st7789_ctrl, but representable in 9/8 bits) pass the
    // framebuffer through even though the text-address arithmetic aliases them onto real cells:
    // x=400 -> col 50 -> linear cell row*40+50 = cell (row+1, 10); y=250 -> row 15 (beyond the 15 rows).
    write_char(1, 10, "X");      // aliased by (400, 5)
    write_char(7, 10, "X");      // aliased by (400, 100)
    write_char(15, 2, "Y");      // aliased by (19, 250): RAM byte 602, outside the 600 used cells
    read_pix(400, 5, v);   if (v !== 16'hF800)         $fatal(1, "x out of range altered pixel: %h", v);
    read_pix(400, 100, v); if (v !== fb_pat(400, 100)) $fatal(1, "x out of range altered pattern pixel: %h", v);
    read_pix(19, 250, v);  if (v !== fb_pat(19, 250))  $fatal(1, "y out of range altered pixel: %h", v);
    // last text row / last column: the address arithmetic must reach cell (14,39)
    write_char(14, 39, "8");
    read_pix(319, 239, v);
    read_pix(319, 224, v);
    read_pix(312, 239, v);
    // reset clears the output register
    rst_n = 0; @(posedge clk); #1;
    if (pix_data !== 16'h0000) $fatal(1, "pix_data not cleared by reset: %h", pix_data);
    $display("PASS tb_osd");
    $finish;
  end
  initial begin #2_000_000; $fatal(1, "timeout"); end
endmodule
