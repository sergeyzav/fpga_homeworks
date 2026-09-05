`timescale 1ns / 1ps

module counter (
     input wire clk,
     input wire rst,
     input wire en,
     input wire load,
     input wire [3:0] data_in,
     input wire up_down,
     output reg [3:0] count
    );
    always_ff @(posedge clk, posedge rst) begin
        count <= count;
        
        if (rst) begin
            count <= 0;
        end else begin
            if (load) 
                count <= data_in;
            else begin
                if (en) begin
                    if (up_down)
                        count <= count + 1;
                    else 
                        count <= count - 1;
                end
            end
        end
    end
    
endmodule
