`timescale 1ns / 1ps

module latch (
     input logic sel,
     input logic a,
     input logic b,
     output logic c
    );
   
   always_comb begin 
      if (sel) 
         c = a;
   end
endmodule

