`timescale 1ns / 1ps

module led (
     input logic clk,
     input logic rst,
     output logic led1, led2, led3, led4
    );

    logic [3:0] counter = 0;

    assign led1 = counter[0];
    assign led2 = counter[1];
    assign led3 = counter[2];
    assign led4 = counter[3];

    always_ff @( posedge clk, posedge rst) begin
        if (rst) begin
            counter <= 0;
        end else begin
            if (counter == 15) 
                counter <= 0;
            else
                counter <= counter + 1;
        end
    end
    
endmodule
