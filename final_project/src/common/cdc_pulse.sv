// Single-cycle pulse crossing via toggle flop. Source pulses must be spaced by
// at least ~3 destination clock periods; otherwise pulses merge.
// Reset ordering: both domains must be out of reset before the first pulse_src; a dst reset
// released while toggle_src is already 1 produces one spurious pulse_dst.
module cdc_pulse (
  input  logic clk_src,
  input  logic rst_src_n,
  input  logic pulse_src,
  input  logic clk_dst,
  input  logic rst_dst_n,
  output logic pulse_dst
);
  logic toggle_src;
  always_ff @(posedge clk_src) begin
    if (!rst_src_n)     toggle_src <= 1'b0;
    else if (pulse_src) toggle_src <= ~toggle_src;
  end

  (* ASYNC_REG = "TRUE" *) logic [2:0] sync_dst;
  always_ff @(posedge clk_dst) begin
    if (!rst_dst_n) sync_dst <= '0;
    else            sync_dst <= {sync_dst[1:0], toggle_src};
  end
  assign pulse_dst = sync_dst[2] ^ sync_dst[1];
endmodule
