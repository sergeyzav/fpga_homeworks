`timescale 1ns / 1ps

module decoder #(parameter WIDTH = 4)(
     input logic [$clog2(WIDTH) - 1: 0] address,
     output logic [WIDTH - 1: 0] out
    );

    assign out = 1'b1 << address;
endmodule
