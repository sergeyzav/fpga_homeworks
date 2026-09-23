`timescale 1ns/1ps
module tb_rom_init;
  logic clk = 0; always #5 clk = ~clk;

  logic [2:0] addr = 0;
  logic [15:0] data;
  rom_init #(.WIDTH(16), .DEPTH(8), .INIT_FILE("sim/test_rom.mem")) dut (.clk(clk), .addr(addr), .data(data));

  // Non-power-of-two DEPTH instance: $clog2(6) = 3, so addr [2:0] can reach 6 and 7, which
  // are out of range for this ROM (exercises the module's addr < DEPTH requirement).
  logic [2:0] addr6 = 0;
  logic [15:0] data6;
  rom_init #(.WIDTH(16), .DEPTH(6), .INIT_FILE("sim/test_rom6.mem")) dut6 (.clk(clk), .addr(addr6), .data(data6));

  initial begin
    logic [15:0] prev;

    // Prove the register stage: after addr changes, data must still hold the previous
    // address's value right up until the next posedge, and only then update.
    addr = 3'd0;
    @(posedge clk); #1;
    if (data !== {4{4'h0}}) $fatal(1, "addr 0: got %h", data);
    prev = data;
    for (int i = 1; i < 8; i++) begin
      addr = i[2:0];
      #1;
      if (data !== prev) $fatal(1, "addr %0d: data changed before its clock edge: got %h expected %h", i, data, prev);
      @(posedge clk); #1;
      if (data !== {4{i[3:0]}}) $fatal(1, "addr %0d: got %h", i, data);
      prev = data;
    end

    // Non-power-of-two DEPTH: in-range addresses 0..DEPTH-1 must still read correctly.
    for (int i = 0; i < 6; i++) begin
      addr6 = i[2:0]; @(posedge clk); #1;
      if (data6 !== {4{i[3:0]}}) $fatal(1, "dut6 addr %0d: got %h", i, data6);
    end

    $display("PASS tb_rom_init");
    $finish;
  end
endmodule
