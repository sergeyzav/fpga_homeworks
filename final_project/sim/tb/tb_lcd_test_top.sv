`timescale 1ns/1ps
module tb_lcd_test_top;
  // 160x64 window: 20 text columns x 4 rows, so the header row and all three list rows (1..3) are on screen.
  // Geometry used by the expectations below (test_pattern_gen, osd_compositor, ui_demo):
  //   BAR_W = 160/8 = 20      -> bar i covers x 20i..20i+19 (0 white, 1 yellow, 2 cyan, 3 green, 4 magenta, 5 red, 6 blue, 7 black)
  //   BARS_END = 64*2/3 = 42  -> y < 42 bars, y >= 42 grey gradient {lvl5, lvl6, lvl5}, lvl5 = x*32/160, lvl6 = x*64/160
  //   border: x = 0, x = 159, y = 0, y = 63 are white
  //   text cell (c, r) = x 8c..8c+7, y 16r..16r+15; LIST_COL = COLS-8 = 12 (x 96..159); TEST_COL = 12 on row 0
  localparam int W = 160, H = 64, COLS = W / 8, LIST_COL = COLS - 8, TEST_COL = 12;
  localparam logic [15:0] C_WHITE = 16'hFFFF, C_GREEN = 16'h07E0, C_DIM_WHITE = 16'h7BEF, C_MAGENTA = 16'hF81F;
  logic i_clk = 0; always #12.5 i_clk = ~i_clk;   // 40 MHz board clock (sim shim ignores the value)
  logic btn_n = 1;
  logic lcd_sclk, lcd_mosi, lcd_cs_n, lcd_dcx, lcd_resx_n;

  lcd_test_top #(.SYS_CLK_IN_HZ(40_000_000), .WIDTH(W), .HEIGHT(H), .SPI_CLK_DIV(1), .SIM_FAST(1),
                 .BTN_DEBOUNCE_MS(1), .BTN_LONG_MS(5), .TEST_COL(TEST_COL)) dut
    (.i_clk(i_clk), .btn_n(btn_n), .lcd_sclk(lcd_sclk), .lcd_mosi(lcd_mosi), .lcd_cs_n(lcd_cs_n), .lcd_dcx(lcd_dcx), .lcd_resx_n(lcd_resx_n));

  st7789v_slave_model #(.MIN_SCLK_PERIOD_NS(19.9), .RESET_TO_CMD_NS(5_000.0), .RESET_TO_SLPOUT_NS(120_000.0),
                        .SLPOUT_TO_CMD_NS(5_000.0), .SWRESET_TO_CMD_NS(5_000.0)) panel   // SIM_FAST: ms -> us
    (.sclk(lcd_sclk), .mosi(lcd_mosi), .cs_n(lcd_cs_n), .dcx(lcd_dcx), .resx_n(lcd_resx_n));

  // Reference ROMs: the font decides which pixels of a cell are ink, the channel-name ROM what the list says.
  logic [7:0] font [0:1535]; logic [7:0] names [0:511];
  initial begin $readmemh("mem/font8x16.hex", font); $readmemh("mem/chan_names.hex", names); end

  function automatic int count_cell(input int col, input int row, input logic [15:0] v);
    int n = 0;
    for (int y = row * 16; y < row * 16 + 16; y++) for (int x = col * 8; x < col * 8 + 8; x++) if (panel.pixel(x, y) == v) n++;
    return n;
  endfunction
  // Exact glyph check. Inside a non-blank cell every ink pixel is `ink` and every other pixel is a dimmed
  // framebuffer value (bit 15/10/4 clear, so never white or green): the ink mask must equal the font rows.
  function automatic bit glyph_ok(input int col, input int row, input byte ch, input logic [15:0] ink);
    for (int y = 0; y < 16; y++) for (int x = 0; x < 8; x++)
      if ((panel.pixel(col * 8 + x, row * 16 + y) == ink) != font[(int'(ch) - 32) * 16 + y][7 - x]) return 1'b0;
    return 1'b1;
  endfunction
  // Channel `idx` name (8 ROM bytes) drawn at (col,row) in `ink`; space cells are transparent and not checked.
  task automatic check_chan(input int col, input int row, input int idx, input logic [15:0] ink, input string what);
    for (int i = 0; i < 8; i++) if (names[idx * 8 + i] != 8'h20 && !glyph_ok(col + i, row, names[idx * 8 + i], ink))
      $fatal(1, "%s: channel %0d glyph '%c' at cell (%0d,%0d) not drawn in %h", what, idx, names[idx * 8 + i], col + i, row, ink);
  endtask
  task automatic check_test_hdr();
    logic [31:0] txt = "TEST";
    for (int i = 0; i < 4; i++) if (!glyph_ok(TEST_COL + i, 0, txt[31 - 8 * i -: 8], C_WHITE))
      $fatal(1, "header glyph '%c' at cell (%0d,0) not drawn in white", txt[31 - 8 * i -: 8], TEST_COL + i);
  endtask

  initial begin
    wait (panel.n_frames == 4);        // three complete frames written after init
    if (panel.n_errors != 0) $fatal(1, "protocol errors: %0d", panel.n_errors);
    // bar 1 (x 20..39) under text row 1 (y 16..31): cell (3,1) is blank -> pure yellow
    if (panel.pixel(30, 20) !== 16'hFFE0) $fatal(1, "bar pixel %h", panel.pixel(30, 20));
    // gradient row y = 50 (>= 42, not the border), cells (0,3) (7,3) (10,3) are blank (list starts at col 12):
    //   x = 1:  lvl5 = 1*32/160 = 0,   lvl6 = 1*64/160 = 0   -> 0x0000
    //   x = 60: lvl5 = 60*32/160 = 12, lvl6 = 60*64/160 = 24 -> {01100,011000,01100} = 0x630C
    //   x = 80: lvl5 = 80*32/160 = 16, lvl6 = 80*64/160 = 32 -> {10000,100000,10000} = 0x8410
    if (panel.pixel(1, 50) !== 16'h0000 || panel.pixel(60, 50) !== 16'h630C || panel.pixel(80, 50) !== 16'h8410)
      $fatal(1, "gradient wrong: %h %h %h", panel.pixel(1, 50), panel.pixel(60, 50), panel.pixel(80, 50));
    // cell (0,0) = 'A' over white bar 0 + white border: ink white + dimmed white background = whole cell
    if (count_cell(0, 0, C_WHITE) + count_cell(0, 0, C_DIM_WHITE) != 128) $fatal(1, "cell(0,0) not text-composited");
    if (count_cell(0, 0, C_WHITE) < 10) $fatal(1, "no glyph ink in cell(0,0)");
    // header row: channel 0 name at col 0, "TEST" at TEST_COL, both white
    check_chan(0, 0, 0, C_WHITE, "header");
    if (count_cell(TEST_COL, 0, C_WHITE) < 10) $fatal(1, "no glyph ink in the TEST cell");
    check_test_hdr();
    // the cell left of the list, (11,1) = x 88..95 inside bar 4 (x 80..99): untouched magenta, no dimming
    if (count_cell(LIST_COL - 1, 1, C_MAGENTA) != 128) $fatal(1, "cell left of the list is not pure bar colour");
    // list: entry 0 (row 1) highlighted green, entries 1 and 2 (rows 2, 3) white
    if (count_cell(LIST_COL, 1, C_GREEN) < 10) $fatal(1, "list entry 0 not highlighted");
    if (count_cell(LIST_COL, 2, C_GREEN) != 0) $fatal(1, "list entry 1 should not be highlighted");
    if (count_cell(LIST_COL, 2, C_WHITE) < 10) $fatal(1, "list entry 1 not drawn white");
    if (count_cell(LIST_COL, 3, C_GREEN) != 0) $fatal(1, "list entry 2 should not be highlighted");
    check_chan(LIST_COL, 1, 0, C_GREEN, "before press");
    check_chan(LIST_COL, 2, 1, C_WHITE, "before press");
    check_chan(LIST_COL, 3, 2, C_WHITE, "before press");
    // short press -> selection 1 highlighted after the next frames
    btn_n = 0; #2_000_000; btn_n = 1;   // 2 ms hold (debounce 1 ms, long 5 ms)
    wait (panel.n_frames == 7);
    if (panel.n_errors != 0) $fatal(1, "protocol errors after the press: %0d", panel.n_errors);
    if (count_cell(LIST_COL, 2, C_GREEN) < 10) $fatal(1, "list entry 1 not highlighted after button");
    if (count_cell(LIST_COL, 1, C_GREEN) != 0) $fatal(1, "list entry 0 still highlighted");
    if (count_cell(LIST_COL, 1, C_WHITE) < 10) $fatal(1, "list entry 0 not redrawn white");
    if (count_cell(LIST_COL, 3, C_GREEN) != 0) $fatal(1, "list entry 2 highlighted after button");
    check_chan(LIST_COL, 1, 0, C_WHITE, "after press");
    check_chan(LIST_COL, 2, 1, C_GREEN, "after press");
    check_chan(LIST_COL, 3, 2, C_WHITE, "after press");
    check_chan(0, 0, 0, C_WHITE, "after press"); check_test_hdr();   // header untouched by the list rewrite
    panel.dump_ppm("sim/build/tb_lcd_test_top.ppm");
    $display("PASS tb_lcd_test_top");
    $finish;
  end
  initial begin #60_000_000; $fatal(1, "timeout"); end
endmodule
