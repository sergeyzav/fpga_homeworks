`include "common/defs.svh"
// M1 demo screen. On `start`: row 0 = channel 0 name at col 0, "TEST" at col TEST_COL; rows 1..3 at
// col LIST_COL: channels 0,1,2, highlighted when equal to `sel`. On `sel_change`: rewrite the list only.
//
// Selection timing: each list entry's job reads `sel` live when it is issued. A `sel_change` on the
// very edge that starts a list run is therefore absorbed by that run (the flag it would set is
// cleared on the same edge and the run already uses the new `sel`). A press in the middle of a run
// updates `sel` between entries, so the screen may show two or zero highlighted entries until the
// queued rewrite (3 jobs, well under a frame) restores exactly one.
module ui_demo #(
  parameter int COLS     = 40,
  parameter int LIST_COL = 32,
  parameter int TEST_COL = 12,
  parameter int STR_TEST = 9        // index in mem/ui_strings.hex
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic       sel_change,
  input  logic [1:0] sel,
  output logic       job_valid,
  input  logic       job_ready,
  output logic [3:0] job_row,
  output logic [5:0] job_col,
  output logic       job_src,
  output logic [5:0] job_idx,
  output logic       job_hl
);
  // Row 0 holds the channel name at cols 0..7 and "TEST" at TEST_COL..TEST_COL+7; the list sits on
  // rows 1..3, so it may share columns with "TEST" but every string must end inside the COLS columns.
  `PARAM_CHECK(g_chk_cols, TEST_COL < 8 || TEST_COL + 8 > COLS || LIST_COL + 8 > COLS,
               ("ui_demo: strings do not fit in COLS=%0d (TEST_COL=%0d, LIST_COL=%0d)", COLS, TEST_COL, LIST_COL))

  // step table: 0 = chan0 header, 1 = TEST, 2..4 = list entries, 5 = done
  logic [2:0] step;
  logic       running, pending_start, pending_sel;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      step <= '0; running <= 1'b0; pending_start <= 1'b0; pending_sel <= 1'b0; job_valid <= 1'b0;
      job_row <= '0; job_col <= '0; job_src <= 1'b0; job_idx <= '0; job_hl <= 1'b0;
    end else begin
      if (start)      pending_start <= 1'b1;
      if (sel_change) pending_sel   <= 1'b1;

      if (!running) begin
        if (pending_start)    begin running <= 1'b1; step <= 3'd0; pending_start <= 1'b0; end
        else if (pending_sel) begin running <= 1'b1; step <= 3'd2; pending_sel <= 1'b0; end
      end else if (!job_valid) begin
        if (step == 3'd5) running <= 1'b0;
        else begin
          job_valid <= 1'b1;
          case (step)
            3'd0: begin job_row <= 4'd0; job_col <= 6'd0;           job_src <= 1'b0; job_idx <= 6'd0;         job_hl <= 1'b0; end
            3'd1: begin job_row <= 4'd0; job_col <= 6'(TEST_COL);   job_src <= 1'b1; job_idx <= 6'(STR_TEST); job_hl <= 1'b0; end
            default: begin
              job_row <= 4'(step - 3'd1); job_col <= 6'(LIST_COL); job_src <= 1'b0;
              job_idx <= 6'(step - 3'd2); job_hl <= (2'(step - 3'd2) == sel);
            end
          endcase
        end
      end else if (job_ready) begin        // accepted this cycle
        job_valid <= 1'b0;
        step <= step + 1'b1;
      end
    end
  end
endmodule
