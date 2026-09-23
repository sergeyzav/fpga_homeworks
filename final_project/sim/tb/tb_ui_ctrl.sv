`timescale 1ns/1ps
module tb_ui_ctrl;
  logic clk = 0; always #5 clk = ~clk;
  logic rst_n = 0;
  logic job_valid = 0, job_ready, job_src = 0, job_hl = 0;
  logic [3:0] job_row = 0; logic [5:0] job_col = 0, job_idx = 0;
  logic txt_we; logic [9:0] txt_waddr; logic [7:0] txt_wdata;

  ui_ctrl dut (.clk(clk), .rst_n(rst_n), .job_valid(job_valid), .job_ready(job_ready), .job_row(job_row),
               .job_col(job_col), .job_src(job_src), .job_idx(job_idx), .job_hl(job_hl),
               .txt_we(txt_we), .txt_waddr(txt_waddr), .txt_wdata(txt_wdata));

  // Shadow of the text RAM plus a log of every write in issue order (address only; the data is
  // checked through the shadow). The log is drained and checked after each job.
  logic [7:0] shadow [0:1023];
  logic [9:0] wlog [$];
  always @(posedge clk) if (txt_we) begin shadow[txt_waddr] <= txt_wdata; wlog.push_back(txt_waddr); end

  // Issue one job and wait for it to complete. job_ready is sampled at negedge so the handshake is
  // race-free; the trailing #1 lets the shadow's last non-blocking update settle before any check.
  // Also checks the documented job length: job_ready returns JOB_CLKS edges after the accepting edge.
  localparam int JOB_CLKS = 16;
  task automatic job(input int row, input int col, input logic src, input int idx, input logic hl);
    int n = 0;
    job_row = row[3:0]; job_col = col[5:0]; job_src = src; job_idx = idx[5:0]; job_hl = hl; job_valid = 1;
    forever begin @(negedge clk); if (job_ready) break; end   // next rising edge accepts the job
    @(posedge clk); #1 job_valid = 0;
    @(negedge clk); while (!job_ready) begin @(negedge clk); n++; end   // wait for the 8 writes to finish
    if (n != JOB_CLKS) $fatal(1, "job (%0d,%0d) took %0d clocks, expected %0d", row, col, n, JOB_CLKS);
    @(posedge clk); #1;
  endtask
  function automatic string text_at(input int row, input int col);
    string s = ""; for (int i = 0; i < 8; i++) s = $sformatf("%s%c", s, shadow[row * 40 + col + i][6:0]); return s;
  endfunction
  // Exactly 8 writes, on consecutive addresses base..base+7 in order; then clear the log.
  task automatic check_writes(input int row, input int col);
    int base = row * 40 + col;
    if (wlog.size() != 8) $fatal(1, "job (%0d,%0d): %0d writes, expected 8", row, col, wlog.size());
    for (int i = 0; i < 8; i++)
      if (wlog[i] != 10'(base + i)) $fatal(1, "job (%0d,%0d): write %0d hit addr %0d, expected %0d", row, col, i, wlog[i], base + i);
    wlog.delete();
  endtask
  task automatic expect_quiet(input int cycles, input string when);
    repeat (cycles) @(posedge clk); #1;
    if (wlog.size() != 0) $fatal(1, "%0d write(s) outside a job (%s)", wlog.size(), when);
    if (!job_ready) $fatal(1, "job_ready low while idle (%s)", when);
  endtask

  initial begin
    for (int i = 0; i < 1024; i++) shadow[i] = 8'h20;
    repeat (2) @(posedge clk); rst_n = 1;
    expect_quiet(5, "after reset");

    job(0, 0, 0, 0, 0);       // channel 0 name "A1 5865 "
    check_writes(0, 0);
    expect_quiet(5, "after job 1");
    job(0, 12, 1, 1, 0);      // string 1 "SCAN    "
    check_writes(0, 12);
    job(3, 32, 0, 5, 1);      // channel 5 "A6 5765 " highlighted
    check_writes(3, 32);
    expect_quiet(5, "after job 3");
    if (text_at(0, 0)  != "A1 5865 ") $fatal(1, "text_at(0,0)='%s'", text_at(0, 0));
    if (text_at(0, 12) != "SCAN    ") $fatal(1, "text_at(0,12)='%s'", text_at(0, 12));
    if (text_at(3, 32) != "A6 5765 ") $fatal(1, "text_at(3,32)='%s'", text_at(3, 32));
    for (int i = 0; i < 8; i++) if (!shadow[3 * 40 + 32 + i][7]) $fatal(1, "highlight bit missing at %0d", i);
    for (int i = 0; i < 8; i++) if (shadow[0 + i][7]) $fatal(1, "unexpected highlight at %0d", i);

    // Negative case: fixed-string index >= 16. The strings ROM decodes only idx[3:0], so 17 aliases
    // onto string 1 ("SCAN    "); that is the documented hardware behaviour. The RTL's SIM-only check
    // must flag it exactly once — expect one line like
    //   ERROR: src/display/ui_ctrl.sv:NN: ui_ctrl: fixed-string index 17 >= 16 aliases onto 1
    if (dut.sim_alias_errors != 0) $fatal(1, "alias check fired %0d time(s) before the aliasing job", dut.sim_alias_errors);
    job(4, 0, 1, 17, 0);
    check_writes(4, 0);
    if (text_at(4, 0) != "SCAN    ") $fatal(1, "text_at(4,0)='%s' (idx 17 must alias onto string 1)", text_at(4, 0));
    if (dut.sim_alias_errors != 1) $fatal(1, "alias check fired %0d time(s), expected 1", dut.sim_alias_errors);

    // Back-to-back: job_valid stays high across the first job's completion with the next job's
    // fields already applied. The second job must be accepted on the first edge job_ready returns,
    // and neither string may be corrupted by the overlap of the last write with the new acceptance.
    job_row = 4'd7; job_col = 6'd0; job_src = 1'b1; job_idx = 6'd9; job_hl = 1'b0; job_valid = 1;  // "TEST    "
    forever begin @(negedge clk); if (job_ready) break; end
    @(posedge clk); #1;
    job_row = 4'd7; job_col = 6'd8; job_src = 1'b0; job_idx = 6'd0; job_hl = 1'b1;                 // "A1 5865 " hl
    @(negedge clk); while (!job_ready) @(negedge clk);         // first job done: second accepted at the next posedge
    @(posedge clk); #1 job_valid = 0;
    @(negedge clk); while (!job_ready) @(negedge clk);
    @(posedge clk); #1;
    if (wlog.size() != 16) $fatal(1, "back-to-back: %0d writes, expected 16", wlog.size());
    for (int i = 0; i < 16; i++)
      if (wlog[i] != 10'(7 * 40 + i)) $fatal(1, "back-to-back: write %0d hit addr %0d, expected %0d", i, wlog[i], 7 * 40 + i);
    wlog.delete();
    if (text_at(7, 0) != "TEST    ") $fatal(1, "text_at(7,0)='%s'", text_at(7, 0));
    if (text_at(7, 8) != "A1 5865 ") $fatal(1, "text_at(7,8)='%s'", text_at(7, 8));
    for (int i = 0; i < 8; i++) if (shadow[7 * 40 + i][7])      $fatal(1, "unexpected highlight at (7,%0d)", i);
    for (int i = 0; i < 8; i++) if (!shadow[7 * 40 + 8 + i][7]) $fatal(1, "highlight bit missing at (7,%0d)", 8 + i);
    expect_quiet(10, "end of test");

    $display("PASS tb_ui_ctrl");
    $finish;
  end
endmodule
