# M1 bring-up: test pattern on the ST7789V

Goal: get the M1 design (`src/top/lcd_test_top.sv`) — colour-bar test pattern + OSD text + button
demo — running on real hardware. M0/M1 are complete and passing in simulation; this checklist is
for the first real build.

## Prerequisites

- [ ] LCD pins (SCLK, SDA/MOSI, CS, DC, RESX, 3.3 V, GND) and the button pin are known and entered
      in `constr/board_io.xdc` — uncomment and fill the six commented `PACKAGE_PIN` lines
      (`lcd_sclk`, `lcd_mosi`, `lcd_cs_n`, `lcd_dcx`, `lcd_resx_n`, `btn_n`).
      **Do not connect the panel to a bitstream built before this is done.** `vivado/build.tcl`
      checks for unplaced ports right after `synth_design` and prints:
      `WARNING: ports without PACKAGE_PIN (auto-placed, do NOT connect hardware): <list>`
      As of this checklist, an unplaced port is **fatal by default**: the build prints the
      warning above, then `ERROR: unplaced ports present and allow_unplaced (4th tclarg) not
      set; aborting before place_design` and exits 1 — no bitstream is produced. If that warning
      names any LCD/button port, stop — Vivado auto-placed it on an arbitrary pin; fill in the
      real pins before rebuilding. For a no-hardware trial build only (e.g. checking utilization
      or timing with the LCD pins still unplaced), pass any non-empty 4th `tclarg` to override:
      `vivado -mode batch -source vivado/build.tcl -tclargs lcd_test_top <SYS_CLK_IN_HZ> xc7z020clg400-1 allow_unplaced`
      (the `part` argument must be given too, since `allow_unplaced` is positional). A bitstream
      built this way must still not be connected to real hardware on the unplaced pins.
      `vivado/build.tcl` also refuses to write a bitstream (exits 1, no override) if setup or
      hold WNS is negative after `route_design` — see step 5 below.
- [ ] Board oscillator frequency on pin N18 is known (`SYS_CLK_IN_HZ`). It is **not** known for
      this board yet — measure it with a scope/frequency counter, or read it off the schematic,
      before building. `src/common/clk_gen.sv`'s MMCM solver rejects `SYS_CLK_IN_HZ` outside
      10–800 MHz (MMCME2 CLKIN1 range) and any value whose PFD input (`SYS_CLK_IN_HZ` after the
      D divider) falls outside 19–450 MHz — a build with the wrong value either aborts with
      `clk_gen: SYS_CLK_IN_HZ outside MMCM CLKIN range` / `no MMCM solution for ... Hz`, or (worse)
      elaborates with the wrong `sys_clk` frequency if you also guess the argument wrong. The
      solver is **integer-only** (it searches integer M and O multiply/divide values): if the
      measured board clock has no integer MMCM solution to 100 MHz (e.g. 27 MHz or 33.333 MHz),
      the build stops with `no MMCM solution` even though the frequency is otherwise in range.
      That is a solver limitation, not a hardware problem — extending
      `src/common/clk_gen.sv`'s solver to 0.125 (1/8) steps would cover those inputs, but that
      extension does not exist yet.
- [ ] `make test` passes locally (runs `sim` + `lint` + `tclcheck` + `pytests`; syntax-checks
      `vivado/*.tcl` and `constr/*.xdc` with `tclsh`, no Vivado needed, and exercises the Python
      generators under `tools/test_*.py`).

## Simulation cross-check (do this first, costs nothing)

- [ ] `make test` — runs, in order: `sim` (all 12 testbenches under `sim/tb/tb_*.sv` print `PASS`:
      `tb_rst_sync`, `tb_cdc`, `tb_axis_async_fifo`, `tb_button_debounce`, `tb_rom_init`,
      `tb_clk_gen`, `tb_st7789_spi_master`, `tb_st7789_ctrl`, `tb_framebuffer`, `tb_osd`,
      `tb_ui_ctrl`, `tb_lcd_test_top`), `lint` (Verilator), `tclcheck` (Tcl/XDC syntax), and
      `pytests` (each `tools/test_*.py`) — stopping at the first failure.
- [ ] Open `sim/build/tb_lcd_test_top.ppm` (written by `tb_lcd_test_top.sv`) and confirm it shows the
      expected 160×64 window (20 text columns × 4 rows: header row, three list rows, the bars/gradient
      boundary at y = 42) before spending time on real hardware.

## Build

1. On the Vivado machine, from the repo root:
   ```
   vivado -mode batch -source vivado/build.tcl -tclargs lcd_test_top <SYS_CLK_IN_HZ>
   ```
   Outputs land in `vivado/out/`: `lcd_test_top.bit`, `lcd_test_top.dcp`, `lcd_test_top_synth.dcp`,
   `lcd_test_top_util.rpt`, `lcd_test_top_timing.rpt`, `lcd_test_top_drc.rpt`, and (if any
   `ASYNC_REG` cells survive) `lcd_test_top_async_reg.rpt`.
2. **Read the log before doing anything else:**
   - No `WARNING: ports without PACKAGE_PIN ...` naming an LCD or button port (see Prerequisites).
   - Grep for `[Vivado 12-1411]` (empty object list) near the `CLOCK_DEDICATED_ROUTE` constraint in
     `constr/ad9363.xdc` (line targeting `u_mmcm/CLKIN1`) — this constraint's `get_pins` must resolve
     once `lcd_test_top` is the actual top, so an empty match here is worth chasing down.
   - Grep for the same `[Vivado 12-1411]` around the `axis_async_fifo` `set_max_delay` constraints in
     `constr/timing.xdc` (the `fifo_wr_ptr`/`fifo_rd_ptr`/`wr2rd_sync`/`rd2wr_sync` `get_cells`
     lookups) — **these are expected to match nothing** for this M1 top (no `axis_async_fifo` is
     instantiated yet), so an empty match here is fine and not a regression.
3. Check `lcd_test_top_async_reg.rpt`: it should list the `rst_sync`/`cdc_sync`/`button_debounce`
   synchroniser stage registers with `ASYNC_REG = TRUE`. Then check `report_utilization` /
   `report_cells` (or the util report) that no `SRL16E`/`SRLC32E` was inferred for the `cdc_sync`
   stage registers, **and also for `rst_sync`'s `shreg`** — Vivado can fold shift-register-shaped
   flops into an `SRL` primitive, which silently defeats the synchroniser (no `ASYNC_REG` on an
   `SRL`, and its internal delay path breaks the metastability guarantee).
4. Check `lcd_test_top_util.rpt`: framebuffer (`320×240×16`) should use approximately 38 RAMB36,
   and total BRAM usage should be well under the part's 140 RAMB36 (`xc7z020clg400-1`).
5. `vivado/build.tcl` gates the bitstream on timing itself: after `route_design` it reads back
   worst setup and hold slack and, if either is negative, prints
   `ERROR: timing not met (WNS=... WHS=...)` and exits 1 without writing `<top>.dcp`/`<top>.bit`
   (there is no override flag for this one — fix the timing violation instead). If the build did
   reach `BUILD DONE`, still check `lcd_test_top_timing.rpt`: WNS >= 0 at 100 MHz (the internal `sys_clk` domain), and
   `lcd_test_top_drc.rpt`: no `UCIO-1` violation for the LCD pins (`UCIO-1` is downgraded to a
   warning globally in `constr/ad9363.xdc` for the AD9361 pins that aren't wired yet — that's
   expected and unrelated to the LCD pins, which should have real sites once step 1's prerequisite
   is done).

## Program and verify

6. Program: `vivado -mode batch -source vivado/program.tcl -tclargs vivado/out/lcd_test_top.bit`
7. Expected on the panel within ~0.5 s (from `test_pattern_gen.sv` + `ui_demo.sv`):
   - A 1-pixel white border around the frame.
   - Top 2/3 of the screen: 8 SMPTE-style colour bars (white, yellow, cyan, green, magenta, red,
     blue, black), left to right.
   - Bottom 1/3: a horizontal grey gradient (dark to light, left to right).
   - Row 0, column 0: channel label `A1 5865` (channel 0's name + frequency in MHz).
   - Row 0, column 12: the string `TEST`.
   - Right-hand column (starting at `COLS - 8`): three channel names, one per row below row 0,
     with the first one drawn in green (the currently-selected entry).
8. Short button press: the green highlight moves to the next entry down the list
   (0 -> 1 -> 2 -> 0, wrapping).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Blank / white screen | RESX not wired, or never pulses low at power-up | Scope `lcd_resx_n`; check wiring. Also try `INVERT = False` in `tools/gen_st7789_rom.py` |
| Colours look inverted | Panel's polarity differs from the `INVON` sent | Toggle `INVERT` in `tools/gen_st7789_rom.py`, `make gen`, rebuild |
| Image mirrored / rotated | Wrong `MADCTL` for this panel's orientation | Change `MADCTL` in `tools/gen_st7789_rom.py` (bit7=MY, bit6=MX, bit5=MV: `0x60` = MV\|MX landscape (current default), `0xA0` = MV\|MY landscape (other direction), `0x00`/`0xC0` = portrait), `make gen`, rebuild |
| Image shifted or wraps around | Panel is 240x240 or has a column/row offset | Adjust the CASET/RASET start offsets in `tools/gen_st7789_rom.py`, `make gen`, rebuild |
| Washed out or too dark | VCOMS/VRHS mismatch for this panel | Try `VCOMS` (cmd 0xBB, datasheet p.266, full range `0x00`..`0x3F` = 0.1..1.675 V) in the typical tuning range `0x19`..`0x2B`, `VRHS` (cmd 0xC3, p.271) in the typical tuning range `0x0B`..`0x15` — both panel-dependent, no fixed correct value, `make gen`, rebuild |
| Frame rate too slow / want faster refresh, and/or an artifact appears at CLK_DIV 2 or 1 | SPI clock conservative at reset; CLK_DIV 2/1 are overclocks, not a spec range to sweep | `SPI_CLK_DIV` on `lcd_test_top`: only **4 (12.5 MHz) is within the ST7789V datasheet's SPI maximum** (tSCYCW = 66 ns minimum cycle time -> 15.15 MHz max). **2 (25 MHz) and 1 (50 MHz) are out-of-spec overclocks** that many panels happen to tolerate, not a supported range. If you raise `SPI_CLK_DIV` below 4 and see *any* artifact (tearing, noise, garbled pixels, wrong colours) on a scope or the panel, that means **stop and drop back to a slower divider** — do not treat it as something to tune around. Scope `lcd_sclk` rise time regardless (<= 15 ns required by the datasheet) |
| Nothing happens, no `WARNING` about pins, build looks clean | `SYS_CLK_IN_HZ` argument doesn't match the real oscillator | Re-measure pin N18 (scope/frequency counter) or check the schematic; rerun `build.tcl` with the correct value |
| Build aborts with `clk_gen: ... outside MMCM CLKIN range` or `no MMCM solution` | `SYS_CLK_IN_HZ` argument outside 10–800 MHz, or its PFD-divided value outside 19–450 MHz | Re-check the measured oscillator frequency; the solver in `src/common/clk_gen.sv` cannot produce 100 MHz from every input |
| Button does nothing | Debounce/long-press timing, or `btn_n` polarity/pull-up | Confirm `btn_n` is pulled up (`constr/board_io.xdc` sets `PULLUP true`) and idles high; short press should register within `BTN_DEBOUNCE_MS` (20 ms default) |
