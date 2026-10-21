module power_detector #(
  parameter HIT_LEN  = 16
)(
  input  logic        data_clk, 
  input  logic        data_rst,
  input  logic        data_en,          
  input  logic [63:0] data,        
  input  logic [31:0] thresh,      
  input  logic        detector_en,   
  output logic         hit,         
  output logic  [31:0] pwr   
);
    logic [31:0] hit_counter;
    logic signed [11:0] q0, i0, q1, i1;
    logic [22:0] qq0, ii0, qq1, ii1;
    logic [23:0] pwr0, pwr1;

    assign q1 = data[59:48];
    assign i1 = data[43:32];
    assign q0 = data[27:16];
    assign i0 = data[11:0]; // first 12 bits important

    assign hit = (hit_counter >= HIT_LEN);
    assign pwr = pwr1;

    always_ff @(posedge data_clk) begin
        if (data_rst) begin
            qq0 <= 0;
            ii0 <= 0;
            qq1 <= 0;
            ii1 <= 0;
            pwr0 <= 0;
            pwr1 <= 0;
        end else begin
            if (data_en) begin
                qq0 <= q0 * q0;
                ii0 <= i0 * i0;
                qq1 <= q1 * q1;
                ii1 <= i1 * i1;
                pwr0 <= qq0 + ii0;
                pwr1 <= qq1 + ii1;
            end
        end
    end

    always_ff @(posedge data_clk) begin
        if (data_rst || !detector_en) begin
            hit_counter <= 0;
        end else begin
            if (data_en) begin
                if (pwr0 >= thresh && pwr1 >= thresh) begin
                    if (hit_counter < HIT_LEN) begin
                        hit_counter <= hit_counter + 2;
                    end else begin
                        hit_counter <= HIT_LEN;
                    end
                end else if (pwr1 >= thresh) begin
                    hit_counter <=  1;
                end else begin
                    hit_counter <= 0;
                end
            end
        end
    end
endmodule