module record_counter #(
  parameter CAPTURE_SAMPLES = 1_000_000,
  parameter HANG_SAMPLES    = 50_000
)(
  input  logic        data_clk,
  input  logic        data_rst,
  input  logic        data_en,
  input  logic        start,
  input  logic        hit,
  output logic        capture_done,
  output logic [31:0] active_samples
);
localparam CAPTURE_DIMENSION = $clog2(CAPTURE_SAMPLES + 1);
localparam HANG_DIMENSION = $clog2(HANG_SAMPLES);

logic hang_exceeded;

logic [CAPTURE_DIMENSION-1:0] capture_counter;
logic [HANG_DIMENSION-1:0] hang_counter;

assign capture_done = data_en && (capture_counter == CAPTURE_SAMPLES - 1);

always_ff @(posedge data_clk) begin
    if (data_rst || start) 
        capture_counter <= 0;
    else if (data_en) 
        if (capture_counter <= CAPTURE_SAMPLES - 1) 
            capture_counter <= capture_counter + 1; 
end

always_ff @(posedge data_clk) begin
    if (data_rst || start) begin
        active_samples <= 0;
        hang_counter <= 0;
        hang_exceeded <= 0;
    end else if (data_en && !hang_exceeded) begin
        active_samples <= capture_counter + 1; 
        if (hit)
          hang_counter <= 0;
        else if (hang_counter < HANG_SAMPLES - 1) 
          hang_counter <= hang_counter + 1;
        else 
          hang_exceeded <= 1;
    end
end

endmodule
