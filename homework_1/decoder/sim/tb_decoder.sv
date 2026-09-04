`timescale 1ns / 1ps

module tb_decoder;

    logic [2:0] address;
    logic [3:0] out4;
    logic [7:0] out8;

    decoder_wrapper dut (
        .addr(address),
        .out4(out4),
        .out8(out8)
    );

    task automatic check_decoder(
        input integer width,
        input logic [2:0] addr_val,
        input logic [7:0] expected_val
    );
        address = addr_val;
        
        #1; // delay

        if (width == 4) begin
            if (out4 != expected_val[3:0])
                $error("Fail 4-bit at addr=%0d, expected=%04b got=%04b", addr_val, expected_val[3:0], out4);
            else
                $display("PASS 4-bit at addr=%0d, out=%04b", addr_val, out4);
        end 
        else if (width == 8) begin
            if (out8 != expected_val)
                $error("Fail 8-bit at addr=%0d, expected=%08b got=%08b", addr_val, expected_val, out8);
            else
                $display("PASS 8-bit at addr=%0d, out=%08b", addr_val, out8);
        end
    endtask

    initial begin
        check_decoder(4, 3'd0, 8'b0000_0001);
        check_decoder(4, 3'd1, 8'b0000_0010);
        check_decoder(4, 3'd2, 8'b0000_0100);
        check_decoder(4, 3'd3, 8'b0000_1000);
        
        check_decoder(8, 3'd0, 8'b0000_0001);
        check_decoder(8, 3'd1, 8'b0000_0010);
        check_decoder(8, 3'd2, 8'b0000_0100);
        check_decoder(8, 3'd3, 8'b0000_1000);
        check_decoder(8, 3'd4, 8'b0001_0000);
        check_decoder(8, 3'd5, 8'b0010_0000);
        check_decoder(8, 3'd6, 8'b0100_0000);
        check_decoder(8, 3'd7, 8'b1000_0000);

        $finish; 
    end

endmodule