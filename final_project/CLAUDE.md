# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Standalone FPV 5.8 GHz detector on a PlutoSDR (Zynq 7020, PL only, no PS/Linux): the AD9363 scans the
40 analog FPV channels, demodulates the selected one and shows video plus an OSD on an ST7789V 320x240
LCD over 4-wire SPI. Milestones M0 (skeleton, CDC/reset blocks) and M1 (LCD test pattern + OSD + button,
`src/top/lcd_test_top.sv`) are done in simulation; hardware bring-up is pending (`docs/bringup-m1.md`).
The RF/video path (M2+) does not exist yet. `ad9363/` is a vendor AD9361 Vivado example kept for
reference only (`AD936X_Driver.v` there is known-buggy dead code; do not reuse it).

Design spec: `docs/superpowers/specs/2026-09-22-fpv-detector-design.md`.
Implementation plan: `docs/superpowers/plans/2026-09-22-m0-m1-foundation-lcd.md`.

## Commands (run everything from the repo root)

```
brew install icarus-verilog verilator     # one-time
make venv                                 # .venv with numpy/scipy/pillow
make gen                                  # regenerate mem/*.mem, mem/*.hex from tools/gen_*.py

make sim                                  # all testbenches (sim/tb/tb_*.sv) with Icarus
make -C sim tb_st7789_ctrl                # one testbench (target = file stem)
make -C sim tb_st7789_ctrl WAVES=1        # same, VCD written to sim/build/
make -C sim list                          # list testbench targets
make lint                                 # Verilator -Wall lint, top = lcd_test_top
make tclcheck                             # parse vivado/*.tcl + constr/*.xdc with bare tclsh (no Vivado)
make pytests                              # tools/test_*.py
make test                                 # sim + lint + tclcheck + pytests, stops at first failure
make clean                                # rm sim/build
```

- Icarus flags come from `sim/Makefile`: `-g2012 -DSIM -Isrc -Isim/models`; every RTL file plus
  `sim/models/*.sv` is compiled into each testbench. `$readmemh` paths are `mem/...` relative to the cwd,
  so simulations and Vivado must be launched from the repo root.
- `sim/build/*.vvp` is rebuilt on mtime; after a quick edit-and-rerun within the same second the stale
  `.vvp` may be reused (Make 3.81 granularity) — `make -C sim clean` first when a change seems ignored.
- Testbenches print `PASS <tb_name>` and exit non-zero via `$fatal(1, ...)` on failure. `tb_clk_gen`
  deliberately instantiates a 27 MHz `clk_gen` with no MMCM solution; its `ERROR: ... no MMCM solution`
  line at time 0 is expected output, not a failure.
- Vivado runs on another machine, batch only:
  `vivado -mode batch -source vivado/build.tcl -tclargs lcd_test_top <SYS_CLK_IN_HZ>` then
  `vivado/program.tcl`. `build.tcl` refuses to write a bitstream on negative WNS or unplaced ports.

## RTL conventions (enforced across `src/`)

- `always_ff @(posedge clk)` with synchronous active-low `rst_n` (`if (!rst_n) ... else ...`). Only
  `rst_sync` has an async reset (it turns the MMCM `locked` into `rst_n`; there is no reset pin).
- Ports are `logic` packed vectors only — no interfaces or unpacked struct ports (Icarus 13 limitation).
  Untyped string parameters (`parameter INIT_FILE = ""`) for the same reason.
- Every module `` `include "common/defs.svh" `` (include path is `src/`). It provides `` `MEM_DIR ``
  (default `"mem"`, used as `` {`MEM_DIR, "/name.mem"} ``) and `` `PARAM_CHECK(g_chk_x, COND, ("msg %0d", V)) ``
  for parameter guards: under `-DSIM` it is a non-fatal `initial $error` (so TBs can instantiate bad
  parameters on purpose), otherwise an elaboration-time `$error` in a named generate block so Vivado
  stops. Use it for all new parameter guards; no trailing semicolon at the call site.
- Synthesis-only primitives (`MMCME2_BASE`, `BUFG`) live under `` `ifndef SIM `` with a behavioural
  shim in the `` `ifdef SIM `` branch. No Xilinx IP cores anywhere; everything must simulate in Icarus.
- Output pins that go to the LCD are dedicated registers with no internal fan-out so they can be
  packed into IOBs (`constr/board_io.xdc` sets `IOB TRUE`); `st7789_spi_master` keeps internal
  copies (`sclk_r`, `cs_n_r`) and drives the ports from replicas loaded on the same edge.
- Lint must stay clean under `verilator --lint-only -Wall -DSIM -Wno-DECLFILENAME -Wno-UNUSEDPARAM`;
  use scoped `/* verilator lint_off ... */` pairs, not global waivers.
- The plan document mirrors every committed RTL file in a fenced code block under `### Task N:`.
  When you change a module, update its plan block to stay byte-identical (this is checked by review).

## Architecture: the M1 display chain

Single 100 MHz `sys_clk` domain (`clk_gen` MMCM from board clock `i_clk`, `SYS_CLK_IN_HZ` parameter
shared between RTL and `vivado/build.tcl`; the board oscillator frequency is still unmeasured).

```
test_pattern_gen ──wr──▶ framebuffer (BRAM, 2-clk read) ──┐
                                                          ▼
ui_demo ─job─▶ ui_ctrl ─txt_we─▶ osd_text_ram ─▶ osd_compositor (3-clk pix latency) ─pix_data─▶ st7789_ctrl ─tx─▶ st7789_spi_master ─▶ LCD pins
               (chan_names.hex,                  (font8x16.hex)                                  (st7789_init.mem)
                ui_strings.hex)
button_debounce ─short_press─▶ sel ─▶ ui_demo
```

- `st7789_ctrl` drives the panel: hardware reset → walks `mem/st7789_init.mem` (16-bit words:
  `[15:14]` 0=cmd, 1=data, 2=delay ticks, 3=end) → streams frames forever (CASET/RASET/RAMWR +
  WIDTH*HEIGHT RGB565 pixels). Delay ticks are ms on hardware, us with `SIM_FAST=1`.
- **Pixel-source contract**: `pix_x/pix_y` change only when a pixel is latched, and `pix_data` is
  sampled no earlier than the (`PIX_LAT`+1)-th edge after the address changes. `osd_compositor` has
  exactly 3 clocks of latency (framebuffer 2-clock path and text-RAM→font-ROM path meet, then one
  output register); `lcd_test_top` uses `PIX_LAT=6`. A guard rejects `PIX_LAT` large enough to stall SPI.
- `osd_compositor` overlays 8x16 glyphs: text-RAM byte = `{highlight, ascii[6:0]}`, chars <= 0x20 are
  transparent, ink white (green when highlighted), cell background = framebuffer dimmed by half.
- `ui_ctrl` job handshake: `job_valid && job_ready` accepts one 8-character string write (16 clocks,
  writes at row*COLS+col+i); `job_src` selects channel-name ROM (idx 0..38) vs fixed-string ROM
  (idx 0..15, indices defined in `tools/gen_ui_strings.py`; only `idx[3:0]` is decoded).
- `test_pattern_gen` fills the framebuffer once at reset release (border, 8 colour bars, grey
  gradient); at 320x240 this finishes inside `st7789_ctrl`'s 120 ms post-reset wait, so the first
  streamed frame is complete. With `SIM_FAST` that wait is 120 us — TBs use small windows (e.g. 160x64).
- `st7789_spi_master`: mode 0, MSB first, `SCLK = clk/(2*CLK_DIV)`; `cs_req` is a level, `tx_ready`
  rises 3 clocks after CS falls (tCSS) and CS is held through any byte accepted that clock.

## Simulation model and ROM generators

- `sim/models/st7789v_slave_model.sv` is a behavioural ST7789V that decodes the SPI protocol, checks
  real datasheet timings (in ns) and reconstructs the frame (`panel.pixel(x, y)`, `n_frames`,
  `n_errors`). TBs with a `SIM_FAST` controller must pass timing parameters scaled ms→us, as
  `tb_lcd_test_top` does. Exact-pixel expectations in `tb_framebuffer`/`tb_lcd_test_top` pin the
  pattern and glyph placement, so pattern/OSD changes need matching TB updates.
- `mem/*` is generated by `tools/gen_*.py` (`make gen`) from `tools/fpv_channels.py` (the shared
  40-channel table) and the ST7789V datasheet register values. `mem/font8x16.hex` is rendered from a
  system TTF and is not byte-reproducible across OS/Pillow versions — treat the committed file as the
  reference and only regenerate deliberately.
