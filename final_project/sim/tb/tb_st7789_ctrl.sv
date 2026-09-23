`timescale 1ns/1ps
module tb_st7789_ctrl;
  localparam int W = 32, H = 24, CLK_DIV = 1;  // small window keeps the sim short; 50 MHz SCLK
  localparam int RESET_LOW_TICKS = 1, RESET_WAIT_TICKS = 120;  // SIM_FAST: ticks are microseconds
  localparam int PIX_LAT = 4;                  // DUT parameter and the address-hold monitor below
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;

  logic cs_req, tx_valid, tx_ready, tx_dc, busy;
  logic [7:0] tx_data;
  logic sclk, mosi, cs_n, dcx, resx_n;
  logic [4:0] pix_x; logic [4:0] pix_y; logic [15:0] pix_data;
  logic init_done, frame_done;

  st7789_ctrl #(.CLK_HZ(100_000_000), .SIM_FAST(1), .WIDTH(W), .HEIGHT(H), .PIX_LAT(PIX_LAT), .CLK_DIV(CLK_DIV),
                .RESET_LOW_TICKS(RESET_LOW_TICKS), .RESET_WAIT_TICKS(RESET_WAIT_TICKS),
                .INIT_ROM_FILE("mem/st7789_init.mem")) dut (
    .clk(clk), .rst_n(rst_n),
    .cs_req(cs_req), .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc), .spi_busy(busy),
    .lcd_resx_n(resx_n), .pix_x(pix_x), .pix_y(pix_y), .pix_data(pix_data),
    .init_done(init_done), .frame_done(frame_done));

  st7789_spi_master #(.CLK_DIV(CLK_DIV)) u_spi (.clk(clk), .rst_n(rst_n), .cs_req(cs_req),
    .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc), .busy(busy),
    .sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dcx(dcx));

  // scaled limits: SIM_FAST turns ms into us; the model gets the same scale (ns)
  st7789v_slave_model #(.MIN_SCLK_PERIOD_NS(19.9), .RESET_TO_CMD_NS(5_000.0), .RESET_TO_SLPOUT_NS(120_000.0), .SLPOUT_TO_CMD_NS(5_000.0), .SWRESET_TO_CMD_NS(5_000.0))
    panel (.sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dcx(dcx), .resx_n(resx_n));

  // pixel source with 3-cycle latency: value encodes the address
  function automatic logic [15:0] pat(input int x, input int y); return {x[7:0], y[7:0]}; endfunction
  logic [15:0] d1, d2;
  always_ff @(posedge clk) begin d1 <= pat(pix_x, pix_y); d2 <= d1; pix_data <= d2; end

  // ---- monitors
  int frames = 0;
  logic frame_done_q = 0;
  always @(posedge clk) begin
    if (frame_done) frames++;
    if (frame_done && frame_done_q) $fatal(1, "frame_done wider than one clock");
    if (frame_done && cs_n !== 1'b1) $fatal(1, "frame_done while CS is still low");
    frame_done_q <= frame_done;
  end

  // reset timing: RESX low >= RESET_LOW_TICKS us after rst_n release, first SPI byte >= RESET_WAIT_TICKS us after RESX release
  realtime t_rst_rel = -1, t_resx_rise = -1, t_first_cs = -1, t_cs_rise = -1;
  always @(posedge resx_n) t_resx_rise = $realtime;
  always @(negedge cs_n) begin
    if (t_first_cs < 0) t_first_cs = $realtime;
    if (init_done && t_cs_rise >= 0 && $realtime - t_cs_rise < 40.0)
      $fatal(1, "CS high between transactions only %0t (tCHW >= 40 ns)", $realtime - t_cs_rise);
  end
  int cs_rises_after_init = 0;
  always @(posedge cs_n) begin t_cs_rise = $realtime; if (init_done) cs_rises_after_init++; end

  // controller side of the pixel contract: the fetch address must stay stable >= PIX_LAT clocks
  logic [4:0] px_q = 0, py_q = 0; int addr_age = 0, min_age = 1 << 30;   // addr_age at a change edge = clocks held - 1
  always @(posedge clk) begin
    if (px_q !== pix_x || py_q !== pix_y) begin
      if (init_done && addr_age < PIX_LAT) $fatal(1, "pixel address changed after %0d clocks, PIX_LAT is %0d", addr_age, PIX_LAT);
      if (init_done && addr_age < min_age) min_age = addr_age;
      addr_age <= 0;
    end else addr_age <= addr_age + 1;
    px_q <= pix_x; py_q <= pix_y;
  end

  initial begin
    repeat (3) @(posedge clk); rst_n <= 1; t_rst_rel = $realtime;
    wait (init_done);
    if (!panel.sleep_out || !panel.disp_on) $fatal(1, "panel not initialised: slpout=%b dispon=%b", panel.sleep_out, panel.disp_on);
    if (panel.colmod !== 8'h55) $fatal(1, "COLMOD %h", panel.colmod);
    if (panel.madctl !== 8'h60) $fatal(1, "MADCTL %h", panel.madctl);
    if (t_resx_rise < 0 || t_first_cs < 0) $fatal(1, "reset/CS never seen");
    if (t_resx_rise - t_rst_rel < RESET_LOW_TICKS * 1000.0)
      $fatal(1, "RESX low only %0t, expected >= %0d us", t_resx_rise - t_rst_rel, RESET_LOW_TICKS);
    if (t_first_cs - t_resx_rise < RESET_WAIT_TICKS * 1000.0)
      $fatal(1, "first command %0t after RESX release, expected >= %0d us", t_first_cs - t_resx_rise, RESET_WAIT_TICKS);
    $display("RESX low %0.1f us, first command %0.1f us after RESX release", (t_resx_rise - t_rst_rel) / 1000.0, (t_first_cs - t_resx_rise) / 1000.0);
    wait (frames == 2);
    $display("frame_done pulses %0d, RAMWR count %0d, CS releases after init %0d, last CS high gap %0t, min clocks between address changes %0d", frames, panel.n_frames, cs_rises_after_init, $realtime - t_cs_rise, min_age + 1);
    // frame_done follows the CS release of a frame; the next RAMWR (which bumps n_frames) is ~11 bytes later
    if (panel.n_frames != frames) $fatal(1, "frame_done pulses %0d, RAMWR count %0d", frames, panel.n_frames);
    if (cs_rises_after_init < 2) $fatal(1, "CS released only %0d times after init, expected one per frame", cs_rises_after_init);
    if (panel.xs != 0 || panel.xe != W-1 || panel.ys != 0 || panel.ye != H-1) $fatal(1, "window %0d..%0d x %0d..%0d", panel.xs, panel.xe, panel.ys, panel.ye);
    if (panel.n_pixels != W*H) $fatal(1, "pixels per frame %0d", panel.n_pixels);
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
      if (panel.pixel(x, y) !== pat(x, y)) $fatal(1, "pixel (%0d,%0d) = %h expected %h", x, y, panel.pixel(x, y), pat(x, y));
    if (panel.n_errors != 0) $fatal(1, "%0d protocol errors", panel.n_errors);
    panel.dump_ppm("sim/build/tb_st7789_ctrl.ppm");
    $display("PASS tb_st7789_ctrl");
    $finish;
  end
  initial begin #20_000_000; $fatal(1, "timeout"); end
endmodule
