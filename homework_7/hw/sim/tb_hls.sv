

`timescale 1ns / 1ps

module tb_hls;

    localparam N_SAMPLES = 64;
    localparam WINDOW = 8;

    reg clk = 0;
    reg rst = 0;
    reg start = 0;  
    reg ap_done, ap_idle, ap_ready;  
    reg [5:0] in_data_address0, out_data_address0;
    reg [31:0] in_data_q0, out_data_d0;
    reg in_data_ce0, out_data_ce0, out_data_we0;
    
    always #5 clk = ~clk;  // 100 Mhz

     moving_max  dut(
        .ap_clk(clk),
        .ap_rst(rst),
        .ap_start(start),
        .ap_done(ap_done),
        .ap_idle(ap_idle),
        .ap_ready(ap_ready),
        .in_data_address0(in_data_address0),
        .in_data_ce0(in_data_ce0),
        .in_data_q0(in_data_q0),
        .out_data_address0(out_data_address0),
        .out_data_ce0(out_data_ce0),
        .out_data_we0(out_data_we0),
        .out_data_d0(out_data_d0)
);;
// input   ap_clk;
// input   ap_rst;
// input   ap_start;
// output   ap_done;
// output   ap_idle;
// output   ap_ready;
// output  [5:0] in_data_address0;
// output   in_data_ce0;
// input  [31:0] in_data_q0;
// output  [5:0] out_data_address0;
// output   out_data_ce0;
// output   out_data_we0;
// output  [31:0] out_data_d0;

    reg [31:0] mem_in  [0:N_SAMPLES-1];
    reg [31:0] mem_out [0:N_SAMPLES-1];
    reg [31:0] mem_target [0:N_SAMPLES-1];


    always_ff @(posedge clk) begin
        if (in_data_ce0) begin
            in_data_q0 <= mem_in[in_data_address0];
        end

        if (out_data_ce0 && out_data_we0) begin
            mem_out[out_data_address0] <= out_data_d0;
        end
    end
    
     int t, n, i;

    task calculate_out;
        rst = 1;
        @(negedge clk);
        rst = 0;
        start = 1;
        while (!ap_ready) begin
            @(negedge clk);
        end

        start = 0;

        while (!ap_done) begin
             @(negedge clk);
        end
    endtask;


    task calculate_target;
        reg [31:0]max;
        begin
            for (n = 0; n < N_SAMPLES; n = n + 1) begin
                max = mem_in[n];
                for (i = n - 1; i >= 0 && n - i < WINDOW; i = i - 1) begin
                    if (mem_in[i] > max) 
                        max = mem_in[i];
                end
                mem_target[n] = max;
            end
        end
    endtask;


    reg [31:0] seed;
   

    initial begin
        seed   = 32'd12345;

        for (t = 0; t < 3; t = t + 1) begin
            for (n = 0; n < N_SAMPLES; n = n + 1) begin
                seed = seed * 32'd1103515245 + 32'd12345;
                mem_in[n]  = (seed >> 16) % 1000;
                mem_out[n] = 32'hDEADBEEF;
            end
            calculate_target;
            calculate_out;
            
            repeat (3) @(negedge clk);
            for (n = 0; n < N_SAMPLES; n = n + 1) begin
                if (mem_out[n] !== mem_target[n]) begin
                    $error("MISMATCH: call %0d, sample %0d: DUT=%0d, ref=%0d",
                                 t, n, mem_out[n], mem_target[n]);
                end
            end
        end
        $finish;
    end
    

   initial begin
       #(20000);
       $error("TIMEOUT");
       $finish;
   end

endmodule