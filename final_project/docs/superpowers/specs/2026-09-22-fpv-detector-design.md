# FPV 5.8 GHz Detector on PlutoSDR (Zynq 7020 PL only) — Implementation Plan

## Context

Build a standalone FPV-drone detector: the AD9363 steps through the 40 analog FPV
channels of the 5.8 GHz band, keeps an up-to-date list of channels carrying a signal,
FM-demodulates the selected channel's analog video (PAL/NTSC, colour) and shows it on an
ST7789V 240×320 LCD over 4-wire SPI with an OSD (channel, frequency, detected list).
A button cycles through the detected channels. Everything runs in PL (no PS/Linux).

Existing material in the repo (`ad9363/`): a Vivado AD9361 example — LVDS 2R2T DDR
interface (`data_process.v` + `selectio_wiz_0` IP), ROM-driven SPI init sequencer
(`AD936X_Init.v`, 2574-entry `AD936X_lut.v` for LO 2.4 GHz / 20 MSPS / 2 MHz BW),
SPI master (`spi_drive.v`), pins (`AD936X.xdc`). `AD936X_Driver.v` is dead code with
bugs — do not reuse. IP cores (clk_wiz, selectio_wiz, blk_mem, ila) are absent; init is
one-shot with no runtime LO retune. ST7789V datasheet essentials are captured below.

Nothing is installed locally yet: no Icarus/Verilator/numpy. Vivado runs on another
machine; only clear batch Tcl scripts are required here.

## Decisions taken with the user

| Topic | Decision |
|---|---|
| Output | Demodulated analog FPV video, colour PAL/NTSC with auto-detect. Staged: luma (B/W) first, chroma added on top without redesign |
| Frequency pool | 40 FPV channels, bands A/B/E/F/R, 5645–5945 MHz (39 unique: F8 = R7 = 5880). AD9363 programmed like AD9361 to 5.8 GHz |
| Shared RX LO | RX1/RX2 share one LO → time-multiplex: VIEW on selected channel, background full RESCAN every `RESCAN_PERIOD` (default 2 s, ≈17 ms blackout, frame frozen), active list kept current, button cycles list. RX2 unused in v1 |
| Toolchain | SystemVerilog RTL in `src/`, testbenches in `sim/` (Icarus `-g2012` + Verilator lint/full-chain), Vivado only via batch Tcl in `vivado/`. **No Xilinx IP**: MMCM, IBUFDS, IDDR, BUFG are instantiated as primitives behind `ifdef SYNTHESIS` shims so everything simulates |
| Interconnect | AXI4-Stream between DSP blocks (video streams use `tuser[0]=SOF`, `tlast=EOL`), AXI4-Lite register bank for control/status |
| LCD | ROM-driven init, RGB565 (COLMOD 0x55), landscape 320×240 via MADCTL, SPI clock parameter (in-spec 12.5 MHz default, overclock later) |
| Board clock | `i_clk` frequency unknown → `SYS_CLK_IN_HZ` parameter (RTL + Tcl), MMCM produces 100 MHz `sys_clk` |
| Init LUT | Both tool paths in `tools/`: ADI Evaluation-Software script converter **and** Pluto register-dump path; chosen at bring-up |
| Pins | AD9363 from `ad9363/AD936X.xdc`; LCD SPI/RESX/DCX + button pins TBD → placeholders in `constr/board_io.xdc` |

## Architecture

```
                 data_clk 80 MHz (from AD9363 DATA_CLK)     |        sys_clk 100 MHz (MMCM from i_clk)
 AD9363 ─LVDS─▶ ad9361_lvds_phy ─▶ ad9361_lvds_unpack ─▶ ad9361_iq_axis ─▶ axis_async_fifo ─▶ fm_demod ─▶ deemph ─▶ fir_dec2 (20 MSPS)
                                          │                                    │                                        │
                                          └─▶ energy_detector (I²+Q²)           │                          cvbs_clamp_agc ─▶ sync_sep ─▶ luma_lpf ─┐
                                                     │                          │                                  │ (Stage B: chroma_bpf→burst_pll→ │
   AD9363 ◀─SPI─ ad9361_spi_master ◀─ ad9361_seq (ROM programs) ◀─ rf_ctrl ─────┘                                  │   chroma_demod→pal_delay_line)  │
                                                     ▲                                                             └──────────▶ yuv2rgb565 ─▶ video_scaler
   button ─▶ button_debounce ───────────────────────┘                                                                                             │
                                          rf_regs (AXI4-Lite) ─▶ ui_ctrl ─▶ osd_text_ram                                                framebuffer (BRAM)
                                                                                         │                                                        │
   ST7789V ◀─SPI─ st7789_spi_master ◀─ st7789_ctrl (init ROM + frame streamer) ◀─ osd_compositor ◀───────────────────────────────────────────────┘
```

Clock domains: `data_clk` (LVDS deframer, IQ packer, energy detector), `sys_clk` (everything
else: SPI masters, sequencer, control, video DSP, framebuffer both ports, OSD, LCD). One
hand-written dual-clock FIFO (`axis_async_fifo`) crosses IQ; `cdc_sync`/`cdc_pulse` for
control bits. LCD SCLK is a registered output, not an internal clock.

## Directory layout

```
src/common/    clk_gen.sv (MMCME2_BASE + sim shim), rst_sync.sv, cdc_sync.sv, cdc_pulse.sv,
               axis_async_fifo.sv, axil_regs.sv, button_debounce.sv, rom_init.sv ($readmemh)
src/rf/        ad9361_lvds_phy.sv, ad9361_lvds_unpack.sv, ad9361_iq_axis.sv, ad9361_spi_master.sv,
               ad9361_seq.sv, rf_ctrl.sv, rf_regs.sv, energy_detector.sv, scan_table.sv
src/video/     fm_demod.sv, cordic_atan2.sv, deemph_iir.sv, fir_dec2.sv, cvbs_clamp_agc.sv,
               sync_sep.sv, luma_lpf.sv, chroma_bpf.sv, nco_sincos.sv, chroma_demod.sv,
               burst_pll.sv, pal_delay_line.sv, yuv2rgb565.sv, video_scaler.sv, framebuffer.sv
src/display/   st7789_spi_master.sv, st7789_ctrl.sv, st7789_init_rom.sv, osd_font_rom.sv,
               osd_text_ram.sv, osd_compositor.sv, chan_names_rom.sv, ui_ctrl.sv
src/top/       fpv_detector_top.sv
mem/           ad9361_prog.mem, chan_sorted.mem, st7789_init.mem, font8x16.hex, chan_names.hex,
               fir_*.hex (coefficients)
tools/         gen_channel_rom.py, adi_script_to_mem.py, pluto_regdump.sh, regdump_to_mem.py,
               gen_fir_coeffs.py, gen_st7789_rom.py, gen_font.py
sim/           Makefile, models/ (ad9361_spi_slave_model.sv, ad9361_lvds_tx_model.sv,
               st7789v_slave_model.sv), gen/ (gen_cvbs.py, iq_gen.py, model_fm_demod.py,
               compare.py, compare_frame.py), tb/ (one tb_<module>.sv per module)
vivado/        create_project.tcl, build.tcl (synth→impl→bitstream, non-project mode),
               program.tcl, timing_report.tcl
constr/        ad9363.xdc (copied/fixed from ad9363/AD936X.xdc), board_io.xdc (placeholders), timing.xdc
docs/          spec (this design), bring-up checklist, register notes
```

## Key design facts to implement against

### AD9363 / RF
- LVDS DDR 1R1T: 6 lanes × 2 edges = 12 bits per DATA_CLK; one I/Q sample per 2 DATA_CLK cycles;
  40 MSPS → DATA_CLK 80 MHz (same rate the working example uses at 2R2T/20 MSPS).
  Frame high = [11:6] half-words, low = [5:0]; rising edge = I, falling = Q (verify vs ADI `axi_ad9361_lvds_if.v`).
  Eye centring via AD9361 reg 0x006 (example 0x80); IDDR `SAME_EDGE_PIPELINED`, no IDELAY.
  `constr/timing.xdc`: `create_clock -period 12.500` on `rx_clk_in_p` (example wrongly says 4.000) + source-synchronous input delays.
- SPI: 24-bit `{R/W, W1:W0=00, 3×0, addr[9:0], data[7:0]}`, MSB first, SCLK 12.5 MHz, single-byte only.
  Fix `spi_drive.v` issues when refactoring: MOSI on falling edge (true mode 0), duplicate `assign w_active`, CS dwell.
- Sequencer ROM word (32 bit): `op[3:0] | addr[9:0] | data[7:0] | arg[7:0]`; ops WR, POLL1, POLL0 (mask, timeout ×100 µs → `error`, `err_pc`), DLY (×10 µs / ×1 ms), RET.
  Programs: INIT (~2600 words), CH[k] k=0..38 (VCO-band regs + 0x235,0x234,0x233,0x232 then **0x231 last** → auto VCO cal; POLL1 0x247 bit1 lock), GAIN_MGC(idx), GAIN_AGC, BB_RESET. Existing LUT bugs not to repeat: missing entry 13'd2573, 0x3FF/0x14 delay 2 ms vs "20 ms" comment.
- Frequency math: f_ref = 40 MHz × 2 = 80 MHz; VCO = 2·f_LO (11.29–11.89 GHz), RX divider ÷2 (0x005[3:0]=0);
  `int = floor(f_vco/80)`, `frac = round((f_vco mod 80)/80 × 8388593)`. 5800 MHz → int 0x091, frac 0. 5865 MHz → int 0x092, frac 0x4FFFF7.
  VCO-band regs from ADI `SynthLUT_FDD` 80 MHz table (0x239, 0x23A, 0x23B, 0x23E–0x240, 0x242, 0x250/0x251, 0x238) — bit packing to be verified in `ad9361.h` by `tools/gen_channel_rom.py` author; the 2.4 GHz block in `AD936X_lut.v:1695-1744` shows the concrete register set.
- Sample chain: BBPLL 1280 MHz, ADC 640 MHz, RHB3/RHB2/RHB1 ÷8 → 80 MHz, RX FIR ÷2 → 40 MSPS; RX BB analog BW ≈ 28 MHz; gain table 5500 MHz; 0x003 = RX1 only.
- ENSM: stay forced FDD (0x014=0x23) during retune, gate stream with `freeze`; fallback program via ALERT (0x014=0x0D).
- Gain: SCAN in MGC fixed index (repeatable absolute power); VIEW in slow-attack AGC (0x0FA). 2 SPI writes per switch.
- Detector: `energy_detector` sums I²+Q² over 4096 samples (102 µs). `scan_table`: frequency-sorted 39 entries, noise floor = min power, `T_on = floor×K_on` (8), `T_off = floor×K_off` (4), local-max within ±12 MHz (channels interleave at 1–4 MHz spacing so one TX lights 5–8 entries), persistence 2 scans on / 3 off, up to 8 active sorted by power.
- Hop budget: ~16 SPI writes 42 µs + VCO cal/lock ≤200 µs + settle 20 µs + dwell 102 µs ≈ 370 µs; 39 hops + gain switches ≈ 17 ms per rescan.
- `rf_ctrl` states: RESET → INIT → SCAN_FULL → VIEW ⇄ RESCAN, FAULT on sequencer error. Button short = next active (by channel id), long ≥1 s = force rescan. If selected channel inactive for 3 scans → strongest.

### Video
- FM demod: conj-multiply `x[n]·conj(x[n-1])` + 14-iteration pipelined CORDIC atan2 (linear over ±π, amplitude-independent); 16-bit frequency, 610 Hz/LSB at 40 MSPS. Carrier offset (±1 MHz) becomes DC → removed by sync-tip clamp, not by a DC blocker.
- De-emphasis first-order IIR (bypassable). 19-tap LPF 5.6 MHz + ÷2 → **CVBS at 20 MSPS** (kills 6.0/6.5 MHz audio subcarriers). All line constants `localparam` from `FS_HZ`.
- Line geometry @20 MSPS: PAL 1280 samples/line, NTSC 1271.1; H-sync 94; active start 210 (PAL) / 188 (NTSC); burst window 112–157.
- `cvbs_clamp_agc`: sync-tip min-follower, back-porch average, per-line gain loop to (blank−tip)=77/255.
- `sync_sep`: slicer at mid-sync, flywheel line counter with ±32-sample window, lock after 16 edges / unlock after 32 misses; V-sync via broad-pulse (>15 µs) integrator; field parity; PAL/NTSC by line count (312/313 vs 262/263) with 4-field hysteresis; exports `hsync, vsync, active, field, std_pal, burst_gate, locked`.
- Luma: 21-tap LPF 3.0 MHz (Stage A) → 8-bit Y. Stage B: Y = cvbs − chroma_bpf (complementary), LPF 4.2 MHz.
- Chroma (Stage B): 23-tap BPF fsc±1.3 MHz (PAL 4.43361875 / NTSC 3.579545 MHz coefficient sets), 32-bit NCO + quarter-wave sine ROM, demod + 9-tap 1 MHz LPFs → U/V; burst PLL (10-iter CORDIC on gated burst, PI loop, PAL V-switch fold + ident), colour-kill on weak burst (degrades to Stage A); PAL 1H delay-line average (1 BRAM36); `yuv2rgb565` 8.8 fixed point.
- Scaler: horizontal fractional accumulator 8.8 (step 3.25 PAL / 3.29 NTSC → 320 px, 2-tap linear); vertical one field → 240 rows (PAL step 0.8333 nearest, NTSC 1.0); each field refreshes whole buffer.
- Framebuffer: 320×240×RGB565 = 38 BRAM36, TDP, single buffer (`N_BUF` param), writer stalls on `freeze` or `!locked` (frame held; OSD shows NO SIGNAL after N fields).

### ST7789V
- 4-wire SPI mode 0 (also accepts mode 3), MSB first, D/CX sampled on 8th SCLK; write cycle ≥66 ns (15.15 MHz max in spec; panels commonly run 50–62 MHz). CS low across a frame, ≥40 ns high between frames. Datasheet pin table quirk: bump `DCX` = clock, `WRX` = D/C.
- Reset: RESX ≥10 µs, wait 120 ms; SLPOUT then ≥5 ms (use 120 ms). `SIM_FAST` param scales ms→µs.
- Init ROM (16-bit `{type[1:0], payload}`; cmd/data/delay-ms/end): SWRESET (150 ms), SLPOUT (120 ms), COLMOD 0x55, MADCTL 0x60 (landscape, param), PORCTRL B2 0C 0C 00 33 33, GCTRL B7 35, VCOMS BB 20, LCMCTRL C0 2C, VDVVRHEN C2 01 FF, VRHS C3 0B, VDVS C4 20, FRCTRL2 C6 0F, PWCTRL1 D0 A4 A1, PVGAMCTRL E0 / NVGAMCTRL E1 = 70 2C 2E 15 10 09 48 33 53 0B 19 18 20 25, INVON (param), NORON, DISPON, CASET 0..0x13F, RASET 0..0xEF.
- Streaming: CASET, RASET, RAMWR then 76,800 × 2 bytes, high byte `{R4..R0,G5..G3}` first. 12.5 MHz → ~10 fps; 50 MHz → ~40 fps.
- OSD: 8×16 font (96 glyphs, `font8x16.hex`), text RAM 40×15, row 0 = `CH R1 5658  LOCK PAL`, right column rows 1–8 = active list with current highlighted; `chan_names_rom` (39 × 8 chars) so `ui_ctrl` issues `{row, col, chan_idx}` jobs.

### Resource budget (xc7z020: 53.2k LUT / 106k FF / 140 BRAM36 / 220 DSP)
Video+display ≈ 6.2k LUT, 6.5k FF, 41 BRAM, 59 DSP. RF side ≈ 2k LUT, 4 BRAM (program ROM 3 + FIFO), 2–4 DSP. Total well under 30 % of the part; double buffering (+38 BRAM) is affordable if wanted later.

## Milestones (each ends with passing sims + Verilator lint; hardware steps marked HW)

### M0 — Skeleton and tooling
- `sim/Makefile` (Icarus per-TB targets, `lint` via Verilator `-Wall`, `gen` for Python), `requirements.txt` (numpy, scipy, pillow), `README` with `brew install icarus-verilog verilator`.
- `src/common/*`: clk_gen (MMCME2_BASE, `SYS_CLK_IN_HZ` param, sim shim), rst_sync, cdc_*, axis_async_fifo (Gray pointers), axil_regs, button_debounce, rom_init. TBs for FIFO (CDC stress), debounce, regs.
- `vivado/create_project.tcl` + `build.tcl` (non-project batch: read_verilog -sv, read_xdc, synth_design, opt/place/route, write_bitstream, reports), `program.tcl`. `constr/` files with placeholders and the corrected 12.5 ns LVDS clock.

### M1 — LCD path with test pattern (first visible result on HW)
- `st7789_spi_master`, `st7789_init_rom` + `tools/gen_st7789_rom.py`, `st7789_ctrl` (init → frame streaming), `framebuffer`, `osd_*`, `chan_names_rom`, `ui_ctrl` (static text), a colour-bar/gradient test-pattern writer.
- `sim/models/st7789v_slave_model.sv` reconstructs the frame (honours CASET/RASET/MADCTL, checks timing/DCX/order) → PPM; `tb_st7789`, `tb_osd`.
- HW: bitstream with test pattern + OSD text on the panel; tune MADCTL/INVON/VCOMS/SPI_DIV parameters.

### M2 — AD9363 bring-up: SPI, sequencer, init, LVDS capture, retune
- `ad9361_spi_master` (refactor of `spi_drive.v`), `ad9361_seq` (ROM programs), `ad9361_lvds_phy/unpack`, `ad9361_iq_axis`, PRBS/BIST checker.
- `tools/adi_script_to_mem.py` (validated by converting the original 2.4 GHz script and diffing against `AD936X_lut.v`), `tools/pluto_regdump.sh` + `regdump_to_mem.py`, `tools/gen_channel_rom.py` (ports `ad9361_calc_rfpll_divder` + `SynthLUT_FDD`, emits CH[k] programs, `chan_sorted.mem`, JSON for the sim model).
- `sim/models/ad9361_spi_slave_model.sv` (register array, lock/cal side effects with programmable delays, write log), `ad9361_lvds_tx_model.sv`; `tb_ad9361_spi_master`, `tb_ad9361_seq` (incl. timeout → error), `tb_lvds_rx`.
- HW: INIT completes (status on OSD), PRBS BIST passes, LO hops lock on all 39 channels (error PC on OSD if not).

### M3 — Scanner and RF control
- `energy_detector`, `scan_table`, `rf_ctrl`, `rf_regs`, `ui_ctrl` shows live active list/powers.
- `sim/gen/iq_gen.py` (tone+noise, noise, wideband FM-like), `tb_energy_detector` (±1 % vs numpy), `tb_scan_table` (single TX at 5800 → only F4; two TX; noise-only; flapping), `tb_rf_ctrl` integration (scaled timers, button, freeze envelope, fault path).
- HW: real VTX detected, list updates every rescan, button cycles.

### M4 — Video Stage A (B/W picture)
- `fm_demod` + `cordic_atan2`, `deemph_iir`, `fir_dec2`, `cvbs_clamp_agc`, `sync_sep`, `luma_lpf`, `yuv2rgb565` (U=V=0), `video_scaler`, connection to framebuffer with `freeze`.
- `sim/gen/gen_cvbs.py` (PAL/NTSC colour bars → FM I/Q with deviation/offset/SNR options, `ref_frame.png`), `model_fm_demod.py` bit-accurate; `tb_fm_demod` (≤2 LSB vs model), `tb_sync_sep` (positions, std detect, hold over missing pulses), `tb_video_pipeline` (Verilator, PPM dump, PSNR ≥30 dB grey).
- HW: live B/W FPV video with OSD; tune de-emphasis/AGC constants.

### M5 — Video Stage B (colour)
- `chroma_bpf`, `nco_sincos`, `chroma_demod`, `burst_pll`, `pal_delay_line`, complementary luma path, colour-kill.
- `tb_chroma` (U/V per bar ±6 LSB, PLL lock <20 lines, PAL ident, colour-kill), `tb_video_pipeline` colour PSNR ≥28 dB.
- HW: colour video; hue/saturation params.

### M6 — Integration and hardening
- `fpv_detector_top` full wiring, final `constr/*.xdc` (real LCD/button pins), timing closure report, bring-up checklist in `docs/`, optional `N_BUF=2` if BRAM allows and tearing bothers.

## Verification summary
- Every module has `sim/tb/tb_<module>.sv` run by `make tb_<module>` (Icarus `-g2012`); `make lint` (Verilator `-Wall`) over `src/`; `make all` runs everything and Python golden checks. SystemVerilog subset restricted to what Icarus, Verilator and Vivado all accept (`logic`, `always_ff/comb`, packed arrays, `localparam` functions; no interfaces/unpacked struct ports).
- Python generators produce deterministic stimulus + golden references; image outputs (PPM/PNG) for eyeballing.
- Hardware verification per milestone as listed; `vivado/build.tcl` emits utilisation/timing reports that are checked against the budget above.

## Risks / open items
1. AD9363 at 5.8 GHz is outside the datasheet range (board matching, VCO at 11.89 GHz for E8/R8 near the 12 GHz limit) — verify lock and sensitivity on HW early (M2).
2. VCO-LUT register bit packing and "0x231 write triggers cal" must be confirmed against ADI `ad9361.h`/UG-570 when writing `gen_channel_rom.py`.
3. Init LUT source (ADI eval software vs Pluto dump) decided at bring-up; both tools provided.
4. `i_clk` frequency unknown (parameter); LCD/button pins pending from user.
5. Adjacent-channel masking (channels 1–4 MHz apart) — local-max picking in v1; narrow pre-filter is the upgrade path.
6. VTX pre-emphasis/deviation vary — de-emphasis and AGC constants are runtime/parameter tunable.
7. LCD SPI overclock is panel-specific; 10 fps at spec speed until tested.
8. Single framebuffer tearing accepted in v1.
