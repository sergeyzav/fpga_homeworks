`include "common/defs.svh"
// 4-wire SPI master for ST7789V (write only). Mode 0: SCLK idles low, MOSI updated on the falling
// edge, the panel samples on the rising edge, MSB first. SCLK = clk / (2*CLK_DIV).
// cs_req: level; cs_n falls immediately, tx_ready rises 3 clocks later (tCSS >= 15 ns at 100 MHz)
// and cs_n only rises again when cs_req is low and no byte is in flight or being accepted.
module st7789_spi_master #(
  parameter int CLK_DIV = 4          // 100 MHz / (2*4) = 12.5 MHz (datasheet max 15.15 MHz)
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       cs_req,
  input  logic       tx_valid,
  output logic       tx_ready,
  input  logic [7:0] tx_data,
  input  logic       tx_dc,          // 0 = command, 1 = data/parameter
  output logic       busy,
  output logic       sclk,
  output logic       mosi,
  output logic       cs_n,
  output logic       dcx
);
  localparam logic [7:0] DIV_MAX = 8'(CLK_DIV - 1);

  `PARAM_CHECK(g_chk_div, CLK_DIV < 1 || CLK_DIV > 256, ("st7789_spi_master: CLK_DIV must be 1..256"))

  // All four outputs are dedicated registers with no fan-out back into the module, so the synthesiser
  // can pack them into the IOB flip-flops for clean, mutually aligned output timing:
  //  - mosi is loaded from tx_data[7] on accept, then from shreg[6] on each falling edge (not a mux off
  //    shreg); shreg holds the 7 bits still to send after the one currently on mosi.
  //  - sclk and cs_n also steer the internal state machine, so the module keeps its own copies
  //    (sclk_r, cs_n_r) and the output ports are replicas: both copies load the same next-state value
  //    (sclk_n, cs_n_n) on the same clock edge, so the ports are cycle-identical to the internal state
  //    and no extra skew against mosi/dcx is introduced.
  logic [6:0] shreg;
  logic [2:0] bit_cnt;
  logic [7:0] div_cnt;
  logic [1:0] cs_cnt;
  logic       shifting;
  logic       sclk_r, cs_n_r;        // internal copies of the sclk / cs_n outputs
  logic       sclk_n, cs_n_n;        // shared next-state for the internal copy and the IOB replica

  assign busy     = shifting;
  assign tx_ready = !shifting && !cs_n_r && (cs_cnt == 2'd3);

  always_comb begin
    // chip select: falls on request, rises only when idle and not accepting a byte this clock
    cs_n_n = cs_n_r;
    if (cs_req)                                     cs_n_n = 1'b0;
    else if (!shifting && !(tx_valid && tx_ready))  cs_n_n = 1'b1;  // hold CS through a byte accepted this clock
    // clock: low while idle, toggles every CLK_DIV clocks while a byte is shifting
    sclk_n = sclk_r;
    if (!shifting) begin
      if (tx_valid && tx_ready) sclk_n = 1'b0;
    end else if (div_cnt == DIV_MAX) sclk_n = !sclk_r;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cs_n_r <= 1'b1; cs_n <= 1'b1; cs_cnt <= '0; sclk_r <= 1'b0; sclk <= 1'b0; mosi <= 1'b0; dcx <= 1'b0;
      shifting <= 1'b0; shreg <= '0; bit_cnt <= '0; div_cnt <= '0;
    end else begin
      cs_n_r <= cs_n_n; cs_n <= cs_n_n;
      sclk_r <= sclk_n; sclk <= sclk_n;
      if (cs_n_r) cs_cnt <= '0;
      else if (cs_cnt != 2'd3) cs_cnt <= cs_cnt + 1'b1;

      if (!shifting) begin
        if (tx_valid && tx_ready) begin
          shreg    <= tx_data[6:0];
          dcx      <= tx_dc;
          mosi     <= tx_data[7];
          bit_cnt  <= 3'd7;
          div_cnt  <= '0;
          shifting <= 1'b1;
        end
      end else begin
        if (div_cnt == DIV_MAX) begin
          div_cnt <= '0;
          if (sclk_r) begin                     // falling edge (sclk_n = 0): present next bit
            if (bit_cnt == 3'd0) shifting <= 1'b0;
            else begin
              bit_cnt <= bit_cnt - 1'b1;
              shreg   <= {shreg[5:0], 1'b0};
              mosi    <= shreg[6];
            end
          end                                   // else rising edge (sclk_n = 1): panel samples mosi
        end else div_cnt <= div_cnt + 1'b1;
      end
    end
  end
endmodule
