module pythagoras_squares_comb(
    input wire clk,
    input wire rst, 
    input wire [15:0] a,
    input wire [15:0] b,
    output reg [32:0] sum_sq_out
);

    reg [15:0] a_r, b_r;
    
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            a_r <= 16'b0;
            b_r <= 16'b0;
            sum_sq_out <= 33'b0;
        end else begin
            a_r <= a;
            b_r <= b;
            sum_sq_out <= (a_r * a_r) + (b_r * b_r);
        end
   end
endmodule
