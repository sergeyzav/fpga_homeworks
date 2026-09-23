`include "common/defs.svh"
// Dual-clock AXI4-Stream FIFO with Gray-code pointers.
// Depth = 2**DEPTH_LOG2 words. s_overflow goes sticky-high (cleared by s_rst_n) when a word is
// offered (s_tvalid) while the FIFO is full. For a free-running source that ignores s_tready
// (e.g. the IQ sample stream) this means the word was dropped. A source that honours s_tready
// and holds s_tvalid while waiting sets the flag too, so it is only meaningful for
// non-stalling sources.
//
// Reset contract: s_rst_n and m_rst_n must be asserted together, derived from one reset source
// (e.g. one rst_sync per clock fed by the same request), each held for at least 2 cycles of its
// own clock plus the synchroniser depth. Resetting one domain alone leaves the write and read
// pointers inconsistent and the FIFO emits stale data.
module axis_async_fifo #(
  parameter int WIDTH      = 32,
  parameter int DEPTH_LOG2 = 6
) (
  input  logic             s_clk,
  input  logic             s_rst_n,
  input  logic [WIDTH-1:0] s_tdata,
  input  logic             s_tvalid,
  output logic             s_tready,
  output logic             s_overflow,

  input  logic             m_clk,
  input  logic             m_rst_n,
  output logic [WIDTH-1:0] m_tdata,
  output logic             m_tvalid,
  input  logic             m_tready
);
  localparam int AW = DEPTH_LOG2;

  `PARAM_CHECK(g_chk_depth, DEPTH_LOG2 < 2, ("axis_async_fifo: DEPTH_LOG2 must be >= 2"))

  (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:(1<<AW)-1];

  // ---------------- write side ----------------
  logic [AW:0] wr_bin, wr_gray, rd_gray_in_wr;
  logic [AW:0] rd_bin, rd_gray, wr_gray_in_rd;
  wire         wr_fire = s_tvalid && s_tready;

  function automatic logic [AW:0] bin2gray(input logic [AW:0] b); return b ^ (b >> 1); endfunction

  always_ff @(posedge s_clk) begin
    if (!s_rst_n) begin
      wr_bin <= '0; wr_gray <= '0; s_overflow <= 1'b0;
    end else begin
      if (wr_fire) begin
        mem[wr_bin[AW-1:0]] <= s_tdata;
        wr_bin  <= wr_bin + 1'b1;
        wr_gray <= bin2gray(wr_bin + 1'b1);
      end
      if (s_tvalid && !s_tready) s_overflow <= 1'b1;
    end
  end

  // Multi-bit cdc_sync is valid here only because the pointer is Gray-coded: it changes one bit
  // per source clock edge, so a stale sample is a valid (older) pointer, never a mixed one.
  // The rd_gray -> rd_gray_in_wr path needs set_max_delay -datapath_only (one source clock
  // period) in constr/timing.xdc, not a false path.
  cdc_sync #(.WIDTH(AW+1)) u_rd2wr (.clk(s_clk), .d(rd_gray), .q(rd_gray_in_wr));
  // full when pointers differ only in the two MSBs
  wire full = (wr_gray == {~rd_gray_in_wr[AW:AW-1], rd_gray_in_wr[AW-2:0]});
  assign s_tready = s_rst_n && !full;

  // ---------------- read side ----------------
  // Same Gray-code argument and set_max_delay -datapath_only constraint for wr_gray -> wr_gray_in_rd.
  cdc_sync #(.WIDTH(AW+1)) u_wr2rd (.clk(m_clk), .d(wr_gray), .q(wr_gray_in_rd));
  wire empty = (rd_gray == wr_gray_in_rd);

  // registered output with one-word skid: m_tvalid high while output register holds data.
  // m_tdata is not reset (don't-care while m_tvalid=0) so it can absorb into the BRAM output register.
  always_ff @(posedge m_clk) begin
    if (!m_rst_n) begin
      rd_bin <= '0; rd_gray <= '0; m_tvalid <= 1'b0;
    end else begin
      if (!m_tvalid || m_tready) begin
        if (!empty) begin
          m_tdata  <= mem[rd_bin[AW-1:0]];
          m_tvalid <= 1'b1;
          rd_bin   <= rd_bin + 1'b1;
          rd_gray  <= bin2gray(rd_bin + 1'b1);
        end else begin
          m_tvalid <= 1'b0;
        end
      end
    end
  end
endmodule
