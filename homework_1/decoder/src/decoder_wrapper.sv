`timescale 1ns / 1ps

module decoder_wrapper (
     input logic [2: 0] addr,
     output logic [3: 0] out4,
     output logic [7: 0] out8
    );
   decoder #(.WIDTH(4)) d4(.address(addr[1:0]), .out(out4));
   decoder #(.WIDTH(8)) d8(.address(addr), .out(out8));
endmodule

