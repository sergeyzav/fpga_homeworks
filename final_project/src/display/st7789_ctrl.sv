`include "common/defs.svh"
// ST7789V controller: hardware reset -> init ROM (commands/params/delays) -> endless frame streaming
// (CASET, RASET, RAMWR, WIDTH*HEIGHT RGB565 pixels, high byte first). Delay ticks are milliseconds
// on hardware and microseconds when SIM_FAST=1.
//
// Pixel source contract: pix_x/pix_y hold the address of the pixel being fetched and only change
// when a pixel is latched. The controller samples pix_data no earlier than the (PIX_LAT+1)-th clock
// edge after the address changed, so the source must have pix_data valid for the new address before
// that edge and keep it stable while the address is stable: a source with L register stages between
// pix_x/pix_y and pix_data needs PIX_LAT >= L (use PIX_LAT >= L+1 for one clock of margin). In steady
// state the two SPI bytes of the previous pixel already hold the address for >= 2*(16*CLK_DIV+1)
// clocks, so the lat_cnt gate below is a non-binding safety net as long as PIX_LAT stays under that
// (the elaboration check); it only ever stalls the first pixel of a frame.
// init_done asserts when the ROM end marker is read, while the last init byte may still be shifting;
// CS is not released between the init sequence and the first frame (cs_req stays high).
module st7789_ctrl #(
  parameter int CLK_HZ         = 100_000_000,
  parameter bit SIM_FAST       = 0,
  parameter int WIDTH          = 320,
  parameter int HEIGHT         = 240,
  parameter int PIX_LAT        = 6,        // pixel source latency in clocks
  parameter int CLK_DIV        = 4,        // must match st7789_spi_master (used for the stall check only)
  parameter int RESET_LOW_TICKS  = 1,      // RESX low time (>= 10 us)
  parameter int RESET_WAIT_TICKS = 120,    // after RESX release before first command
  parameter     INIT_ROM_FILE  = {`MEM_DIR, "/st7789_init.mem"},
  parameter int INIT_ROM_DEPTH = 128
) (
  input  logic        clk,
  input  logic        rst_n,
  // SPI master
  output logic        cs_req,
  output logic        tx_valid,
  input  logic        tx_ready,
  output logic [7:0]  tx_data,
  output logic        tx_dc,
  input  logic        spi_busy,
  // panel reset
  output logic        lcd_resx_n,
  // pixel source
  output logic [$clog2(WIDTH)-1:0]  pix_x,
  output logic [$clog2(HEIGHT)-1:0] pix_y,
  input  logic [15:0] pix_data,
  // status
  output logic        init_done,
  output logic        frame_done
);
  localparam int TICK_CYC = SIM_FAST ? (CLK_HZ + 999_999) / 1_000_000 : (CLK_HZ + 999) / 1000;  // ceil: a tick is never short
  localparam int N_PIX    = WIDTH * HEIGHT;
  localparam int XW = $clog2(WIDTH), YW = $clog2(HEIGHT), CW = $clog2(N_PIX) + 1;
  localparam int TW = $clog2(TICK_CYC), LW = $clog2(PIX_LAT + 2);
  localparam logic [XW-1:0] X_LAST    = XW'(WIDTH - 1);
  localparam logic [YW-1:0] Y_LAST    = YW'(HEIGHT - 1);
  localparam logic [CW-1:0] PIX_LAST  = CW'(N_PIX - 1);
  localparam logic [TW-1:0] TICK_LAST = TW'(TICK_CYC - 1);
  localparam logic [LW-1:0] LAT_MAX   = LW'(PIX_LAT);

  `PARAM_CHECK(g_chk_pix_lat, PIX_LAT > 2 * (16 * CLK_DIV + 1), ("st7789_ctrl: PIX_LAT too large, pixel fetch would stall the SPI"))
  `PARAM_CHECK(g_chk_tick, TICK_CYC < 2, ("st7789_ctrl: CLK_HZ too low for the tick timer"))

  typedef enum logic [3:0] {
    S_RESET_LOW, S_RESET_WAIT, S_ROM_ADDR, S_ROM_WAIT, S_ROM_EXEC, S_SEND, S_DELAY,
    S_FRAME_HDR, S_PIX_LATCH, S_PIX_HI, S_PIX_LO, S_FRAME_END
  } state_t;
  state_t state, ret_state;

  // init ROM
  logic [$clog2(INIT_ROM_DEPTH)-1:0] rom_addr;
  logic [15:0] rom_data;
  rom_init #(.WIDTH(16), .DEPTH(INIT_ROM_DEPTH), .INIT_FILE(INIT_ROM_FILE)) u_rom (.clk(clk), .addr(rom_addr), .data(rom_data));

  // delay machinery
  logic [13:0]   delay_ticks;
  logic [TW-1:0] tick_cnt;

  // frame header: CASET, RASET, RAMWR  -> {dc, byte}
  function automatic logic [8:0] frame_hdr(input logic [3:0] i);
    case (i)
      4'd0:  return {1'b0, 8'h2A};
      4'd1:  return {1'b1, 8'h00};
      4'd2:  return {1'b1, 8'h00};
      4'd3:  return {1'b1, 8'((WIDTH - 1) >> 8)};
      4'd4:  return {1'b1, 8'((WIDTH - 1) & 255)};
      4'd5:  return {1'b0, 8'h2B};
      4'd6:  return {1'b1, 8'h00};
      4'd7:  return {1'b1, 8'h00};
      4'd8:  return {1'b1, 8'((HEIGHT - 1) >> 8)};
      4'd9:  return {1'b1, 8'((HEIGHT - 1) & 255)};
      default: return {1'b0, 8'h2C};
    endcase
  endfunction
  logic [3:0]    hdr_idx;
  wire  [8:0]    hdr_cur = frame_hdr(hdr_idx);
  logic [15:0]   pix_lat;
  logic [CW-1:0] sent_cnt;
  logic [3:0]    wait_cnt;
  logic [LW-1:0] lat_cnt;                  // clocks since pix_x/pix_y last changed, saturates at PIX_LAT

  // send one byte then continue in ret_state
  task automatic start_send(input logic dc, input logic [7:0] b, input state_t nxt);
    tx_data <= b; tx_dc <= dc; tx_valid <= 1'b1; ret_state <= nxt; state <= S_SEND;
  endtask

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= S_RESET_LOW; ret_state <= S_RESET_LOW; cs_req <= 1'b0; tx_valid <= 1'b0; tx_data <= '0; tx_dc <= 1'b0;
      lcd_resx_n <= 1'b0; rom_addr <= '0; delay_ticks <= 14'(RESET_LOW_TICKS); tick_cnt <= '0;
      pix_x <= '0; pix_y <= '0; pix_lat <= '0; sent_cnt <= '0; hdr_idx <= '0; wait_cnt <= '0; lat_cnt <= '0;
      init_done <= 1'b0; frame_done <= 1'b0;
    end else begin
      frame_done <= 1'b0;
      if (lat_cnt != LAT_MAX) lat_cnt <= lat_cnt + 1'b1;
      case (state)
        // ---------------- reset ----------------
        S_RESET_LOW: begin
          lcd_resx_n <= 1'b0; delay_ticks <= 14'(RESET_LOW_TICKS); tick_cnt <= '0; ret_state <= S_RESET_WAIT; state <= S_DELAY;
        end
        S_RESET_WAIT: begin
          lcd_resx_n <= 1'b1; delay_ticks <= 14'(RESET_WAIT_TICKS); tick_cnt <= '0; ret_state <= S_ROM_ADDR; state <= S_DELAY;
        end
        // ---------------- init ROM ----------------
        S_ROM_ADDR: state <= S_ROM_WAIT;             // rom_addr already valid; rom_data valid next cycle
        S_ROM_WAIT: state <= S_ROM_EXEC;
        S_ROM_EXEC: begin
          rom_addr <= rom_addr + 1'b1;
          case (rom_data[15:14])
            2'b00: begin cs_req <= 1'b1; start_send(1'b0, rom_data[7:0], S_ROM_ADDR); end
            2'b01: begin cs_req <= 1'b1; start_send(1'b1, rom_data[7:0], S_ROM_ADDR); end
            2'b10: begin cs_req <= 1'b0; delay_ticks <= rom_data[13:0]; tick_cnt <= '0; ret_state <= S_ROM_ADDR; state <= S_DELAY; end
            default: begin init_done <= 1'b1; hdr_idx <= '0; state <= S_FRAME_HDR; end   // cs_req stays high into the first frame
          endcase
        end
        // ---------------- generic byte send / delay ----------------
        S_SEND: if (tx_valid && tx_ready) begin tx_valid <= 1'b0; state <= ret_state; end
        S_DELAY: begin
          if (!spi_busy) begin                                     // let the last byte finish first
            if (tick_cnt == TICK_LAST) begin
              tick_cnt <= '0;
              if (delay_ticks <= 14'd1) state <= ret_state; else delay_ticks <= delay_ticks - 1'b1;
            end else tick_cnt <= tick_cnt + 1'b1;
          end
        end
        // ---------------- frame ----------------
        S_FRAME_HDR: begin
          cs_req <= 1'b1;
          if (hdr_idx == 4'd10) begin
            pix_x <= '0; pix_y <= '0; sent_cnt <= '0; wait_cnt <= '0; lat_cnt <= '0;
            start_send(hdr_cur[8], hdr_cur[7:0], S_PIX_LATCH);
          end else begin
            hdr_idx <= hdr_idx + 1'b1;
            start_send(hdr_cur[8], hdr_cur[7:0], S_FRAME_HDR);
          end
        end
        S_PIX_LATCH: if (lat_cnt == LAT_MAX) begin                 // source latency elapsed: capture pixel, advance fetch address
          pix_lat <= pix_data;
          lat_cnt <= '0;
          if (pix_x == X_LAST) begin pix_x <= '0; pix_y <= (pix_y == Y_LAST) ? '0 : pix_y + 1'b1; end
          else pix_x <= pix_x + 1'b1;
          state <= S_PIX_HI;
        end
        S_PIX_HI: start_send(1'b1, pix_lat[15:8], S_PIX_LO);
        S_PIX_LO: begin
          sent_cnt <= sent_cnt + 1'b1;
          if (sent_cnt == PIX_LAST) start_send(1'b1, pix_lat[7:0], S_FRAME_END);
          else                      start_send(1'b1, pix_lat[7:0], S_PIX_LATCH);
        end
        S_FRAME_END: begin
          if (!spi_busy) begin
            cs_req <= 1'b0;
            if (wait_cnt == 4'd15) begin frame_done <= 1'b1; hdr_idx <= '0; wait_cnt <= '0; state <= S_FRAME_HDR; end
            else wait_cnt <= wait_cnt + 1'b1;                   // >= 40 ns CS high (tCHW)
          end
        end
        default: state <= S_RESET_LOW;
      endcase
    end
  end
endmodule
