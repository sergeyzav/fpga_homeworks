`timescale 1ns/1ps
// Behavioural ST7789V 4-wire SPI slave. Not synthesisable.
// Timing parameters are REAL datasheet values in ns; TBs using a SIM_FAST controller must pass scaled values.
module st7789v_slave_model #(
  parameter real MIN_SCLK_PERIOD_NS   = 66.0,           // tSCYCW (datasheet Table 6)
  parameter real RESET_TO_CMD_NS      = 5_000_000.0,    // no command within 5 ms of reset release
  parameter real RESET_TO_SLPOUT_NS   = 120_000_000.0,  // SLPOUT not before 120 ms after reset
  parameter real SLPOUT_TO_CMD_NS     = 5_000_000.0,    // 5 ms quiet after SLPOUT
  parameter real SWRESET_TO_CMD_NS    = 5_000_000.0     // 5 ms quiet after SWRESET
) (
  input logic sclk,
  input logic mosi,
  input logic cs_n,
  input logic dcx,
  input logic resx_n
);
  // ---- observable state
  logic [7:0]  madctl = 8'h00, colmod = 8'h66, last_cmd = 8'h00;
  logic [15:0] xs = 0, xe = 16'h00EF, ys = 0, ye = 16'h013F;
  logic        sleep_out = 0, disp_on = 0, inverted = 0;
  int          n_frames = 0, n_pixels = 0, n_errors = 0;   // n_errors is cumulative by design (survives reset)
  logic [15:0] mem     [0:319][0:319];   // [col][page]; only 240 of one dimension is used
  bit          written [0:319][0:319];   // set on each pixel write, cleared by hardware reset

  // ---- protocol decode
  logic [7:0] sh; int nbits = 0;
  logic [15:0] col, page; int pix_phase = 0; logic [7:0] pix_hi;
  int param_idx = 0;
  realtime t_reset_rel = -1e12, t_slpout = -1e12, t_swreset = -1e12, t_edge = -1e12;
  bit have_edge = 0;

  function automatic void err(input string msg);
    n_errors++; $error("st7789v_slave_model: %s (t=%t)", msg, $realtime);
  endfunction

  always @(posedge resx_n) begin
    t_reset_rel = $realtime; t_slpout = -1e12; t_swreset = -1e12;
    sleep_out = 0; disp_on = 0; madctl = 0; colmod = 8'h66; inverted = 0;
    xs = 0; xe = 16'h00EF; ys = 0; ye = 16'h013F; nbits = 0;
    n_frames = 0; n_pixels = 0; last_cmd = 0; pix_phase = 0; param_idx = 0;
    for (int c = 0; c < 320; c++) for (int p = 0; p < 320; p++) written[c][p] = 0;
  end
  always @(negedge cs_n) begin nbits = 0; have_edge = 0; end

  function automatic bit mv(); return madctl[5]; endfunction

  task automatic handle_cmd(input logic [7:0] c);
    if ($realtime - t_reset_rel < RESET_TO_CMD_NS) err($sformatf("command %02h too soon after reset", c));
    if (t_slpout  > -1e11 && $realtime - t_slpout  < SLPOUT_TO_CMD_NS)  err($sformatf("command %02h within SLPOUT quiet time", c));
    if (t_swreset > -1e11 && $realtime - t_swreset < SWRESET_TO_CMD_NS) err($sformatf("command %02h within SWRESET quiet time", c));
    last_cmd = c; param_idx = 0;
    case (c)
      // SWRESET resets the window, keeps MADCTL/COLMOD. not modeled: "SWRESET during sleep-out sequence" rule
      8'h01: begin t_swreset = $realtime; xs = 0; ys = 0; xe = mv() ? 16'h013F : 16'h00EF; ye = mv() ? 16'h00EF : 16'h013F; end
      8'h11: begin if ($realtime - t_reset_rel < RESET_TO_SLPOUT_NS) err("SLPOUT before 120 ms"); sleep_out = 1; t_slpout = $realtime; end
      8'h10: sleep_out = 0;
      8'h20: inverted = 0;
      8'h21: inverted = 1;
      8'h28: disp_on = 0;
      8'h29: disp_on = 1;
      8'h2C: begin col = xs; page = ys; pix_phase = 0; n_frames++; n_pixels = 0; end // RAMWR
      8'h3C: pix_phase = 0;                                                        // WRMEMC continues
      default: ;
    endcase
  endtask

  task automatic handle_data(input logic [7:0] d);
    case (last_cmd)
      8'h36: madctl = d;
      8'h3A: colmod = d;
      8'h2A: case (param_idx) 0: xs[15:8] = d; 1: xs[7:0] = d; 2: xe[15:8] = d; 3: xe[7:0] = d; default: err("CASET extra param"); endcase
      8'h2B: case (param_idx) 0: ys[15:8] = d; 1: ys[7:0] = d; 2: ye[15:8] = d; 3: ye[7:0] = d; default: err("RASET extra param"); endcase
      8'h2C, 8'h3C: begin
        if (pix_phase == 0) begin
          if (colmod[2:0] != 3'b101) err("pixel data with COLMOD not 16 bpp");   // once per pixel
          pix_hi = d; pix_phase = 1;
        end else begin
          pix_phase = 0;
          if (col > xe || page > ye) err("pixel outside window");
          else begin
            mem[col][page] = {pix_hi, d};
            written[col][page] = 1;
            n_pixels++;
            // datasheet 8.12: column increments, wraps to xs and increments page; wraps to ys at ye
            if (col == xe) begin col = xs; page = (page == ye) ? ys : page + 1; end
            else col = col + 1;
          end
        end
      end
      default: ; // parameters of other commands are accepted and ignored
    endcase
    param_idx++;
  endtask

  always @(posedge sclk) if (!cs_n) begin
    if (!resx_n) err("SPI activity while RESX low");   // bit ignored
    else begin
      if (have_edge && $realtime - t_edge < MIN_SCLK_PERIOD_NS - 0.01) err("SCLK period below tSCYCW");
      t_edge = $realtime; have_edge = 1;
      sh = {sh[6:0], mosi};
      nbits++;
      if (nbits == 8) begin
        nbits = 0;
        if (dcx) handle_data(sh); else handle_cmd(sh);   // D/CX sampled on the 8th rising edge
      end
    end
  end

  // ---- image helpers. Logical image = what the host addressed: width = column range, height = page range.
  function automatic int img_w(); return mv() ? 320 : 240; endfunction
  function automatic int img_h(); return mv() ? 240 : 320; endfunction
  function automatic logic [15:0] pixel(input int x, input int y);
    if (!written[x][y]) begin err($sformatf("pixel (%0d,%0d) read before being written", x, y)); return 16'h0000; end
    return mem[x][y];
  endfunction

  task automatic dump_ppm(input string fname);
    int fd; logic [15:0] p; int r, g, b;
    fd = $fopen(fname, "wb");
    if (fd == 0) begin err({"cannot open ", fname}); return; end
    $fwrite(fd, "P6\n%0d %0d\n255\n", img_w(), img_h());
    for (int y = 0; y < img_h(); y++)
      for (int x = 0; x < img_w(); x++) begin
        if (!written[x][y]) begin r = 255; g = 0; b = 255; end   // unwritten pixels are magenta
        else begin
          p = mem[x][y];
          r = {p[15:11], p[15:13]}; g = {p[10:5], p[10:9]}; b = {p[4:0], p[4:2]};
        end
        $fwrite(fd, "%c%c%c", r, g, b);
      end
    $fclose(fd);
    $display("st7789v_slave_model: wrote %s (%0dx%0d)", fname, img_w(), img_h());
  endtask
endmodule
