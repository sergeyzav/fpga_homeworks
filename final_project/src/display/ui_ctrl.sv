`include "common/defs.svh"
// Writes 8-character strings into the OSD text RAM.
// job_src = 0: channel display name from mem/chan_names.hex (index = unique channel index, 0..38)
// job_src = 1: fixed string from mem/ui_strings.hex (indices in tools/gen_ui_strings.py, 0..15;
//              the strings ROM only decodes job_idx[3:0], so 16..63 alias onto 0..15)
//
// Handshake: job_ready = idle. A job is accepted on the clock edge where job_valid && job_ready; the
// job_* fields are latched then and may change on the next edge. Each character costs 2 clocks
// (ROM read, then write): writes land at txt_waddr = row*COLS + col + i (i = 0..7, in order) on
// clocks 2, 4, ..., 16 after acceptance, and job_ready returns on clock 16, in the same cycle as the
// eighth write is asserted (txt_we is registered), so a waiting job_valid is accepted back-to-back
// and its first write follows 2 clocks later. Total: 16 clocks per job.
module ui_ctrl #(
  parameter int COLS = 40,
  parameter     CHAN_NAMES_FILE = {`MEM_DIR, "/chan_names.hex"},
  parameter     UI_STRINGS_FILE = {`MEM_DIR, "/ui_strings.hex"}
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       job_valid,
  output logic       job_ready,
  input  logic [3:0] job_row,
  input  logic [5:0] job_col,
  input  logic       job_src,
  input  logic [5:0] job_idx,
  input  logic       job_hl,
  output logic       txt_we,
  output logic [9:0] txt_waddr,
  output logic [7:0] txt_wdata
);
  // row*COLS + col + 7 must fit the 10-bit text RAM address: COLS <= 64 keeps 15*COLS < 1024;
  // whether a specific (row, col) overflows is a runtime concern, checked in simulation below.
  `PARAM_CHECK(g_chk_cols, COLS < 1 || COLS > 64, ("ui_ctrl: COLS must be in 1..64"))

  typedef enum logic [1:0] {S_IDLE, S_WAIT, S_WRITE} state_t;
  state_t state;

  logic [5:0] idx; logic src, hl; logic [9:0] base; logic [2:0] i;
  wire  [8:0] name_addr = {idx, i};                      // idx*8 + i, 64 names
  // 16 fixed strings: only idx[3:0] is decoded, so indices >= 16 alias onto idx mod 16. The hardware
  // wraps silently; the condition is flagged only by the simulation check below.
  wire  [6:0] str_addr  = {idx[3:0], i};
  // ROM images hold 8-bit bytes but the text is 7-bit ASCII: bit 7 is always 0 and never used.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [7:0] name_q, str_q;
  /* verilator lint_on UNUSEDSIGNAL */
  rom_init #(.WIDTH(8), .DEPTH(512), .INIT_FILE(CHAN_NAMES_FILE)) u_names (.clk(clk), .addr(name_addr), .data(name_q));
  rom_init #(.WIDTH(8), .DEPTH(128), .INIT_FILE(UI_STRINGS_FILE)) u_strs  (.clk(clk), .addr(str_addr),  .data(str_q));

  assign job_ready = (state == S_IDLE);

`ifdef SIM
  // Simulation-only sanity checks on the accepted job (not synthesizable; the hardware just wraps).
  // sim_alias_errors counts the string-index check firing so a testbench can assert on it.
  int unsigned sim_alias_errors;
  always @(posedge clk)
    if (!rst_n) sim_alias_errors <= 0;
    else if (job_valid && job_ready) begin
      if (int'(job_row) * COLS + int'(job_col) + 7 > 1023)
        $error("ui_ctrl: job (%0d,%0d) ends at text address %0d > 1023", job_row, job_col, int'(job_row) * COLS + int'(job_col) + 7);
      if (job_src && job_idx > 6'd15) begin
        sim_alias_errors <= sim_alias_errors + 1;
        $error("ui_ctrl: fixed-string index %0d >= 16 aliases onto %0d", job_idx, job_idx[3:0]);
      end
    end
`endif

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= S_IDLE; txt_we <= 1'b0; txt_waddr <= '0; txt_wdata <= '0; idx <= '0; src <= 1'b0; hl <= 1'b0; base <= '0; i <= '0;
    end else begin
      txt_we <= 1'b0;
      case (state)
        S_IDLE: if (job_valid) begin
          idx <= job_idx; src <= job_src; hl <= job_hl; i <= '0;
          base <= 10'(job_row) * 10'(COLS) + 10'(job_col);
          state <= S_WAIT;
        end
        S_WAIT: state <= S_WRITE;                          // ROM address valid, data next cycle
        S_WRITE: begin
          txt_we    <= 1'b1;
          txt_waddr <= base + 10'(i);
          txt_wdata <= {hl, (src ? str_q[6:0] : name_q[6:0])};
          if (i == 3'd7) state <= S_IDLE;
          else begin i <= i + 1'b1; state <= S_WAIT; end
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
