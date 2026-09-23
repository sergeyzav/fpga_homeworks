`timescale 1ns/1ps
module tb_axis_async_fifo;
  localparam int N          = 2000;  // words per phase
  localparam int DEPTH_LOG2 = 4;
  localparam int STALL      = 100;   // reader stall cycles at start of phase 2 (fills the FIFO)
  logic s_clk = 0, m_clk = 0, s_rst_n = 0, m_rst_n = 0;
  always #6.25 s_clk = ~s_clk;  // 80 MHz writer
  always #5    m_clk = ~m_clk;  // 100 MHz reader

  logic [31:0] s_tdata, m_tdata;
  logic s_tvalid, s_tready, m_tvalid, m_tready, s_overflow;

  axis_async_fifo #(.WIDTH(32), .DEPTH_LOG2(DEPTH_LOG2)) dut (
    .s_clk(s_clk), .s_rst_n(s_rst_n), .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tready(s_tready), .s_overflow(s_overflow),
    .m_clk(m_clk), .m_rst_n(m_rst_n), .m_tdata(m_tdata), .m_tvalid(m_tvalid), .m_tready(m_tready));

  // writer: sequential words 0..limit-1, 50 % offered, honours s_tready
  int wr_i = 0, limit = N, nxt;
  always @(posedge s_clk) begin
    if (!s_rst_n) begin s_tvalid <= 0; s_tdata <= 0; end
    else begin
      nxt = wr_i + ((s_tvalid && s_tready) ? 1 : 0);
      wr_i <= nxt;
      if (!s_tvalid || s_tready) begin
        s_tvalid <= (nxt < limit) && ($urandom_range(0, 3) > 1);
        s_tdata  <= nxt;
      end
    end
  end
  // reader: random stalls, checks order. While `stall` > 0 the reader is held off so the FIFO
  // fills and the writer sees back-pressure (exercises the full / Gray-pointer compare path).
  int rd_i = 0, stall = 0;
  always @(posedge m_clk) begin
    if (stall > 0) begin stall <= stall - 1; m_tready <= 0; end
    else m_tready <= ($urandom_range(0, 2) != 0);
    if (m_tvalid && m_tready) begin
      if (m_tdata !== rd_i) $fatal(1, "order error: got %0d expected %0d", m_tdata, rd_i);
      rd_i <= rd_i + 1;
    end
  end

  // back-pressure must be observed in phase 2, otherwise the full path is untested
  logic saw_backpressure = 0;
  always @(posedge s_clk) if (s_rst_n && s_tvalid && !s_tready) saw_backpressure <= 1;

  // occupancy = accepted - consumed; the FIFO holds 2**DEPTH_LOG2 words plus the output skid word
  int max_occ = 0;
  always @(posedge m_clk) if (wr_i - rd_i > max_occ) max_occ = wr_i - rd_i;

  initial begin
    repeat (4) @(posedge s_clk); s_rst_n = 1; m_rst_n = 1;

    // ---- phase 1: reader faster than writer on average, FIFO never fills ----
    wait (rd_i == N);
    repeat (10) @(posedge m_clk);
    if (saw_backpressure) $fatal(1, "phase 1: unexpected back-pressure");
    if (s_overflow) $fatal(1, "overflow flagged although s_tready respected");
    if (m_tvalid) $fatal(1, "extra data in FIFO");

    // ---- phase 2: stall the reader so the FIFO fills and wraps under back-pressure ----
    @(posedge m_clk); stall <= STALL; limit <= 2*N;
    wait (rd_i == 2*N);
    repeat (10) @(posedge m_clk);
    if (!saw_backpressure) $fatal(1, "phase 2: FIFO never filled, back-pressure path untested");
    if (!s_overflow) $fatal(1, "phase 2: s_overflow not flagged although a word was offered while full");
    if (m_tvalid) $fatal(1, "phase 2: extra data in FIFO");
    if (max_occ != (1 << DEPTH_LOG2) + 1)
      $fatal(1, "phase 2: max occupancy %0d, expected %0d", max_occ, (1 << DEPTH_LOG2) + 1);

    // ---- both resets asserted together clear the sticky overflow flag and the output register ----
    @(posedge s_clk); s_rst_n <= 0; m_rst_n <= 0;
    repeat (5) @(posedge s_clk);            // 62.5 ns: 5 s_clk / 6 m_clk cycles
    s_rst_n <= 1; m_rst_n <= 1;
    repeat (4) @(posedge m_clk); #1;
    if (s_overflow) $fatal(1, "s_overflow not cleared by reset");
    if (m_tvalid) $fatal(1, "m_tvalid not cleared by reset");

    $display("PASS tb_axis_async_fifo");
    $finish;
  end

  initial begin #200000; $fatal(1, "timeout"); end
endmodule
