// M1 hardware top: test pattern + OSD text on the ST7789V. Button (active low) cycles the highlighted list entry.
module lcd_test_top #(
  parameter int SYS_CLK_IN_HZ   = 40_000_000,
  parameter int WIDTH           = 320,
  parameter int HEIGHT          = 240,
  parameter int SPI_CLK_DIV     = 4,     // 100 MHz / 8 = 12.5 MHz SCLK (in spec)
  parameter bit SIM_FAST        = 0,
  parameter int BTN_DEBOUNCE_MS = 20,
  parameter int BTN_LONG_MS     = 1000,
  parameter int TEST_COL        = 12     // text column of the "TEST" header string (row 0)
) (
  input  logic i_clk,
  input  logic btn_n,
  output logic lcd_sclk,
  output logic lcd_mosi,
  output logic lcd_cs_n,
  output logic lcd_dcx,
  output logic lcd_resx_n
);
  localparam int SYS_CLK_HZ = 100_000_000;
  localparam int COLS = WIDTH / 8;

  // clocks and reset. MMCM lock is the only reset source: rst_n asserts while the MMCM is unlocked and
  // releases 4 sys_clk later; there is no reset pin, so re-resetting the design means reconfiguring the FPGA.
  logic sys_clk, locked, rst_n;
  clk_gen  #(.SYS_CLK_IN_HZ(SYS_CLK_IN_HZ), .SYS_CLK_OUT_HZ(SYS_CLK_HZ)) u_clk (.clk_in(i_clk), .clk_out(sys_clk), .locked(locked));
  rst_sync #(.N_STAGES(4)) u_rst (.clk(sys_clk), .arst_n(locked), .rst_n(rst_n));

  // display chain
  logic cs_req, tx_valid, tx_ready, tx_dc, spi_busy; logic [7:0] tx_data;
  logic [$clog2(WIDTH)-1:0] pix_x, fb_rd_x; logic [$clog2(HEIGHT)-1:0] pix_y, fb_rd_y;
  logic [15:0] pix_data, fb_rd_data;
  logic init_done;
  // status outputs not used by this top (no LEDs / debug port yet)
  /* verilator lint_off UNUSEDSIGNAL */
  logic frame_done, pat_busy, pat_done, pressed, long_press;
  /* verilator lint_on UNUSEDSIGNAL */

  st7789_spi_master #(.CLK_DIV(SPI_CLK_DIV)) u_spi (.clk(sys_clk), .rst_n(rst_n), .cs_req(cs_req),
    .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc), .busy(spi_busy),
    .sclk(lcd_sclk), .mosi(lcd_mosi), .cs_n(lcd_cs_n), .dcx(lcd_dcx));

  st7789_ctrl #(.CLK_HZ(SYS_CLK_HZ), .SIM_FAST(SIM_FAST), .WIDTH(WIDTH), .HEIGHT(HEIGHT), .PIX_LAT(6), .CLK_DIV(SPI_CLK_DIV)) u_ctrl (
    .clk(sys_clk), .rst_n(rst_n), .cs_req(cs_req), .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc),
    .spi_busy(spi_busy), .lcd_resx_n(lcd_resx_n), .pix_x(pix_x), .pix_y(pix_y), .pix_data(pix_data),
    .init_done(init_done), .frame_done(frame_done));

  // framebuffer + test pattern, drawn once when reset releases. The WIDTH*HEIGHT writes (76800 clocks =
  // 0.77 ms at 320x240) finish inside st7789_ctrl's 120 ms post-reset wait, so the first frame streamed
  // to the panel is already complete. (SIM_FAST shrinks that wait to 120 us: keep TB windows below ~12000 pixels.)
  logic pat_start, wr_en; logic [$clog2(WIDTH)-1:0] wr_x; logic [$clog2(HEIGHT)-1:0] wr_y; logic [15:0] wr_data;
  logic started;
  always_ff @(posedge sys_clk) begin
    if (!rst_n) begin started <= 1'b0; pat_start <= 1'b0; end
    else begin pat_start <= !started; started <= 1'b1; end
  end
  test_pattern_gen #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_pat (.clk(sys_clk), .rst_n(rst_n), .start(pat_start), .busy(pat_busy), .done(pat_done),
    .wr_en(wr_en), .wr_x(wr_x), .wr_y(wr_y), .wr_data(wr_data));
  framebuffer #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_fb (.clk(sys_clk), .wr_en(wr_en), .wr_x(wr_x), .wr_y(wr_y), .wr_data(wr_data),
    .rd_x(fb_rd_x), .rd_y(fb_rd_y), .rd_data(fb_rd_data));

  // OSD
  logic txt_we; logic [9:0] txt_waddr; logic [7:0] txt_wdata;
  osd_compositor #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_osd (.clk(sys_clk), .rst_n(rst_n), .pix_x(pix_x), .pix_y(pix_y), .pix_data(pix_data),
    .fb_rd_x(fb_rd_x), .fb_rd_y(fb_rd_y), .fb_rd_data(fb_rd_data), .txt_we(txt_we), .txt_waddr(txt_waddr), .txt_wdata(txt_wdata));

  logic job_valid, job_ready, job_src, job_hl; logic [3:0] job_row; logic [5:0] job_col, job_idx;
  ui_ctrl #(.COLS(COLS)) u_ui (.clk(sys_clk), .rst_n(rst_n), .job_valid(job_valid), .job_ready(job_ready), .job_row(job_row), .job_col(job_col),
    .job_src(job_src), .job_idx(job_idx), .job_hl(job_hl), .txt_we(txt_we), .txt_waddr(txt_waddr), .txt_wdata(txt_wdata));

  // button -> selection
  logic short_press; logic [1:0] sel;
  button_debounce #(.CLK_HZ(SYS_CLK_HZ), .DEBOUNCE_MS(BTN_DEBOUNCE_MS), .LONG_MS(BTN_LONG_MS), .ACTIVE_LOW(1)) u_btn
    (.clk(sys_clk), .rst_n(rst_n), .btn(btn_n), .pressed(pressed), .short_press(short_press), .long_press(long_press));
  always_ff @(posedge sys_clk) begin
    if (!rst_n) sel <= 2'd0;
    else if (short_press) sel <= (sel == 2'd2) ? 2'd0 : sel + 1'b1;
  end

  // ui_demo draws the screen once on the rising edge of init_done, then redraws the list on each short press
  logic init_done_d;
  always_ff @(posedge sys_clk) begin
    if (!rst_n) init_done_d <= 1'b0;
    else        init_done_d <= init_done;
  end
  ui_demo #(.COLS(COLS), .LIST_COL(COLS - 8), .TEST_COL(TEST_COL)) u_demo (.clk(sys_clk), .rst_n(rst_n), .start(init_done && !init_done_d),
    .sel_change(short_press), .sel(sel), .job_valid(job_valid), .job_ready(job_ready), .job_row(job_row), .job_col(job_col),
    .job_src(job_src), .job_idx(job_idx), .job_hl(job_hl));
endmodule
