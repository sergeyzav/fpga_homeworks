# FPV 5.8 GHz detector on PlutoSDR (Zynq 7020, PL only)

## Status

M0 (project skeleton, common CDC/reset blocks) and M1 (ST7789V test pattern + OSD + button demo,
`src/top/lcd_test_top.sv`) are complete and passing in simulation (`make sim`, 12/12 testbenches).
Hardware bring-up is pending: `constr/board_io.xdc` still needs real `PACKAGE_PIN`s for the LCD and
button, and the board's oscillator frequency on pin N18 (`SYS_CLK_IN_HZ`) is not yet measured. See
`docs/bringup-m1.md` for the full bring-up checklist.

Design spec: `docs/superpowers/specs/2026-09-22-fpv-detector-design.md`.

## Setup (macOS)
    brew install icarus-verilog verilator
    make venv          # python3 -m venv .venv && pip install numpy scipy pillow
    make gen           # regenerate mem/*.mem and mem/*.hex from tools/
    make sim           # run every testbench (sim/tb/tb_*.sv) with Icarus
    make -C sim tb_st7789_ctrl WAVES=1   # single test with VCD in sim/build/
    make lint          # Verilator lint of the RTL
    make test          # sim + lint + tclcheck + pytests, in that order; fails on first error

## Vivado (on the build machine, from the repo root)
    vivado -mode batch -source vivado/build.tcl -tclargs lcd_test_top <SYS_CLK_IN_HZ>
    vivado -mode batch -source vivado/program.tcl -tclargs vivado/out/lcd_test_top.bit
    make tclcheck      # syntax-check vivado/*.tcl and constr/*.xdc with tclsh, no Vivado needed

`make tclcheck` sources each file under a bare `tclsh` with Vivado-specific commands stubbed
out (an `unknown` proc that swallows them, plus a dummy `get_hw_devices`), so it only proves
the Tcl parses cleanly (no unbalanced braces/quotes) — it does not run a real build or program
step. It creates `vivado/out/clk_in.xdc` as a side effect of exercising `build.tcl`; that path
is gitignored.

`make test` runs `sim`, `lint`, `tclcheck`, then `pytests` (each `tools/test_*.py` under
`$(PYTHON)`), stopping at the first failure — the aggregate target for CI or a pre-push check.

Layout: `src/` RTL (SystemVerilog), `sim/` testbenches and models, `mem/` ROM images,
`tools/` generators, `vivado/` Tcl, `constr/` XDC, `docs/` bring-up and design docs.
