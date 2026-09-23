`timescale 1ns/1ps
module tb_st7789_spi_master;
  localparam int CLK_DIV = 2; // SCLK = 100 MHz / 4 = 25 MHz -> period 40 ns
  localparam realtime T_HALF = CLK_DIV * 10.0;  // SCLK half period (ns)
  localparam realtime T_SCLK = 2 * T_HALF;      // SCLK period (ns)
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;
  logic cs_req = 0, tx_valid = 0, tx_ready, tx_dc = 0, busy;
  logic [7:0] tx_data = 0;
  logic sclk, mosi, cs_n, dcx;

  st7789_spi_master #(.CLK_DIV(CLK_DIV)) dut (.clk(clk), .rst_n(rst_n), .cs_req(cs_req),
    .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc), .busy(busy),
    .sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dcx(dcx));

  // bit-level monitor (what the panel sees)
  logic [7:0] rx_byte; int rx_bits = 0; realtime t_last_edge = 0, t_cs_fall = 0;
  realtime t_last_fall = 0, t_mosi = 0, t_byte_first_edge = 0, t_prev_edge = 0;
  logic first_bit = 0;
  logic [7:0] rx_q[$]; logic rx_dc_q[$]; realtime byte_span_q[$];
  always @(negedge cs_n) begin t_cs_fall = $realtime; rx_bits = 0; end
  always @(mosi) t_mosi = $realtime;                      // time of the last MOSI change
  always @(negedge sclk) if (!cs_n) begin
    t_last_fall = $realtime;
    if ($realtime - t_last_edge != T_HALF) $fatal(1, "SCLK high time %0t, expected %0t", $realtime - t_last_edge, T_HALF);
  end
  always @(posedge sclk) if (!cs_n) begin
    if (rx_bits == 0 && t_cs_fall != 0 && $realtime - t_cs_fall < 15.0) $fatal(1, "tCSS violated");
    if (rx_bits > 0 && $realtime - t_last_edge < 39.9) $fatal(1, "SCLK period too short");
    if (rx_bits > 0 && $realtime - t_last_edge != T_SCLK)
      $fatal(1, "SCLK period %0t, expected %0t", $realtime - t_last_edge, T_SCLK);
    first_bit = (rx_bits == 0);
    if (first_bit) t_byte_first_edge = $realtime;
    t_prev_edge = t_last_edge;
    t_last_edge = $realtime;
    rx_byte = {rx_byte[6:0], mosi};
    rx_bits++;
    if (rx_bits == 8) begin
      rx_q.push_back(rx_byte); rx_dc_q.push_back(dcx);
      byte_span_q.push_back($realtime - t_byte_first_edge);
      rx_bits = 0;
    end
  end
  // MOSI may only change on the SCLK falling edge (bits 1..7) or, for bit 0, before the byte's first
  // rising edge with at least half a period of setup. Checked 1 ns after the rising edge so that a
  // MOSI change in the same time step as the rising edge is already recorded in t_mosi (no race).
  always @(posedge sclk) begin
    #1;
    if (!cs_n) begin
      if (!first_bit && t_mosi > t_prev_edge && t_mosi != t_last_fall)
        $fatal(1, "MOSI changed at %0t, not on the SCLK falling edge %0t", t_mosi, t_last_fall);
      if (first_bit && t_last_edge - t_mosi < T_HALF)
        $fatal(1, "MOSI setup before first rising edge %0t, expected >= %0t", t_last_edge - t_mosi, T_HALF);
    end
  end
  // CS must stay low for the whole byte, even if cs_req was dropped in the clock the byte was accepted
  always @(posedge clk) if (busy && cs_n) $fatal(1, "CS released while a byte is shifting");
  // dcx must not change while a byte is on the wire
  always @(dcx) if (rx_bits != 0) $fatal(1, "DCX changed mid-byte");

  // Any SCLK edge while deselected is an error; counted so the deselect test can check for none.
  int sclk_edges = 0, edges0 = 0; always @(sclk) sclk_edges++;

  // Second DUT with CLK_DIV=1 (DIV_MAX=0 path): SCLK = clk/2 -> 20 ns period, 10 ns high.
  logic cs_req1 = 0, tx_valid1 = 0, tx_ready1, busy1, sclk1, mosi1, cs_n1, dcx1;
  logic [7:0] tx_data1 = 0;
  st7789_spi_master #(.CLK_DIV(1)) dut1 (.clk(clk), .rst_n(rst_n), .cs_req(cs_req1),
    .tx_valid(tx_valid1), .tx_ready(tx_ready1), .tx_data(tx_data1), .tx_dc(1'b0), .busy(busy1),
    .sclk(sclk1), .mosi(mosi1), .cs_n(cs_n1), .dcx(dcx1));
  logic [7:0] rx_byte1; int rx_bits1 = 0; realtime t_rise1 = 0; logic [7:0] rx_q1[$];
  always @(negedge sclk1) if (!cs_n1 && $realtime - t_rise1 != 10.0)
    $fatal(1, "CLK_DIV=1: SCLK high time %0t, expected 10 ns", $realtime - t_rise1);
  always @(posedge sclk1) if (!cs_n1) begin
    if (rx_bits1 > 0 && $realtime - t_rise1 != 20.0)
      $fatal(1, "CLK_DIV=1: SCLK period %0t, expected 20 ns", $realtime - t_rise1);
    t_rise1 = $realtime;
    rx_byte1 = {rx_byte1[6:0], mosi1};
    rx_bits1++;
    if (rx_bits1 == 8) begin rx_q1.push_back(rx_byte1); rx_bits1 = 0; end
  end

  // Sample tx_ready at the falling edge (signals stable); the following rising edge is the accept.
  task send(input logic [7:0] b, input logic dc);
    tx_data = b; tx_dc = dc; tx_valid = 1;
    forever begin @(negedge clk); if (tx_ready) break; end
    @(posedge clk); #1 tx_valid = 0;
  endtask
  // Same as send, but cs_req is dropped in the very clock the byte is accepted.
  task send_and_drop_cs(input logic [7:0] b, input logic dc);
    tx_data = b; tx_dc = dc; tx_valid = 1;
    forever begin @(negedge clk); if (tx_ready) begin cs_req = 0; break; end end
    @(posedge clk); #1 tx_valid = 0;
  endtask

  initial begin
    repeat (3) @(posedge clk); rst_n = 1;
    if (cs_n !== 1'b1 || sclk !== 1'b0) $fatal(1, "idle levels wrong");
    if (tx_ready) $fatal(1, "ready without CS");
    cs_req = 1;
    send(8'h2C, 0);
    send(8'hA5, 1);
    send(8'h5A, 1);
    while (busy) @(posedge clk);
    if (sclk !== 1'b0) $fatal(1, "SCLK not idle low after byte");
    repeat (2) @(posedge clk); cs_req = 0; repeat (4) @(posedge clk);
    if (cs_n !== 1'b1) $fatal(1, "CS not released");
    if (rx_q.size() != 3) $fatal(1, "got %0d bytes", rx_q.size());
    if (rx_q[0] !== 8'h2C || rx_dc_q[0] !== 0) $fatal(1, "byte0 %h dc %b", rx_q[0], rx_dc_q[0]);
    if (rx_q[1] !== 8'hA5 || rx_dc_q[1] !== 1) $fatal(1, "byte1 %h dc %b", rx_q[1], rx_dc_q[1]);
    if (rx_q[2] !== 8'h5A || rx_dc_q[2] !== 1) $fatal(1, "byte2 %h dc %b", rx_q[2], rx_dc_q[2]);
    // Second transaction: cs_req falls in the clock the byte is accepted. CS must be held low until
    // the byte completes (checked by the busy && cs_n monitor) and released right after.
    cs_req = 1;
    send_and_drop_cs(8'h3C, 1);
    if (!busy) $fatal(1, "byte not accepted");
    while (busy) @(posedge clk);
    if (cs_n !== 1'b0) $fatal(1, "CS not held until byte end");
    @(negedge clk);
    if (cs_n !== 1'b1) $fatal(1, "CS not released after byte");
    // Deselected (cs_req low, cs_n high): a pending byte must not be accepted and SCLK must not move.
    // Starts in the very clock after cs_n rose, while the tCSS counter is still saturated, so that a
    // tx_ready that does not look at cs_n would accept the byte.
    edges0 = sclk_edges;
    tx_data = 8'hFF; tx_dc = 1; tx_valid = 1;
    repeat (10) begin
      if (tx_ready !== 1'b0) $fatal(1, "tx_ready asserted while deselected");
      if (busy !== 1'b0) $fatal(1, "busy asserted while deselected");
      @(negedge clk);
    end
    if (sclk_edges != edges0) $fatal(1, "SCLK toggled while deselected");
    if (cs_n !== 1'b1) $fatal(1, "CS fell while deselected");
    @(posedge clk); #1 tx_valid = 0;
    if (rx_q.size() != 4) $fatal(1, "got %0d bytes, expected 4", rx_q.size());
    if (rx_q[3] !== 8'h3C || rx_dc_q[3] !== 1) $fatal(1, "byte3 %h dc %b", rx_q[3], rx_dc_q[3]);
    // 8 SCLK periods of exactly T_SCLK per byte: 1st to 8th rising edge = 7 periods (each period and
    // the high time are checked edge by edge above).
    for (int i = 0; i < 4; i++)
      if (byte_span_q[i] != 7 * T_SCLK)
        $fatal(1, "byte%0d spans %0t from first to last rising edge, expected %0t", i, byte_span_q[i], 7 * T_SCLK);
    // CLK_DIV=1 DUT: one byte at SCLK = clk/2.
    cs_req1 = 1; tx_data1 = 8'h96; tx_valid1 = 1;
    forever begin @(negedge clk); if (tx_ready1) break; end
    @(posedge clk); #1 tx_valid1 = 0;
    while (busy1) @(posedge clk);
    if (sclk1 !== 1'b0) $fatal(1, "CLK_DIV=1: SCLK not idle low after byte");
    repeat (2) @(posedge clk); cs_req1 = 0; repeat (2) @(posedge clk);
    if (cs_n1 !== 1'b1) $fatal(1, "CLK_DIV=1: CS not released");
    if (rx_q1.size() != 1 || rx_q1[0] !== 8'h96) $fatal(1, "CLK_DIV=1: got %0d bytes, byte0 %h", rx_q1.size(), rx_q1[0]);
    $display("PASS tb_st7789_spi_master");
    $finish;
  end
endmodule
