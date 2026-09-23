`timescale 1ns/1ps
module tb_framebuffer;
  localparam int W = 320, H = 240;
  localparam int BARS_END = (H * 2) / 3;   // first gradient row (160)
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;
  logic wr_en; logic [8:0] wr_x, rd_x = 0; logic [7:0] wr_y, rd_y = 0; logic [15:0] wr_data, rd_data;
  logic start = 0, busy, done;

  framebuffer #(.WIDTH(W), .HEIGHT(H)) fb (.clk(clk), .wr_en(wr_en), .wr_x(wr_x), .wr_y(wr_y), .wr_data(wr_data),
                                          .rd_x(rd_x), .rd_y(rd_y), .rd_data(rd_data));
  test_pattern_gen #(.WIDTH(W), .HEIGHT(H)) gen (.clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
                                                .wr_en(wr_en), .wr_x(wr_x), .wr_y(wr_y), .wr_data(wr_data));

  // Monitor: count write strobes; busy may only fall in the cycle done pulses; done is a single-cycle pulse.
  int n_wr = 0, n_done = 0; logic busy_q = 0;
  always @(posedge clk) if (rst_n) begin
    if (wr_en) n_wr++;
    if (done)  n_done++;
    if (busy_q && !busy && !done) $fatal(1, "busy fell without done");
    if (done && busy)             $fatal(1, "done asserted while busy still high");
    busy_q <= busy;
  end

  task automatic expect_px(input int x, input int y, input logic [15:0] v);
    rd_x <= x[8:0]; rd_y <= y[7:0]; repeat (2) @(posedge clk); #1;
    if (rd_data !== v) $fatal(1, "(%0d,%0d) = %h expected %h", x, y, rd_data, v);
  endtask

  initial begin
    repeat (3) @(posedge clk); rst_n = 1;
    @(posedge clk); #1;
    if (busy !== 1'b0 || wr_en !== 1'b0) $fatal(1, "busy/wr_en not idle after reset");
    @(posedge clk); start <= 1; @(posedge clk); start <= 0; #1;
    if (busy !== 1'b1) $fatal(1, "busy not high one cycle after start");
    repeat (1000) @(posedge clk); #1;
    if (busy !== 1'b1) $fatal(1, "busy dropped during fill");
    wait (done); @(posedge clk); #1;         // last write commits on the edge after done
    if (busy !== 1'b0)  $fatal(1, "busy still high after done");
    if (wr_en !== 1'b0) $fatal(1, "wr_en still high one cycle after done");
    if (n_done != 1)    $fatal(1, "done pulsed %0d times, expected 1", n_done);
    if (n_wr != W * H)  $fatal(1, "%0d write strobes, expected %0d", n_wr, W * H);
    expect_px(0,   0,   16'hFFFF);   // border white: corners and the midpoint of each side
    expect_px(319, 239, 16'hFFFF);
    expect_px(0,   120, 16'hFFFF);   // left
    expect_px(319, 120, 16'hFFFF);   // right
    expect_px(160, 0,   16'hFFFF);   // top
    expect_px(160, 239, 16'hFFFF);   // bottom
    expect_px(20,  50,  16'hFFFF);   // bar 0 white
    expect_px(60,  50,  16'hFFE0);   // bar 1 yellow
    expect_px(100, 50,  16'h07FF);   // bar 2 cyan
    expect_px(140, 50,  16'h07E0);   // bar 3 green
    expect_px(180, 50,  16'hF81F);   // bar 4 magenta
    expect_px(220, 50,  16'hF800);   // bar 5 red
    expect_px(260, 50,  16'h001F);   // bar 6 blue
    expect_px(300, 50,  16'h0000);   // bar 7 black
    // BARS_END boundary: last bar row is BARS_END-1, first gradient row is BARS_END.
    expect_px(20,  BARS_END - 1, 16'hFFFF);  // bar 0 white
    expect_px(20,  BARS_END,     16'h1082);  // x=20: lvl5 = 20*32/320 = 2, lvl6 = 20*64/320 = 4 -> {5'd2,6'd4,5'd2} = 00010_000100_00010
    expect_px(1,   200, 16'h0000);   // gradient: x=1 -> level 0
    expect_px(318, 200, 16'hFFFF);   // gradient: x=318 -> level 31
    expect_px(160, 200, 16'h8410);   // level 16 -> {5'd16,6'd32,5'd16}
    // Read latency is exactly 2 clocks: after a new address, the old value survives one edge and the
    // new value appears after the second.
    expect_px(220, 50, 16'hF800);                       // red, settled
    rd_x <= 9'd260; rd_y <= 8'd50; @(posedge clk); #1;  // blue requested
    if (rd_data !== 16'hF800) $fatal(1, "rd_data changed after 1 clock: %h (latency < 2)", rd_data);
    @(posedge clk); #1;
    if (rd_data !== 16'h001F) $fatal(1, "rd_data not updated after 2 clocks: %h (latency > 2)", rd_data);
    // A second start refills the buffer with the same image.
    @(posedge clk); start <= 1; @(posedge clk); start <= 0;
    wait (done); @(posedge clk); #1;
    if (n_wr != 2 * W * H) $fatal(1, "%0d write strobes after 2 fills, expected %0d", n_wr, 2 * W * H);
    expect_px(100, 50, 16'h07FF);
    $display("PASS tb_framebuffer");
    $finish;
  end
  initial begin #4_000_000; $fatal(1, "timeout"); end
endmodule
