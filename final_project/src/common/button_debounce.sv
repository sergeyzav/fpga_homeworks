`include "common/defs.svh"
// Debounced push button with short/long press detection.
//  pressed     : debounced level (1 = held)
//  short_press : 1-cycle pulse on release if held shorter than LONG_MS
//  long_press  : 1-cycle pulse when the hold time reaches LONG_MS (no short_press afterwards)
module button_debounce #(
  parameter int CLK_HZ      = 100_000_000,
  parameter int DEBOUNCE_MS = 20,
  parameter int LONG_MS     = 1000,
  parameter bit ACTIVE_LOW  = 1
) (
  input  logic clk,
  input  logic rst_n,
  input  logic btn,
  output logic pressed,
  output logic short_press,
  output logic long_press
);
  `PARAM_CHECK(g_chk_times, DEBOUNCE_MS < 1 || LONG_MS <= DEBOUNCE_MS,
               ("button_debounce: need DEBOUNCE_MS >= 1 and LONG_MS > DEBOUNCE_MS"))

  localparam longint DEB_CYC  = (longint'(CLK_HZ) / 1000) * DEBOUNCE_MS;
  localparam longint LONG_CYC = (longint'(CLK_HZ) / 1000) * LONG_MS;
  // counters sized to hold 0 .. *_CYC-1; compare constants share the same width
  localparam int DEB_W  = (DEB_CYC  > 1) ? $clog2(DEB_CYC)  : 1;
  localparam int LONG_W = (LONG_CYC > 1) ? $clog2(LONG_CYC) : 1;
  localparam logic [DEB_W-1:0]  DEB_LAST  = DEB_W'(DEB_CYC - 1);
  localparam logic [LONG_W-1:0] LONG_LAST = LONG_W'(LONG_CYC - 1);

  logic btn_s;
  cdc_sync #(.WIDTH(1)) u_sync (.clk(clk), .d(btn), .q(btn_s));
  logic raw;
  assign raw = ACTIVE_LOW ? ~btn_s : btn_s;

  logic [DEB_W-1:0]  deb_cnt;
  logic [LONG_W-1:0] hold_cnt;
  logic              long_fired;
  // hold time reaches LONG_CYC this cycle; also blocks a same-cycle short_press on release
  logic              long_hit;
  assign long_hit = pressed && !long_fired && (hold_cnt == LONG_LAST);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pressed <= 1'b0; deb_cnt <= '0; hold_cnt <= '0; long_fired <= 1'b0;
      short_press <= 1'b0; long_press <= 1'b0;
    end else begin
      short_press <= 1'b0;
      long_press  <= 1'b0;

      // debounce: input must be stable for DEB_CYC cycles before pressed follows it
      if (raw == pressed) deb_cnt <= '0;
      else if (deb_cnt == DEB_LAST) begin
        deb_cnt <= '0;
        pressed <= raw;
        if (!raw && !long_fired && !long_hit) short_press <= 1'b1; // release after a short hold
      end else deb_cnt <= deb_cnt + 1'b1;

      // hold timer
      if (!pressed) begin
        hold_cnt <= '0; long_fired <= 1'b0;
      end else if (long_hit) begin
        long_fired <= 1'b1; long_press <= 1'b1;
      end else if (!long_fired) hold_cnt <= hold_cnt + 1'b1;
    end
  end
endmodule
