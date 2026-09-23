# M0+M1 — Foundation, Tooling and LCD Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the SystemVerilog project skeleton (sim flow, common CDC/reset blocks, Vivado Tcl) and get a test pattern plus OSD text onto the ST7789V panel over SPI — the first hardware-visible milestone of the FPV detector.

**Architecture:** Pure SystemVerilog, one `sys_clk` (100 MHz from MMCM) domain for everything in this plan. `st7789_ctrl` walks an init ROM, then streams frames forever, pulling pixels through `osd_compositor`, which overlays 8×16 text from `osd_text_ram` onto the BRAM `framebuffer`. `ui_ctrl` writes strings (channel names from a ROM) into the text RAM. A `test_pattern_gen` fills the framebuffer. Every module has an Icarus testbench; an ST7789V SPI slave model reconstructs the frame as a PPM image.

**Tech Stack:** SystemVerilog-2012 (subset accepted by Icarus `-g2012`, Verilator, Vivado), Icarus Verilog, Verilator (lint), Python 3 (+numpy/pillow in `.venv`) for ROM generators, Vivado batch Tcl (run on another machine), GNU Make.

**Spec:** `docs/superpowers/specs/2026-09-22-fpv-detector-design.md`

---

## Conventions (read first)

- All RTL: `always_ff @(posedge clk)` with **synchronous active-low `rst_n`** (`if (!rst_n) ... else ...`). Only `rst_sync` uses an async reset.
- Ports: `logic` only, packed vectors, no interfaces / unpacked struct ports (Icarus).
- Memory init files are referenced as `` {`MEM_DIR, "/name.mem"} ``; `` `MEM_DIR `` defaults to `"mem"`. **Always run Icarus and Vivado from the repo root.**
- Simulation macro: `-DSIM` is passed by the Makefile; synthesis-only primitives live under `` `ifndef SIM ``.
- Testbenches print `PASS <tb_name>` on success and call `$fatal(1, ...)` on failure (non-zero `vvp` exit code).
- The repo is **not a git repository** yet. Commit steps assume the user ran `git init`; if not, skip them.
- Homebrew tools: `brew install icarus-verilog verilator` (user runs this). Python: `.venv/bin/python`.

## File structure (this plan)

```
Makefile                         top-level: delegates to sim/Makefile, tools targets
requirements.txt                 numpy scipy pillow
.gitignore
README.md
src/common/rst_sync.sv           async-assert / sync-deassert reset synchroniser
src/common/cdc_sync.sv           N-bit 2-flop level synchroniser
src/common/cdc_pulse.sv          toggle-based single-pulse crossing
src/common/axis_async_fifo.sv    dual-clock AXI4-Stream FIFO, Gray pointers, overflow flag
src/common/button_debounce.sv    debounce + short/long press pulses
src/common/rom_init.sv           generic synchronous ROM from $readmemh
src/common/clk_gen.sv            MMCME2_BASE wrapper (sim shim generates 100 MHz)
src/display/st7789_spi_master.sv byte-level 4-wire SPI master, mode 0, registered pins
src/display/st7789_ctrl.sv       reset → init ROM → endless frame streaming
src/display/framebuffer.sv       320×240×16 dual-port BRAM
src/display/test_pattern_gen.sv  colour bars + gradient writer
src/display/osd_text_ram.sv      40×15 character RAM
src/display/osd_compositor.sv    framebuffer + font overlay → pixel
src/display/ui_ctrl.sv           string writer (channel names ROM, fixed strings ROM)
src/top/lcd_test_top.sv          M1 hardware top
mem/st7789_init.mem, mem/font8x16.hex, mem/chan_names.hex, mem/ui_strings.hex
tools/fpv_channels.py            the 40-channel table (shared by later plans)
tools/gen_st7789_rom.py, tools/gen_font.py, tools/gen_chan_names.py, tools/gen_ui_strings.py
sim/Makefile                     tb_<name> targets, lint, gen
sim/models/st7789v_slave_model.sv
sim/tb/tb_<module>.sv            one per module
vivado/build.tcl, vivado/create_project.tcl, vivado/program.tcl
constr/ad9363.xdc, constr/board_io.xdc, constr/timing.xdc
```

---

### Task 1: Repository skeleton and simulation Makefile

**Files:**
- Create: `.gitignore`, `requirements.txt`, `README.md`, `Makefile`, `sim/Makefile`, `src/common/.keep`, `src/display/.keep`, `src/rf/.keep`, `src/video/.keep`, `src/top/.keep`, `sim/tb/.keep`, `sim/models/.keep`, `sim/gen/.keep`, `mem/.keep`, `tools/.keep`, `vivado/.keep`, `constr/.keep`

- [ ] **Step 1: Create directories and static files**

```bash
cd /Users/user/myprojects/st7789v
mkdir -p src/common src/display src/rf src/video src/top sim/tb sim/models sim/gen sim/build mem tools vivado constr docs
touch src/common/.keep src/display/.keep src/rf/.keep src/video/.keep src/top/.keep sim/tb/.keep sim/models/.keep sim/gen/.keep mem/.keep tools/.keep vivado/.keep constr/.keep
cat > .gitignore <<'EOT'
.venv/
sim/build/
*.vcd
*.fst
*.ppm
*.png
!docs/**/*.png
vivado/out/
vivado/*.log
vivado/*.jou
.Xil/
.idea/
__pycache__/
EOT
cat > requirements.txt <<'EOT'
numpy
scipy
pillow
EOT
```

- [ ] **Step 2: Write `sim/Makefile`**

```make
# Run from repo root:  make -C sim tb_rst_sync   |  make -C sim all  |  make -C sim lint
ROOT      := $(abspath ..)
IVERILOG  ?= iverilog
VVP       ?= vvp
VERILATOR ?= verilator
PYTHON    ?= $(ROOT)/.venv/bin/python
BUILD     := $(ROOT)/sim/build
SHELL     := bash
.SHELLFLAGS := -o pipefail -c

SRCS   := $(shell find $(ROOT)/src -name '*.sv' | sort)
MODELS := $(shell find $(ROOT)/sim/models -name '*.sv' | sort)
TBS    := $(sort $(patsubst $(ROOT)/sim/tb/%.sv,%,$(wildcard $(ROOT)/sim/tb/tb_*.sv)))

IVFLAGS := -g2012 -DSIM -Wall -Wno-timescale -I$(ROOT)/src -I$(ROOT)/sim/models
ifdef WAVES
IVFLAGS += -DWAVES
endif

.PHONY: all list lint clean $(TBS)

all: $(TBS)

list:
	@echo $(TBS)

# Each tb_<name> target compiles all RTL + models + that testbench and runs it from the repo root
$(TBS): %: $(BUILD)/%.vvp
	cd $(ROOT) && $(VVP) -N $<

$(BUILD)/%.vvp: $(ROOT)/sim/tb/%.sv $(SRCS) $(MODELS) | $(BUILD)
	cd $(ROOT) && $(IVERILOG) $(IVFLAGS) -s $* -o $@ $(SRCS) $(MODELS) $<

$(BUILD):
	mkdir -p $(BUILD)

lint: | $(BUILD)
	cd $(ROOT) && set -o pipefail && $(VERILATOR) --lint-only -Wall -DSIM -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
	  -Isrc $(SRCS) --top-module lcd_test_top 2>&1 | tee $(BUILD)/lint.log

clean:
	rm -rf $(BUILD)
```

Note: `vvp -N` makes `$fatal`/`$stop` return a non-zero exit code so `make` fails on a failing test.

- [ ] **Step 3: Write top-level `Makefile` and `README.md`**

```make
# Top-level convenience targets. Simulation lives in sim/Makefile.
PYTHON ?= .venv/bin/python

.PHONY: sim lint gen venv clean
sim:
	$(MAKE) -C sim all
lint:
	$(MAKE) -C sim lint
gen:
	$(PYTHON) tools/gen_st7789_rom.py
	$(PYTHON) tools/gen_font.py
	$(PYTHON) tools/gen_chan_names.py
	$(PYTHON) tools/gen_ui_strings.py
venv:
	python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
clean:
	$(MAKE) -C sim clean
```

```markdown
# FPV 5.8 GHz detector on PlutoSDR (Zynq 7020, PL only)

Design spec: `docs/superpowers/specs/2026-09-22-fpv-detector-design.md`.

## Setup (macOS)
    brew install icarus-verilog verilator
    make venv          # python3 -m venv .venv && pip install numpy scipy pillow
    make gen           # regenerate mem/*.mem and mem/*.hex from tools/
    make sim           # run every testbench (sim/tb/tb_*.sv) with Icarus
    make -C sim tb_st7789_ctrl WAVES=1   # single test with VCD in sim/build/
    make lint          # Verilator lint of the RTL

## Vivado (on the build machine, from the repo root)
    vivado -mode batch -source vivado/build.tcl -tclargs lcd_test_top 100000000
    vivado -mode batch -source vivado/program.tcl -tclargs vivado/out/lcd_test_top.bit

Layout: `src/` RTL (SystemVerilog), `sim/` testbenches and models, `mem/` ROM images,
`tools/` generators, `vivado/` Tcl, `constr/` XDC.
```

- [ ] **Step 4: Verify the Makefile parses**

Run: `cd /Users/user/myprojects/st7789v && make -C sim list`
Expected: prints an empty line (no testbenches yet), exit code 0.

- [ ] **Step 5: Commit**

```bash
git add .gitignore requirements.txt README.md Makefile sim/Makefile src sim mem tools vivado constr
git commit -m "chore: project skeleton and simulation Makefile"
```

---

### Task 2: `rst_sync` — reset synchroniser

**Files:**
- Create: `src/common/rst_sync.sv`
- Test: `sim/tb/tb_rst_sync.sv`

- [ ] **Step 1: Write the failing test**

```systemverilog
`timescale 1ns/1ps
module tb_rst_sync;
  localparam int N_STAGES = 4;

  // arst_n starts high and is asserted at t=1 from the initial block: a time-0 declaration
  // initialiser races the always_ff process start in Icarus, so the negedge would be missed.
  logic clk = 0, arst_n = 1, rst_n;
  always #5 clk = ~clk;

  rst_sync #(.N_STAGES(N_STAGES)) dut (.clk(clk), .arst_n(arst_n), .rst_n(rst_n));

  // global watchdog
  initial begin #1000; $fatal(1, "timeout"); end

  int cycles;
  initial begin
    // asynchronous assertion: rst_n must be low immediately, without a clock
    #1 arst_n = 0;
    #1 if (rst_n !== 1'b0) $fatal(1, "rst_n not low while arst_n low");
    repeat (3) @(posedge clk);
    #1 arst_n = 1;
    // deassertion must take exactly N_STAGES rising edges
    cycles = 0;
    while (rst_n !== 1'b1) begin @(posedge clk); #1 cycles++; if (cycles > 10) $fatal(1, "never deasserted"); end
    if (cycles != N_STAGES) $fatal(1, "deasserted after %0d cycles, expected %0d", cycles, N_STAGES);
    // re-assert asynchronously mid-cycle
    #2 arst_n = 0;
    #1 if (rst_n !== 1'b0) $fatal(1, "async re-assert failed");
    $display("PASS tb_rst_sync");
    $finish;
  end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_rst_sync`
Expected: iverilog error `Unknown module type: rst_sync`.

- [ ] **Step 3: Write the implementation**

```systemverilog
`include "common/defs.svh"
// Reset synchroniser: asynchronous assertion, synchronous deassertion after N_STAGES clocks.
// N_STAGES must be >= 2 (one stage cannot filter metastability on the deassertion edge).
module rst_sync #(
  parameter int N_STAGES = 4
) (
  input  logic clk,
  input  logic arst_n,   // asynchronous active-low reset (e.g. ~mmcm_locked)
  output logic rst_n     // synchronous active-low reset for this clock domain
);
  (* ASYNC_REG = "TRUE" *) logic [N_STAGES-1:0] shreg;

  `PARAM_CHECK(g_chk_stages, N_STAGES < 2, ("rst_sync: N_STAGES must be >= 2"))

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) shreg <= '0;
    else         shreg <= N_STAGES'({shreg, 1'b1});  // explicit truncation to N_STAGES bits
  end

  assign rst_n = shreg[N_STAGES-1];
endmodule
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C sim tb_rst_sync`
Expected: `PASS tb_rst_sync`

- [ ] **Step 5: Commit**

```bash
git add src/common/rst_sync.sv sim/tb/tb_rst_sync.sv
git commit -m "feat(common): reset synchroniser with test"
```

---

### Task 3: `cdc_sync` and `cdc_pulse`

**Files:**
- Create: `src/common/cdc_sync.sv`, `src/common/cdc_pulse.sv`
- Test: `sim/tb/tb_cdc.sv`

- [ ] **Step 1: Write the failing test**

```systemverilog
`timescale 1ns/1ps
// Stimulus uses nonblocking assignments at posedge so the DUT flops sample the
// previous value (avoids a same-timestep race with blocking assignments).
module tb_cdc;
  logic clk_a = 0, clk_b = 0, rst_a_n = 0, rst_b_n = 0;
  always #5  clk_a = ~clk_a;   // 100 MHz
  always #6.25 clk_b = ~clk_b; // 80 MHz

  logic [3:0] lvl_a = 0, lvl_b;
  cdc_sync #(.WIDTH(4)) u_lvl (.clk(clk_b), .d(lvl_a), .q(lvl_b));

  logic pulse_a = 0, pulse_b;
  cdc_pulse u_pulse (.clk_src(clk_a), .rst_src_n(rst_a_n), .pulse_src(pulse_a),
                     .clk_dst(clk_b), .rst_dst_n(rst_b_n), .pulse_dst(pulse_b));

  int got = 0;
  always @(posedge clk_b) if (pulse_b) got++;

  initial begin
    repeat (3) @(posedge clk_a); rst_a_n <= 1; rst_b_n <= 1;
    // level: value appears after 2 clk_b edges
    @(posedge clk_a); lvl_a <= 4'hA;
    // must NOT be visible before any clk_b edge (proves the flops are in the path)
    @(negedge clk_a);
    if (lvl_b !== 4'h0) $fatal(1, "cdc_sync bypassed: value visible before clk_b edges");
    repeat (3) @(posedge clk_b); #1;
    if (lvl_b !== 4'hA) $fatal(1, "cdc_sync did not pass value, got %h", lvl_b);
    // pulse: 5 well-separated pulses -> 5 single-cycle pulses in dst
    repeat (5) begin
      @(posedge clk_a); pulse_a <= 1; @(posedge clk_a); pulse_a <= 0;
      repeat (8) @(posedge clk_a);
    end
    repeat (10) @(posedge clk_b);
    if (got != 5) $fatal(1, "expected 5 dst pulses, got %0d", got);
    // pulse_dst must be exactly one clk_b wide
    got = 0;
    @(posedge clk_a); pulse_a <= 1; @(posedge clk_a); pulse_a <= 0;
    repeat (10) @(posedge clk_b);
    if (got != 1) $fatal(1, "pulse width wrong: counted %0d", got);
    $display("PASS tb_cdc");
    $finish;
  end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_cdc`
Expected: `Unknown module type: cdc_sync`.

- [ ] **Step 3: Write the implementations**

`src/common/cdc_sync.sv`:
```systemverilog
`include "common/defs.svh"
// N-bit level synchroniser (2 flops by default). Only for quasi-static / single-bit signals:
// individual bits may arrive in different cycles.
module cdc_sync #(
  parameter int WIDTH  = 1,
  parameter int STAGES = 2
) (
  input  logic             clk,
  input  logic [WIDTH-1:0] d,
  output logic [WIDTH-1:0] q
);
  `PARAM_CHECK(g_chk_stages, STAGES < 2, ("cdc_sync: STAGES must be >= 2"))

  (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] stage [STAGES];

  always_ff @(posedge clk) begin
    stage[0] <= d;
    for (int i = 1; i < STAGES; i++) stage[i] <= stage[i-1];
  end
  assign q = stage[STAGES-1];
endmodule
```

`src/common/cdc_pulse.sv`:
```systemverilog
// Single-cycle pulse crossing via toggle flop. Source pulses must be spaced by
// at least ~3 destination clock periods; otherwise pulses merge.
// Reset ordering: both domains must be out of reset before the first pulse_src; a dst reset
// released while toggle_src is already 1 produces one spurious pulse_dst.
module cdc_pulse (
  input  logic clk_src,
  input  logic rst_src_n,
  input  logic pulse_src,
  input  logic clk_dst,
  input  logic rst_dst_n,
  output logic pulse_dst
);
  logic toggle_src;
  always_ff @(posedge clk_src) begin
    if (!rst_src_n)     toggle_src <= 1'b0;
    else if (pulse_src) toggle_src <= ~toggle_src;
  end

  (* ASYNC_REG = "TRUE" *) logic [2:0] sync_dst;
  always_ff @(posedge clk_dst) begin
    if (!rst_dst_n) sync_dst <= '0;
    else            sync_dst <= {sync_dst[1:0], toggle_src};
  end
  assign pulse_dst = sync_dst[2] ^ sync_dst[1];
endmodule
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C sim tb_cdc`
Expected: `PASS tb_cdc`

- [ ] **Step 5: Commit**

```bash
git add src/common/cdc_sync.sv src/common/cdc_pulse.sv sim/tb/tb_cdc.sv
git commit -m "feat(common): level and pulse CDC synchronisers"
```

---

### Task 4: `axis_async_fifo` — dual-clock AXI4-Stream FIFO

**Files:**
- Create: `src/common/axis_async_fifo.sv`
- Test: `sim/tb/tb_axis_async_fifo.sv`

The test has two phases: first the reader outruns the writer so the FIFO never fills, then the reader is stalled to force a fill and wrap under back-pressure, which must set `s_overflow`; `s_overflow` means "a word offered while full was dropped" (a free-running source ignoring `s_tready`), and it is cleared by `s_rst_n`.

- [ ] **Step 1: Write the failing test**

```systemverilog
`timescale 1ns/1ps
module tb_axis_async_fifo;
  localparam int N          = 2000;  // words per phase
  localparam int DEPTH_LOG2 = 4;
  localparam int STALL      = 100;   // reader stall cycles at start of phase 2 (fills the FIFO)
  logic s_clk = 0, m_clk = 0, s_rst_n = 0, m_rst_n = 0;
  always #6.25 s_clk = ~s_clk;  // 80 MHz writer
  always #5    m_clk = ~m_clk;  // 100 MHz reader

  logic [31:0] s_tdata, m_tdata;
  logic s_tvalid, s_tready, m_tvalid, m_tready, s_overflow;

  axis_async_fifo #(.WIDTH(32), .DEPTH_LOG2(DEPTH_LOG2)) dut (
    .s_clk(s_clk), .s_rst_n(s_rst_n), .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tready(s_tready), .s_overflow(s_overflow),
    .m_clk(m_clk), .m_rst_n(m_rst_n), .m_tdata(m_tdata), .m_tvalid(m_tvalid), .m_tready(m_tready));

  // writer: sequential words 0..limit-1, 50 % offered, honours s_tready
  int wr_i = 0, limit = N, nxt;
  always @(posedge s_clk) begin
    if (!s_rst_n) begin s_tvalid <= 0; s_tdata <= 0; end
    else begin
      nxt = wr_i + ((s_tvalid && s_tready) ? 1 : 0);
      wr_i <= nxt;
      if (!s_tvalid || s_tready) begin
        s_tvalid <= (nxt < limit) && ($urandom_range(0, 3) > 1);
        s_tdata  <= nxt;
      end
    end
  end
  // reader: random stalls, checks order. While `stall` > 0 the reader is held off so the FIFO
  // fills and the writer sees back-pressure (exercises the full / Gray-pointer compare path).
  int rd_i = 0, stall = 0;
  always @(posedge m_clk) begin
    if (stall > 0) begin stall <= stall - 1; m_tready <= 0; end
    else m_tready <= ($urandom_range(0, 2) != 0);
    if (m_tvalid && m_tready) begin
      if (m_tdata !== rd_i) $fatal(1, "order error: got %0d expected %0d", m_tdata, rd_i);
      rd_i <= rd_i + 1;
    end
  end

  // back-pressure must be observed in phase 2, otherwise the full path is untested
  logic saw_backpressure = 0;
  always @(posedge s_clk) if (s_rst_n && s_tvalid && !s_tready) saw_backpressure <= 1;

  // occupancy = accepted - consumed; the FIFO holds 2**DEPTH_LOG2 words plus the output skid word
  int max_occ = 0;
  always @(posedge m_clk) if (wr_i - rd_i > max_occ) max_occ = wr_i - rd_i;

  initial begin
    repeat (4) @(posedge s_clk); s_rst_n = 1; m_rst_n = 1;

    // ---- phase 1: reader faster than writer on average, FIFO never fills ----
    wait (rd_i == N);
    repeat (10) @(posedge m_clk);
    if (saw_backpressure) $fatal(1, "phase 1: unexpected back-pressure");
    if (s_overflow) $fatal(1, "overflow flagged although s_tready respected");
    if (m_tvalid) $fatal(1, "extra data in FIFO");

    // ---- phase 2: stall the reader so the FIFO fills and wraps under back-pressure ----
    @(posedge m_clk); stall <= STALL; limit <= 2*N;
    wait (rd_i == 2*N);
    repeat (10) @(posedge m_clk);
    if (!saw_backpressure) $fatal(1, "phase 2: FIFO never filled, back-pressure path untested");
    if (!s_overflow) $fatal(1, "phase 2: s_overflow not flagged although a word was offered while full");
    if (m_tvalid) $fatal(1, "phase 2: extra data in FIFO");
    if (max_occ != (1 << DEPTH_LOG2) + 1)
      $fatal(1, "phase 2: max occupancy %0d, expected %0d", max_occ, (1 << DEPTH_LOG2) + 1);

    // ---- both resets asserted together clear the sticky overflow flag and the output register ----
    @(posedge s_clk); s_rst_n <= 0; m_rst_n <= 0;
    repeat (5) @(posedge s_clk);            // 62.5 ns: 5 s_clk / 6 m_clk cycles
    s_rst_n <= 1; m_rst_n <= 1;
    repeat (4) @(posedge m_clk); #1;
    if (s_overflow) $fatal(1, "s_overflow not cleared by reset");
    if (m_tvalid) $fatal(1, "m_tvalid not cleared by reset");

    $display("PASS tb_axis_async_fifo");
    $finish;
  end

  initial begin #200000; $fatal(1, "timeout"); end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_axis_async_fifo`
Expected: `Unknown module type: axis_async_fifo`.

- [ ] **Step 3: Write the implementation**

```systemverilog
`include "common/defs.svh"
// Dual-clock AXI4-Stream FIFO with Gray-code pointers.
// Depth = 2**DEPTH_LOG2 words. s_overflow goes sticky-high (cleared by s_rst_n) when a word is
// offered (s_tvalid) while the FIFO is full. For a free-running source that ignores s_tready
// (e.g. the IQ sample stream) this means the word was dropped. A source that honours s_tready
// and holds s_tvalid while waiting sets the flag too, so it is only meaningful for
// non-stalling sources.
//
// Reset contract: s_rst_n and m_rst_n must be asserted together, derived from one reset source
// (e.g. one rst_sync per clock fed by the same request), each held for at least 2 cycles of its
// own clock plus the synchroniser depth. Resetting one domain alone leaves the write and read
// pointers inconsistent and the FIFO emits stale data.
module axis_async_fifo #(
  parameter int WIDTH      = 32,
  parameter int DEPTH_LOG2 = 6
) (
  input  logic             s_clk,
  input  logic             s_rst_n,
  input  logic [WIDTH-1:0] s_tdata,
  input  logic             s_tvalid,
  output logic             s_tready,
  output logic             s_overflow,

  input  logic             m_clk,
  input  logic             m_rst_n,
  output logic [WIDTH-1:0] m_tdata,
  output logic             m_tvalid,
  input  logic             m_tready
);
  localparam int AW = DEPTH_LOG2;

  `PARAM_CHECK(g_chk_depth, DEPTH_LOG2 < 2, ("axis_async_fifo: DEPTH_LOG2 must be >= 2"))

  (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:(1<<AW)-1];

  // ---------------- write side ----------------
  logic [AW:0] wr_bin, wr_gray, rd_gray_in_wr;
  logic [AW:0] rd_bin, rd_gray, wr_gray_in_rd;
  wire         wr_fire = s_tvalid && s_tready;

  function automatic logic [AW:0] bin2gray(input logic [AW:0] b); return b ^ (b >> 1); endfunction

  always_ff @(posedge s_clk) begin
    if (!s_rst_n) begin
      wr_bin <= '0; wr_gray <= '0; s_overflow <= 1'b0;
    end else begin
      if (wr_fire) begin
        mem[wr_bin[AW-1:0]] <= s_tdata;
        wr_bin  <= wr_bin + 1'b1;
        wr_gray <= bin2gray(wr_bin + 1'b1);
      end
      if (s_tvalid && !s_tready) s_overflow <= 1'b1;
    end
  end

  // Multi-bit cdc_sync is valid here only because the pointer is Gray-coded: it changes one bit
  // per source clock edge, so a stale sample is a valid (older) pointer, never a mixed one.
  // The rd_gray -> rd_gray_in_wr path needs set_max_delay -datapath_only (one source clock
  // period) in constr/timing.xdc, not a false path.
  cdc_sync #(.WIDTH(AW+1)) u_rd2wr (.clk(s_clk), .d(rd_gray), .q(rd_gray_in_wr));
  // full when pointers differ only in the two MSBs
  wire full = (wr_gray == {~rd_gray_in_wr[AW:AW-1], rd_gray_in_wr[AW-2:0]});
  assign s_tready = s_rst_n && !full;

  // ---------------- read side ----------------
  // Same Gray-code argument and set_max_delay -datapath_only constraint for wr_gray -> wr_gray_in_rd.
  cdc_sync #(.WIDTH(AW+1)) u_wr2rd (.clk(m_clk), .d(wr_gray), .q(wr_gray_in_rd));
  wire empty = (rd_gray == wr_gray_in_rd);

  // registered output with one-word skid: m_tvalid high while output register holds data.
  // m_tdata is not reset (don't-care while m_tvalid=0) so it can absorb into the BRAM output register.
  always_ff @(posedge m_clk) begin
    if (!m_rst_n) begin
      rd_bin <= '0; rd_gray <= '0; m_tvalid <= 1'b0;
    end else begin
      if (!m_tvalid || m_tready) begin
        if (!empty) begin
          m_tdata  <= mem[rd_bin[AW-1:0]];
          m_tvalid <= 1'b1;
          rd_bin   <= rd_bin + 1'b1;
          rd_gray  <= bin2gray(rd_bin + 1'b1);
        end else begin
          m_tvalid <= 1'b0;
        end
      end
    end
  end
endmodule
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C sim tb_axis_async_fifo`
Expected: `PASS tb_axis_async_fifo`

- [ ] **Step 5: Commit**

```bash
git add src/common/axis_async_fifo.sv sim/tb/tb_axis_async_fifo.sv
git commit -m "feat(common): dual-clock AXI4-Stream FIFO"
```

---

### Task 5: `button_debounce`

**Files:**
- Create: `src/common/button_debounce.sv`
- Test: `sim/tb/tb_button_debounce.sv`

- [ ] **Step 1: Write the failing test**

```systemverilog
`timescale 1ns/1ps
// btn is driven at negedge clk so the DUT samples a stable value (no same-timestep race).
module tb_button_debounce;
  // 1 MHz clock, 1 ms debounce = 1000 cycles, 5 ms long press = 5000 cycles
  localparam int CLK_HZ = 1_000_000, DEBOUNCE_MS = 1, LONG_MS = 5;
  localparam int DEB_CYC  = (CLK_HZ / 1000) * DEBOUNCE_MS;
  localparam int LONG_CYC = (CLK_HZ / 1000) * LONG_MS;
  // Release latency: btn=1 (set after edge E_n) is sampled at E_n+1, crosses 2 sync flops and
  // DEB_CYC debounce edges, so pressed falls at E_n+DEB_CYC+2. The hold counter runs the whole
  // time pressed is high, i.e. hold = n + DEB_CYC + 2 cycles when n is measured from pressed rising.
  // long_press fires when the hold reaches LONG_CYC, so the boundary in n is:
  localparam int N_BOUND = LONG_CYC - DEB_CYC - 2; // n >= N_BOUND -> long, n < N_BOUND -> short

  logic clk = 0, rst_n = 0, btn = 1; // active-low button, idle high
  always #500 clk = ~clk;

  logic pressed, short_press, long_press;
  button_debounce #(.CLK_HZ(CLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS), .LONG_MS(LONG_MS), .ACTIVE_LOW(1)) dut
    (.clk(clk), .rst_n(rst_n), .btn(btn), .pressed(pressed), .short_press(short_press), .long_press(long_press));

  int n_short = 0, n_long = 0;
  always @(posedge clk) begin n_short += short_press; n_long += long_press; end

  task drive(input logic v);
    @(negedge clk); btn = v;
  endtask

  task press_for(input int cycles);
    drive(0); repeat (cycles) @(posedge clk); drive(1); repeat (1500) @(posedge clk);
  endtask

  // hold btn low until pressed rises, then for exactly n more clk edges before releasing
  task hold_from_pressed(input int n);
    drive(0); @(posedge pressed); repeat (n) @(posedge clk); drive(1); repeat (1500) @(posedge clk);
  endtask

  initial begin
    repeat (3) @(posedge clk); rst_n = 1;
    // glitch shorter than debounce -> ignored
    press_for(300);
    if (n_short != 0 || n_long != 0 || pressed) $fatal(1, "glitch not filtered");
    // 2 ms press -> one short press on release
    press_for(2000);
    if (n_short != 1 || n_long != 0) $fatal(1, "short press: short=%0d long=%0d", n_short, n_long);
    // 8 ms press -> one long press, no short
    press_for(8000);
    if (n_short != 1 || n_long != 1) $fatal(1, "long press: short=%0d long=%0d", n_short, n_long);
    // bouncing edge: 5 toggles of 100 cycles then held 3 ms -> exactly one short
    repeat (5) begin drive(0); repeat (100) @(posedge clk); drive(1); repeat (100) @(posedge clk); end
    press_for(3000);
    if (n_short != 2 || n_long != 1) $fatal(1, "bounce: short=%0d long=%0d", n_short, n_long);
    // exact boundary: hold of LONG_CYC-1 cycles -> short only
    hold_from_pressed(N_BOUND - 1);
    if (n_short != 3 || n_long != 1) $fatal(1, "boundary-1: short=%0d long=%0d", n_short, n_long);
    // exact boundary: hold of LONG_CYC cycles -> long only (pressed falls on the same edge long fires)
    hold_from_pressed(N_BOUND);
    if (n_short != 3 || n_long != 2) $fatal(1, "boundary: short=%0d long=%0d", n_short, n_long);
    $display("PASS tb_button_debounce");
    $finish;
  end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_button_debounce`
Expected: `Unknown module type: button_debounce`.

- [ ] **Step 3: Write the implementation**

```systemverilog
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C sim tb_button_debounce`
Expected: `PASS tb_button_debounce`

- [ ] **Step 5: Commit**

```bash
git add src/common/button_debounce.sv sim/tb/tb_button_debounce.sv
git commit -m "feat(common): button debounce with short/long press"
```

---

### Task 6: `rom_init` generic ROM and `defs.svh`

**Files:**
- Create: `src/common/defs.svh`, `src/common/rom_init.sv`, `sim/test_rom.mem`, `sim/test_rom6.mem` (test fixtures)
- Test: `sim/tb/tb_rom_init.sv`

- [ ] **Step 1: Write the test fixture and failing test**

`sim/test_rom.mem`:
```
// 8 words, 16 bit
0000
1111
2222
3333
4444
5555
6666
7777
```

`sim/test_rom6.mem` (added in code review: non-power-of-two `DEPTH` fixture):
```
// 6 words, 16 bit (non-power-of-two DEPTH fixture)
0000
1111
2222
3333
4444
5555
```

`sim/tb/tb_rom_init.sv` (updated in code review to prove the register stage explicitly and to
exercise a non-power-of-two `DEPTH`):
```systemverilog
`timescale 1ns/1ps
module tb_rom_init;
  logic clk = 0; always #5 clk = ~clk;

  logic [2:0] addr = 0;
  logic [15:0] data;
  rom_init #(.WIDTH(16), .DEPTH(8), .INIT_FILE("sim/test_rom.mem")) dut (.clk(clk), .addr(addr), .data(data));

  // Non-power-of-two DEPTH instance: $clog2(6) = 3, so addr [2:0] can reach 6 and 7, which
  // are out of range for this ROM (exercises the module's addr < DEPTH requirement).
  logic [2:0] addr6 = 0;
  logic [15:0] data6;
  rom_init #(.WIDTH(16), .DEPTH(6), .INIT_FILE("sim/test_rom6.mem")) dut6 (.clk(clk), .addr(addr6), .data(data6));

  initial begin
    logic [15:0] prev;

    // Prove the register stage: after addr changes, data must still hold the previous
    // address's value right up until the next posedge, and only then update.
    addr = 3'd0;
    @(posedge clk); #1;
    if (data !== {4{4'h0}}) $fatal(1, "addr 0: got %h", data);
    prev = data;
    for (int i = 1; i < 8; i++) begin
      addr = i[2:0];
      #1;
      if (data !== prev) $fatal(1, "addr %0d: data changed before its clock edge: got %h expected %h", i, data, prev);
      @(posedge clk); #1;
      if (data !== {4{i[3:0]}}) $fatal(1, "addr %0d: got %h", i, data);
      prev = data;
    end

    // Non-power-of-two DEPTH: in-range addresses 0..DEPTH-1 must still read correctly.
    for (int i = 0; i < 6; i++) begin
      addr6 = i[2:0]; @(posedge clk); #1;
      if (data6 !== {4{i[3:0]}}) $fatal(1, "dut6 addr %0d: got %h", i, data6);
    end

    $display("PASS tb_rom_init");
    $finish;
  end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_rom_init`
Expected: `Unknown module type: rom_init`.

- [ ] **Step 3: Write `defs.svh` and `rom_init.sv`**

`src/common/defs.svh`:
```systemverilog
// Shared compile-time definitions. Include with `include "common/defs.svh" (include path = src/).
`ifndef DEFS_SVH
`define DEFS_SVH
// Directory holding $readmemh images, relative to where the simulator / Vivado is launched (repo root).
`ifndef MEM_DIR
`define MEM_DIR "mem"
`endif

// Parameter guard, used at module scope: `PARAM_CHECK(g_chk_x, COND, ("module: message %0d", VAL))
// with COND true meaning "bad parameters". `msg` is a parenthesised $error argument list so formatted
// messages keep working; no trailing semicolon at the call site.
`ifdef SIM
  // simulation: non-fatal so TBs can test bad parameters deliberately (tb_clk_gen dut27, tb_ui_ctrl idx 17)
  `define PARAM_CHECK(name, cond, msg) initial if (cond) $error msg;
`else
  // synthesis: IEEE 1800-2012 20.11 elaboration task at generate scope so Vivado stops on a bad parameter
  // (an `initial` block is treated as init-only there and the check would be silently dropped)
  `define PARAM_CHECK(name, cond, msg) if (cond) begin : name $error msg; end
`endif
`endif
```

`src/common/rom_init.sv` (updated in code review: `INIT_FILE` is an **untyped** parameter — Icarus 13
accepts `parameter string` with a literal override but cannot bind a parent module's parameter
(or a `{`MEM_DIR, ...}` concatenation) to it, which Task 12 needs; a `DEPTH >= 2` guard; a simulation-only
out-of-range `addr` check for non-power-of-two `DEPTH`, using a plain `always` rather than
`always_ff` since the block is sim-only and `$error` is not synthesizable):
```systemverilog
`include "common/defs.svh"
// Generic synchronous ROM initialised from a hex file (one word per line, $readmemh format).
// One clock of read latency. Infers BRAM or distributed ROM depending on size.
//
// addr must stay < DEPTH. $clog2(DEPTH) rounds the address width up to the next power of
// two, so when DEPTH itself is not a power of two, addr values in [DEPTH, 2**$clog2(DEPTH)-1]
// are out of range: reads return X in simulation and are undefined in synthesis. The
// simulation-only check below flags any such out-of-range access.
module rom_init #(
  parameter int    WIDTH     = 16,
  parameter int    DEPTH     = 256,
  parameter        INIT_FILE = ""   // untyped: Icarus 13 cannot bind a parent parameter to a `parameter string`
) (
  input  logic                     clk,
  input  logic [$clog2(DEPTH)-1:0] addr,
  output logic [WIDTH-1:0]         data
);
  (* rom_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  `PARAM_CHECK(g_chk_depth, DEPTH < 2, ("rom_init: DEPTH must be >= 2"))

  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

`ifdef SIM
  // Elaborate the range check only when DEPTH is not a power of two: when it is, addr's
  // width exactly spans [0:DEPTH-1], so "addr >= DEPTH" would be a constant-false compare
  // (a Verilator lint warning) rather than a real hazard.
  if (DEPTH != (1 << $clog2(DEPTH))) begin : g_range_check
    // Plain `always`, not `always_ff`: this block is simulation-only ($error is not
    // synthesizable), so the synthesis-intent keyword would just trigger an Icarus warning.
    always @(posedge clk)
      if (int'(addr) >= DEPTH) $error("rom_init: addr %0d >= DEPTH %0d", addr, DEPTH);
  end
`endif

  always_ff @(posedge clk) data <= mem[addr];
endmodule
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C sim tb_rom_init`
Expected: `PASS tb_rom_init`

- [ ] **Step 5: Commit**

```bash
git add src/common/defs.svh src/common/rom_init.sv sim/test_rom.mem sim/tb/tb_rom_init.sv
git commit -m "feat(common): generic readmemh ROM"
```

---

### Task 7: `clk_gen` — MMCM wrapper with simulation shim

**Files:**
- Create: `src/common/clk_gen.sv`
- Test: `sim/tb/tb_clk_gen.sv`

- [ ] **Step 1: Write the failing test**

```systemverilog
`timescale 1ns/1ps
module tb_clk_gen;
  logic clk_in = 0; always #12.5 clk_in = ~clk_in; // 40 MHz
  logic clk_out, locked;
  clk_gen #(.SYS_CLK_IN_HZ(40_000_000), .SYS_CLK_OUT_HZ(100_000_000)) dut
    (.clk_in(clk_in), .clk_out(clk_out), .locked(locked));
  // second instance only for the static solver check (50 MHz board oscillator)
  clk_gen #(.SYS_CLK_IN_HZ(50_000_000), .SYS_CLK_OUT_HZ(100_000_000)) dut50
    (.clk_in(clk_in), .clk_out(), .locked());
  // 600 MHz input: D=1 would put the PFD at 600 MHz (> 450 MHz max), so the solver must fall back to D=2 (PFD 300 MHz)
  clk_gen #(.SYS_CLK_IN_HZ(600_000_000), .SYS_CLK_OUT_HZ(100_000_000)) dut600
    (.clk_in(clk_in), .clk_out(), .locked());
  // 27 MHz input: no integer M/D/O reaches 100 MHz -> solver returns -1. Its `$error` at time 0 is expected output.
  clk_gen #(.SYS_CLK_IN_HZ(27_000_000), .SYS_CLK_OUT_HZ(100_000_000)) dut27
    (.clk_in(clk_in), .clk_out(), .locked());

  realtime t0, t1;
  initial begin
    wait (locked);
    @(posedge clk_out); t0 = $realtime;
    repeat (100) @(posedge clk_out); t1 = $realtime;
    // 100 periods of 10 ns
    if (t1 - t0 < 999.0 || t1 - t0 > 1001.0) $fatal(1, "clk_out period wrong: %f ns per 100", t1 - t0);
    // static check of the MMCM parameter solver
    // highest VCO <= 1150 MHz: 40*25 = 1000, 50*22 = 1100, (600/2)*3 = 900
    if (dut.MMCM_D != 1 || dut.MMCM_M != 25 || dut.MMCM_O != 10)
      $fatal(1, "MMCM solver 40 MHz: D=%0d M=%0d O=%0d (expected 1/25/10)", dut.MMCM_D, dut.MMCM_M, dut.MMCM_O);
    if (dut50.MMCM_D != 1 || dut50.MMCM_M != 22 || dut50.MMCM_O != 11)
      $fatal(1, "MMCM solver 50 MHz: D=%0d M=%0d O=%0d (expected 1/22/11)", dut50.MMCM_D, dut50.MMCM_M, dut50.MMCM_O);
    if (dut600.MMCM_D != 2 || dut600.MMCM_M != 3 || dut600.MMCM_O != 9)
      $fatal(1, "MMCM solver 600 MHz: D=%0d M=%0d O=%0d (expected 2/3/9)", dut600.MMCM_D, dut600.MMCM_M, dut600.MMCM_O);
    if (dut27.MMCM_D != -1)
      $fatal(1, "MMCM solver 27 MHz: D=%0d (expected -1, no solution)", dut27.MMCM_D);
    $display("PASS tb_clk_gen");
    $finish;
  end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_clk_gen`
Expected: `Unknown module type: clk_gen`.

- [ ] **Step 3: Write the implementation**

```systemverilog
`timescale 1ns/1ps
`include "common/defs.svh"
// System clock generator: SYS_CLK_IN_HZ (board oscillator on pin N18) -> SYS_CLK_OUT_HZ via MMCME2_BASE.
// The M/D/O factors are solved at elaboration time so only SYS_CLK_IN_HZ needs to change per board.
// Under `SIM the MMCM is replaced by a free-running clock; `locked` rises after 16 output cycles.
module clk_gen #(
  parameter int SYS_CLK_IN_HZ  = 40_000_000,
  parameter int SYS_CLK_OUT_HZ = 100_000_000,
  // VCO ceiling used by the solver. The 7-series -1 datasheet limit is 1200 MHz; 1150 MHz leaves margin
  // against process/temperature spread instead of parking the VCO exactly on the ceiling.
  parameter int VCO_MAX_HZ     = 1_150_000_000
) (
  // verilator lint_off UNUSEDSIGNAL
  input  logic clk_in,   // only consumed by the MMCM branch; the `SIM shim free-runs
  // verilator lint_on UNUSEDSIGNAL
  output logic clk_out,
  output logic locked
);
  // ---- MMCM factor solver (7-series -1, MMCME2): D 1..8, M 2..64, O 1..128, all integer.
  // Constraints: fin/D (PFD input) in [PFD_MIN_HZ, PFD_MAX_HZ], VCO = fin*M/D in [VCO_MIN_HZ, VCO_MAX_HZ], VCO/fout integer.
  // Policy: d ascends 1..8, m descends 64..2, so the first hit is the highest legal VCO for the smallest
  // input divider (lower output jitter, farthest from the VCO floor). `solve` is a SV keyword, hence the prefix.
  localparam int PFD_MIN_HZ =  19_000_000;
  localparam int PFD_MAX_HZ = 450_000_000;
  localparam int VCO_MIN_HZ = 600_000_000;

  function automatic int mmcm_solve(input int fin, input int fout, input int which);
    for (int d = 1; d <= 8; d++) begin
      longint pfd = longint'(fin) / longint'(d);
      if (longint'(fin) % longint'(d) != 0 || pfd < longint'(PFD_MIN_HZ) || pfd > longint'(PFD_MAX_HZ)) continue;
      for (int m = 64; m >= 2; m--) begin
        longint vco = pfd * longint'(m);
        if (vco >= longint'(VCO_MIN_HZ) && vco <= longint'(VCO_MAX_HZ) &&
            vco % longint'(fout) == 0 && vco / longint'(fout) >= 1 && vco / longint'(fout) <= 128)
          return (which == 0) ? d : (which == 1) ? m : int'(vco / longint'(fout));
      end
    end
    return -1;
  endfunction

  // verilator lint_off UNUSEDPARAM
  localparam int MMCM_D = mmcm_solve(SYS_CLK_IN_HZ, SYS_CLK_OUT_HZ, 0);
  localparam int MMCM_M = mmcm_solve(SYS_CLK_IN_HZ, SYS_CLK_OUT_HZ, 1);
  localparam int MMCM_O = mmcm_solve(SYS_CLK_IN_HZ, SYS_CLK_OUT_HZ, 2);
  // verilator lint_on UNUSEDPARAM

  // MMCME2 CLKIN1 range for 7-series -1 is 10..800 MHz.
  `PARAM_CHECK(g_chk_clkin, SYS_CLK_IN_HZ < 10_000_000 || SYS_CLK_IN_HZ > 800_000_000,
               ("clk_gen: SYS_CLK_IN_HZ outside MMCM CLKIN range"))
  `PARAM_CHECK(g_chk_mmcm, MMCM_D < 0, ("clk_gen: no MMCM solution for %0d -> %0d Hz", SYS_CLK_IN_HZ, SYS_CLK_OUT_HZ))

`ifdef SIM
  localparam real HALF_NS = 0.5e9 / SYS_CLK_OUT_HZ;
  initial clk_out = 1'b0;
  always #(HALF_NS) clk_out = ~clk_out;
  // `locked` is a flop, not a compare on lock_cnt: it drives rst_sync's async reset downstream, and a
  // registered source keeps lock_cnt out of that sensitivity list (Verilator SYNCASYNCNET). On hardware
  // LOCKED comes straight from the MMCM primitive, so this only concerns the shim.
  int lock_cnt;
  initial begin lock_cnt = 0; locked = 1'b0; end
  always @(posedge clk_out) begin
    if (lock_cnt < 16)  lock_cnt <= lock_cnt + 1;
    if (lock_cnt == 15) locked   <= 1'b1;       // 16th output edge
  end
`else
  logic clk_fb, clk_fb_buf, clk0;
  // verilator lint_off PINCONNECTEMPTY
  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKIN1_PERIOD(1.0e9 / SYS_CLK_IN_HZ),
    .DIVCLK_DIVIDE(MMCM_D),
    .CLKFBOUT_MULT_F(MMCM_M),
    .CLKOUT0_DIVIDE_F(MMCM_O),
    .CLKOUT0_PHASE(0.0), .CLKOUT0_DUTY_CYCLE(0.5),
    .STARTUP_WAIT("FALSE")
  ) u_mmcm (
    .CLKIN1(clk_in), .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKFBOUTB(),
    .CLKOUT0(clk0), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    // RST tied low: there is no upstream reset domain to drive it (this block *creates* the system clock).
    // The MMCM free-runs from CLKIN and reports LOCKED downstream; rst_sync derives the system reset from it.
    .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0)
  );
  // verilator lint_on PINCONNECTEMPTY
  BUFG u_bufg_fb  (.I(clk_fb), .O(clk_fb_buf));
  BUFG u_bufg_out (.I(clk0),   .O(clk_out));
`endif
endmodule
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C sim tb_clk_gen`
Expected: `PASS tb_clk_gen`

- [ ] **Step 5: Commit**

```bash
git add src/common/clk_gen.sv sim/tb/tb_clk_gen.sv
git commit -m "feat(common): MMCM clock generator with elaboration-time solver and sim shim"
```

---

### Task 8: Vivado Tcl flow and constraint files

**Files:**
- Create: `vivado/build.tcl`, `vivado/create_project.tcl`, `vivado/program.tcl`, `constr/ad9363.xdc`, `constr/board_io.xdc`, `constr/timing.xdc`

These cannot be executed on this Mac; verify syntax by reading and by `tclsh` parse where possible (`tclsh` is present on macOS).

- [ ] **Step 1: Write `vivado/build.tcl` (non-project batch flow)**

```tcl
# Non-project batch build. Run FROM THE REPO ROOT on the Vivado machine:
#   vivado -mode batch -source vivado/build.tcl -tclargs <top> <sys_clk_in_hz> [part] [allow_unplaced]
# Example:
#   vivado -mode batch -source vivado/build.tcl -tclargs lcd_test_top 40000000
# Outputs: vivado/out/<top>.bit, <top>.dcp, <top>_util.rpt, <top>_timing.rpt
# Refuses to write a bitstream (exits 1) if setup or hold WNS is negative after routing, or if
# any port has no PACKAGE_PIN -- unless a 4th tclarg (any non-empty value, e.g. "allow_unplaced")
# is passed, for a no-hardware trial build where auto-placed pins are acceptable.

if {[llength $argv] < 2} { puts "usage: build.tcl <top> <sys_clk_in_hz> \[part\] \[allow_unplaced\]"; exit 1 }
set top  [lindex $argv 0]
set fin  [lindex $argv 1]
set part [expr {[llength $argv] > 2 ? [lindex $argv 2] : "xc7z020clg400-1"}]
set allow_unplaced [expr {[llength $argv] > 3 ? [lindex $argv 3] : ""}]

set root [file normalize [file join [file dirname [info script]] ..]]
set out  $root/vivado/out
file mkdir $out
cd $root   ;# so that $readmemh("mem/...") resolves

set_part $part
read_verilog -sv [lsort [glob $root/src/*/*.sv]]
read_mem        [glob -nocomplain $root/mem/*.mem $root/mem/*.hex]
# board_io.xdc (clock + LCD/button essentials) and timing.xdc apply to every top. ad9363.xdc's
# RF-front-end pins only exist on tops that instantiate the AD9363 interface; reading it for
# lcd_test_top would only produce "[Vivado 12-584] No ports matched" warnings, so scope it to
# the tops that actually have those ports.
read_xdc $root/constr/board_io.xdc
read_xdc $root/constr/timing.xdc
set rf_tops {fpv_detector_top}
if {[lsearch -exact $rf_tops $top] >= 0} { read_xdc $root/constr/ad9363.xdc }

# board oscillator clock constraint derived from the same parameter as the RTL
set period_ns [format %.3f [expr {1.0e9 / $fin}]]
set clk_xdc [open $out/clk_in.xdc w]
puts $clk_xdc "create_clock -name i_clk -period $period_ns \[get_ports i_clk\]"
close $clk_xdc
read_xdc $out/clk_in.xdc

synth_design -top $top -part $part -include_dirs $root/src \
    -generic SYS_CLK_IN_HZ=$fin -verilog_define MEM_DIR=\"$root/mem\"
write_checkpoint -force $out/${top}_synth.dcp
# Ports still without a PACKAGE_PIN (e.g. constr/board_io.xdc's LCD/button pins, pending
# hardware pinout) are unconstrained; checked right after synthesis, before placement assigns
# every port a (possibly auto-chosen) site. A bitstream built this way must not be connected
# to real hardware on those pins.
set unplaced [get_ports -quiet -filter {PACKAGE_PIN == ""}]
if {[llength $unplaced] > 0} {
    puts "WARNING: ports without PACKAGE_PIN (auto-placed, do NOT connect hardware): $unplaced"
    if {$allow_unplaced eq ""} {
        puts "ERROR: unplaced ports present and allow_unplaced (4th tclarg) not set; aborting before place_design"
        exit 1
    }
}
opt_design
place_design
phys_opt_design
route_design
report_utilization    -file $out/${top}_util.rpt
report_timing_summary -file $out/${top}_timing.rpt -max_paths 20
report_drc            -file $out/${top}_drc.rpt
# ASYNC_REG survival check: confirm synthesis/placement did not drop the attribute on any
# CDC first-stage flop (cdc_sync/cdc_pulse/rst_sync). Guarded so an empty match is not an error.
set async_reg_cells [get_cells -quiet -hier -filter {ASYNC_REG == TRUE}]
if {[llength $async_reg_cells] > 0} { report_property -file $out/${top}_async_reg.rpt $async_reg_cells }
# Refuse to write a bitstream that doesn't meet timing. get_property SLACK on an empty
# get_timing_paths result (no paths of that type, or the tclcheck stub) returns "" -- guard the
# numeric compare so that case doesn't itself raise a Tcl error under tclsh.
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
if {($wns ne "" && $wns < 0) || ($whs ne "" && $whs < 0)} {
    puts "ERROR: timing not met (WNS=$wns WHS=$whs)"
    exit 1
}
write_checkpoint -force $out/${top}.dcp
write_bitstream  -force $out/${top}.bit
puts "BUILD DONE: $out/${top}.bit"
```

- [ ] **Step 2: Write `vivado/create_project.tcl` (optional GUI project)**

```tcl
# Creates a Vivado project for GUI work (schematic, ILA, timing analysis). Run from repo root:
#   vivado -mode batch -source vivado/create_project.tcl -tclargs <top> <sys_clk_in_hz>
set top  [lindex $argv 0]
set fin  [lindex $argv 1]
set root [file normalize [file join [file dirname [info script]] ..]]
create_project -force ${top}_proj $root/vivado/proj_$top -part xc7z020clg400-1
add_files -norecurse [lsort [glob $root/src/*/*.sv]]
add_files -norecurse [glob -nocomplain $root/mem/*.mem $root/mem/*.hex]
add_files -fileset constrs_1 -norecurse [lsort [glob $root/constr/*.xdc]]
set_property include_dirs $root/src [current_fileset]
set_property top $top [current_fileset]
set_property generic SYS_CLK_IN_HZ=$fin [current_fileset]
set_property verilog_define MEM_DIR=\"$root/mem\" [current_fileset]
update_compile_order -fileset sources_1
puts "PROJECT CREATED: $root/vivado/proj_$top"
```

- [ ] **Step 3: Write `vivado/program.tcl`**

```tcl
# Programs the FPGA over JTAG. Run:
#   vivado -mode batch -source vivado/program.tcl -tclargs vivado/out/lcd_test_top.bit
set bit [lindex $argv 0]
open_hw_manager
connect_hw_server
open_hw_target
set devs [get_hw_devices xc7z020*]
if {[llength $devs] == 0} { puts "ERROR: no xc7z020 device found on the JTAG chain"; exit 1 }
set dev [lindex $devs 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED $bit"
close_hw_manager
```

- [ ] **Step 4: Write the constraint files**

`constr/ad9363.xdc` — copy `ad9363/AD936X.xdc` then apply these edits:
```bash
cp ad9363/AD936X.xdc constr/ad9363.xdc
# DATA_CLK is 80 MHz in 1R1T @ 40 MSPS, not 250 MHz
sed -i '' 's/create_clock -period 4.000 -name rx_clk/create_clock -period 12.500 -name rx_clk/' constr/ad9363.xdc
# the MMCM input net name depends on our RTL hierarchy, not the old clk_wiz
sed -i '' 's|set_property CLOCK_DEDICATED_ROUTE FALSE \[get_nets clk_wiz_0_u/inst/clk_in1_clk_wiz_0\]|set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -of_objects [get_pins -hierarchical -filter {NAME =~ */u_mmcm/CLKIN1}]]|' constr/ad9363.xdc
```
The file keeps every AD9363 pin. Ports that a given top does not have only produce `[Vivado 12-584] No ports matched` warnings.

`constr/board_io.xdc`:
```tcl
# LCD (ST7789V, 4-wire SPI) and button. PACKAGE_PINs are NOT KNOWN YET - fill in before hardware use.
# Until then UCIO-1 is downgraded (see ad9363.xdc) and Vivado will auto-place these ports: do not
# connect the panel to a bitstream built with unassigned pins.
set_property IOSTANDARD LVCMOS33 [get_ports lcd_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_dcx]
set_property IOSTANDARD LVCMOS33 [get_ports lcd_resx_n]
set_property -dict {IOSTANDARD LVCMOS33 PULLUP true} [get_ports btn_n]
# set_property PACKAGE_PIN <pin> [get_ports lcd_sclk]
# set_property PACKAGE_PIN <pin> [get_ports lcd_mosi]
# set_property PACKAGE_PIN <pin> [get_ports lcd_cs_n]
# set_property PACKAGE_PIN <pin> [get_ports lcd_dcx]
# set_property PACKAGE_PIN <pin> [get_ports lcd_resx_n]
# set_property PACKAGE_PIN <pin> [get_ports btn_n]
# Keep SPI outputs in the IOB flops for low skew between SCLK/MOSI/DCX
set_property IOB TRUE [get_ports {lcd_sclk lcd_mosi lcd_cs_n lcd_dcx}]
```

`constr/timing.xdc`:
```tcl
# Asynchronous inputs: no timing relationship to any clock
set_false_path -from [get_ports btn_n]
# LCD outputs are generated by a divided fabric strobe, not a clock: no output delay analysis
set_false_path -to [get_ports {lcd_sclk lcd_mosi lcd_cs_n lcd_dcx lcd_resx_n}]

# axis_async_fifo Gray pointer crossings: bound datapath delay to one source clock period so
# consecutive single-bit changes cannot be observed out of order. Cells only exist when a FIFO is instantiated.
# The wildcards below match every axis_async_fifo instance in the design; the two periods
# (12.5 ns / 10.0 ns) are sized for THIS plan's 80 MHz <-> 100 MHz IQ FIFO only. A second
# FIFO instantiated between a different pair of clocks needs its own scoped set_max_delay
# (narrow the -hier filter to that instance's path, with that FIFO's own clock periods).
set fifo_wr_ptr [get_cells -quiet -hier -filter {NAME =~ *wr_gray_reg*}]
set fifo_rd_ptr [get_cells -quiet -hier -filter {NAME =~ *rd_gray_reg*}]
set wr2rd_sync  [get_cells -quiet -hier -filter {NAME =~ *u_wr2rd*stage_reg*}]
set rd2wr_sync  [get_cells -quiet -hier -filter {NAME =~ *u_rd2wr*stage_reg*}]
if {[llength $fifo_wr_ptr] > 0 && [llength $wr2rd_sync] > 0} { set_max_delay -datapath_only -from $fifo_wr_ptr -to $wr2rd_sync 12.500 }
if {[llength $fifo_rd_ptr] > 0 && [llength $rd2wr_sync] > 0} { set_max_delay -datapath_only -from $fifo_rd_ptr -to $rd2wr_sync 10.000 }

# All cdc_sync/cdc_pulse/rst_sync first-stage flops are ASYNC_REG. Post-synthesis, confirm the
# attribute survived on these unpacked-array registers with:
#   report_property [get_cells -hier -filter {NAME =~ *stage_reg*}] ASYNC_REG
```

- [ ] **Step 5: Syntax-check the Tcl with tclsh (no Vivado commands executed)**

Run:
```bash
cd /Users/user/myprojects/st7789v && for f in vivado/*.tcl; do echo "proc unknown {args} {}; set argv {lcd_test_top 40000000}; source $f" | tclsh 2>&1 | grep -v '^$' | head -3; echo "$f parsed"; done
```
Expected: each file prints `<file> parsed` with no `syntax error` / `missing close-brace` lines (Vivado-specific commands are swallowed by the `unknown` stub; `file mkdir` will create `vivado/out`, which is gitignored).

This check is also wired up as `make tclcheck` (see top-level `Makefile`), which runs the same
stub over every `vivado/*.tcl` and `constr/*.xdc` file, wraps `source` in `catch` so a real Tcl
error (as opposed to the script's own intentional `exit`) reliably fails the target, predefines
a dummy `get_hw_devices` so `program.tcl`'s "no device" guard doesn't fire under the stub, and
prints `tclcheck ok` on success.

- [ ] **Step 6: Commit**

```bash
git add vivado constr
git commit -m "build: Vivado batch Tcl flow and constraint files"
```

---

### Task 9: ST7789V init-ROM generator (`tools/gen_st7789_rom.py`)

**Files:**
- Create: `tools/gen_st7789_rom.py`, `mem/st7789_init.mem` (generated)
- Test: `tools/test_gen_st7789_rom.py` (pytest-free, plain asserts, run with `.venv/bin/python`)

ROM word format (16 bit): `word[15:14]` = type — `00` command byte, `01` data byte, `10` delay (`word[13:0]` = ticks, ms on hardware / µs with `SIM_FAST`), `11` end. Payload for cmd/data in `word[7:0]`.

- [ ] **Step 1: Write the failing test**

```python
# tools/test_gen_st7789_rom.py  — run: .venv/bin/python tools/test_gen_st7789_rom.py
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import gen_st7789_rom as g

words = g.build_rom()
assert words[0] == 0x0001, "first word must be SWRESET command"          # type 00, 0x01
assert words[1] == (0b10 << 14) | 150, "SWRESET must be followed by 150 tick delay"
assert (0b00 << 14 | 0x11) in words, "SLPOUT present"
i = words.index(0b00 << 14 | 0x3A)
assert words[i + 1] == (0b01 << 14) | 0x55, "COLMOD parameter must be 0x55 (RGB565)"
i = words.index(0b00 << 14 | 0x2A)
assert words[i + 1:i + 5] == [(0b01 << 14) | b for b in (0x00, 0x00, 0x01, 0x3F)], "CASET 0..319"
i = words.index(0b00 << 14 | 0x2B)
assert words[i + 1:i + 5] == [(0b01 << 14) | b for b in (0x00, 0x00, 0x00, 0xEF)], "RASET 0..239"
assert words[-1] == 0xC000, "last word is END"
assert len(words) <= g.ROM_DEPTH
text = g.format_mem(words)
assert text.splitlines()[0].startswith("//")
assert len([l for l in text.splitlines() if not l.startswith("//")]) == g.ROM_DEPTH
print("PASS test_gen_st7789_rom")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/python tools/test_gen_st7789_rom.py`
Expected: `ModuleNotFoundError: No module named 'gen_st7789_rom'`

- [ ] **Step 3: Write the generator**

```python
#!/usr/bin/env python3
"""Generate mem/st7789_init.mem — the ST7789V initialisation ROM for st7789_ctrl.

Word format (16 bit): [15:14] type: 0=command byte, 1=data byte, 2=delay (ticks in [13:0]), 3=end.
Values follow the ST7789V datasheet (V1.0 2013/10): SWRESET p.160, SLPOUT p.181, COLMOD p.221,
MADCTL p.212, PORCTRL p.260, GCTRL p.263, VCOMS p.266, LCMCTRL p.268, VDVVRHEN p.270, VRHS p.271,
VDVS p.273, FRCTRL2 p.277, PWCTRL1 p.283, PVGAMCTRL/NVGAMCTRL p.287/289, CASET p.195, RASET p.197.
"""
import pathlib

ROM_DEPTH = 128
WIDTH, HEIGHT = 320, 240          # landscape (MADCTL.MV = 1)
MADCTL = 0x60                     # MV=1, MX=1, RGB order. Alternative orientation: 0xA0 (MV|MY)
INVERT = True                     # most IPS ST7789V modules need INVON for correct colours

T_CMD, T_DATA, T_DELAY, T_END = 0, 1, 2, 3

def cmd(c):        return [(T_CMD << 14) | (c & 0xFF)]
def data(*bs):     return [(T_DATA << 14) | (b & 0xFF) for b in bs]
def delay(ticks):  return [(T_DELAY << 14) | (ticks & 0x3FFF)]
def end():         return [(T_END << 14)]

def build_rom():
    w = []
    w += cmd(0x01) + delay(150)                      # SWRESET, wait (>=5 ms; 150 covers sleep-in case)
    w += cmd(0x11) + delay(120)                      # SLPOUT, wait 120 ms
    w += cmd(0x3A) + data(0x55)                      # COLMOD: 65K RGB-IF, 16 bpp MCU (datasheet note: 55h for writes)
    w += cmd(0x36) + data(MADCTL)                    # MADCTL
    w += cmd(0xB2) + data(0x0C, 0x0C, 0x00, 0x33, 0x33)   # PORCTRL
    w += cmd(0xB7) + data(0x35)                      # GCTRL  VGH 13.26 V / VGL -10.43 V
    w += cmd(0xBB) + data(0x20)                      # VCOMS 0.90 V (panel dependent)
    w += cmd(0xC0) + data(0x2C)                      # LCMCTRL
    w += cmd(0xC2) + data(0x01, 0xFF)                # VDVVRHEN
    w += cmd(0xC3) + data(0x0B)                      # VRHS
    w += cmd(0xC4) + data(0x20)                      # VDVS 0 V
    w += cmd(0xC6) + data(0x0F)                      # FRCTRL2 60 Hz dot inversion
    w += cmd(0xD0) + data(0xA4, 0xA1)                # PWCTRL1
    gamma = (0x70, 0x2C, 0x2E, 0x15, 0x10, 0x09, 0x48, 0x33, 0x53, 0x0B, 0x19, 0x18, 0x20, 0x25)
    w += cmd(0xE0) + data(*gamma)                    # PVGAMCTRL (datasheet defaults)
    w += cmd(0xE1) + data(*gamma)                    # NVGAMCTRL
    if INVERT:
        w += cmd(0x21)                               # INVON
    w += cmd(0x13) + delay(10)                       # NORON
    w += cmd(0x29) + delay(10)                       # DISPON
    w += cmd(0x2A) + data(0x00, 0x00, (WIDTH - 1) >> 8, (WIDTH - 1) & 0xFF)    # CASET
    w += cmd(0x2B) + data(0x00, 0x00, (HEIGHT - 1) >> 8, (HEIGHT - 1) & 0xFF)  # RASET
    w += end()
    assert len(w) <= ROM_DEPTH, f"ROM too long: {len(w)}"
    return w

def format_mem(words):
    lines = [f"// ST7789V init ROM, {len(words)} used of {ROM_DEPTH} words. Generated by tools/gen_st7789_rom.py",
             "// [15:14]: 0=cmd 1=data 2=delay(ticks) 3=end"]
    padded = words + [0xC000] * (ROM_DEPTH - len(words))
    lines += [f"{x:04X}" for x in padded]
    return "\n".join(lines) + "\n"

if __name__ == "__main__":
    out = pathlib.Path(__file__).resolve().parents[1] / "mem" / "st7789_init.mem"
    out.write_text(format_mem(build_rom()))
    print(f"wrote {out}")
```

- [ ] **Step 4: Run the test and generate the ROM**

Run: `.venv/bin/python tools/test_gen_st7789_rom.py && .venv/bin/python tools/gen_st7789_rom.py && head -5 mem/st7789_init.mem`
Expected: `PASS test_gen_st7789_rom`, `wrote .../mem/st7789_init.mem`, first data line `0001`.

- [ ] **Step 5: Commit**

```bash
git add tools/gen_st7789_rom.py tools/test_gen_st7789_rom.py mem/st7789_init.mem
git commit -m "feat(display): ST7789V init ROM generator"
```

---

### Task 10: `st7789_spi_master`

**Files:**
- Create: `src/display/st7789_spi_master.sv`
- Test: `sim/tb/tb_st7789_spi_master.sv`

Interface: byte-level. `cs_req` (level) asks for CS low; `tx_ready` rises 3 clocks after CS is low (tCSS ≥ 15 ns). Bytes are shifted MSB first, mode 0 (SCLK idle low, MOSI changes on falling edge, panel samples on rising). `dcx` is set with the byte and held for its duration. SCLK frequency = `clk / (2·CLK_DIV)`.

- [ ] **Step 1: Write the failing test**

```systemverilog
`timescale 1ns/1ps
module tb_st7789_spi_master;
  localparam int CLK_DIV = 2; // SCLK = 100 MHz / 4 = 25 MHz -> period 40 ns
  localparam realtime T_HALF = CLK_DIV * 10.0;  // SCLK half period (ns)
  localparam realtime T_SCLK = 2 * T_HALF;      // SCLK period (ns)
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;
  logic cs_req = 0, tx_valid = 0, tx_ready, tx_dc = 0, busy;
  logic [7:0] tx_data = 0;
  logic sclk, mosi, cs_n, dcx;

  st7789_spi_master #(.CLK_DIV(CLK_DIV)) dut (.clk(clk), .rst_n(rst_n), .cs_req(cs_req),
    .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc), .busy(busy),
    .sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dcx(dcx));

  // bit-level monitor (what the panel sees)
  logic [7:0] rx_byte; int rx_bits = 0; realtime t_last_edge = 0, t_cs_fall = 0;
  realtime t_last_fall = 0, t_mosi = 0, t_byte_first_edge = 0, t_prev_edge = 0;
  logic first_bit = 0;
  logic [7:0] rx_q[$]; logic rx_dc_q[$]; realtime byte_span_q[$];
  always @(negedge cs_n) begin t_cs_fall = $realtime; rx_bits = 0; end
  always @(mosi) t_mosi = $realtime;                      // time of the last MOSI change
  always @(negedge sclk) if (!cs_n) begin
    t_last_fall = $realtime;
    if ($realtime - t_last_edge != T_HALF) $fatal(1, "SCLK high time %0t, expected %0t", $realtime - t_last_edge, T_HALF);
  end
  always @(posedge sclk) if (!cs_n) begin
    if (rx_bits == 0 && t_cs_fall != 0 && $realtime - t_cs_fall < 15.0) $fatal(1, "tCSS violated");
    if (rx_bits > 0 && $realtime - t_last_edge < 39.9) $fatal(1, "SCLK period too short");
    if (rx_bits > 0 && $realtime - t_last_edge != T_SCLK)
      $fatal(1, "SCLK period %0t, expected %0t", $realtime - t_last_edge, T_SCLK);
    first_bit = (rx_bits == 0);
    if (first_bit) t_byte_first_edge = $realtime;
    t_prev_edge = t_last_edge;
    t_last_edge = $realtime;
    rx_byte = {rx_byte[6:0], mosi};
    rx_bits++;
    if (rx_bits == 8) begin
      rx_q.push_back(rx_byte); rx_dc_q.push_back(dcx);
      byte_span_q.push_back($realtime - t_byte_first_edge);
      rx_bits = 0;
    end
  end
  // MOSI may only change on the SCLK falling edge (bits 1..7) or, for bit 0, before the byte's first
  // rising edge with at least half a period of setup. Checked 1 ns after the rising edge so that a
  // MOSI change in the same time step as the rising edge is already recorded in t_mosi (no race).
  always @(posedge sclk) begin
    #1;
    if (!cs_n) begin
      if (!first_bit && t_mosi > t_prev_edge && t_mosi != t_last_fall)
        $fatal(1, "MOSI changed at %0t, not on the SCLK falling edge %0t", t_mosi, t_last_fall);
      if (first_bit && t_last_edge - t_mosi < T_HALF)
        $fatal(1, "MOSI setup before first rising edge %0t, expected >= %0t", t_last_edge - t_mosi, T_HALF);
    end
  end
  // CS must stay low for the whole byte, even if cs_req was dropped in the clock the byte was accepted
  always @(posedge clk) if (busy && cs_n) $fatal(1, "CS released while a byte is shifting");
  // dcx must not change while a byte is on the wire
  always @(dcx) if (rx_bits != 0) $fatal(1, "DCX changed mid-byte");

  // Any SCLK edge while deselected is an error; counted so the deselect test can check for none.
  int sclk_edges = 0, edges0 = 0; always @(sclk) sclk_edges++;

  // Second DUT with CLK_DIV=1 (DIV_MAX=0 path): SCLK = clk/2 -> 20 ns period, 10 ns high.
  logic cs_req1 = 0, tx_valid1 = 0, tx_ready1, busy1, sclk1, mosi1, cs_n1, dcx1;
  logic [7:0] tx_data1 = 0;
  st7789_spi_master #(.CLK_DIV(1)) dut1 (.clk(clk), .rst_n(rst_n), .cs_req(cs_req1),
    .tx_valid(tx_valid1), .tx_ready(tx_ready1), .tx_data(tx_data1), .tx_dc(1'b0), .busy(busy1),
    .sclk(sclk1), .mosi(mosi1), .cs_n(cs_n1), .dcx(dcx1));
  logic [7:0] rx_byte1; int rx_bits1 = 0; realtime t_rise1 = 0; logic [7:0] rx_q1[$];
  always @(negedge sclk1) if (!cs_n1 && $realtime - t_rise1 != 10.0)
    $fatal(1, "CLK_DIV=1: SCLK high time %0t, expected 10 ns", $realtime - t_rise1);
  always @(posedge sclk1) if (!cs_n1) begin
    if (rx_bits1 > 0 && $realtime - t_rise1 != 20.0)
      $fatal(1, "CLK_DIV=1: SCLK period %0t, expected 20 ns", $realtime - t_rise1);
    t_rise1 = $realtime;
    rx_byte1 = {rx_byte1[6:0], mosi1};
    rx_bits1++;
    if (rx_bits1 == 8) begin rx_q1.push_back(rx_byte1); rx_bits1 = 0; end
  end

  // Sample tx_ready at the falling edge (signals stable); the following rising edge is the accept.
  task send(input logic [7:0] b, input logic dc);
    tx_data = b; tx_dc = dc; tx_valid = 1;
    forever begin @(negedge clk); if (tx_ready) break; end
    @(posedge clk); #1 tx_valid = 0;
  endtask
  // Same as send, but cs_req is dropped in the very clock the byte is accepted.
  task send_and_drop_cs(input logic [7:0] b, input logic dc);
    tx_data = b; tx_dc = dc; tx_valid = 1;
    forever begin @(negedge clk); if (tx_ready) begin cs_req = 0; break; end end
    @(posedge clk); #1 tx_valid = 0;
  endtask

  initial begin
    repeat (3) @(posedge clk); rst_n = 1;
    if (cs_n !== 1'b1 || sclk !== 1'b0) $fatal(1, "idle levels wrong");
    if (tx_ready) $fatal(1, "ready without CS");
    cs_req = 1;
    send(8'h2C, 0);
    send(8'hA5, 1);
    send(8'h5A, 1);
    while (busy) @(posedge clk);
    if (sclk !== 1'b0) $fatal(1, "SCLK not idle low after byte");
    repeat (2) @(posedge clk); cs_req = 0; repeat (4) @(posedge clk);
    if (cs_n !== 1'b1) $fatal(1, "CS not released");
    if (rx_q.size() != 3) $fatal(1, "got %0d bytes", rx_q.size());
    if (rx_q[0] !== 8'h2C || rx_dc_q[0] !== 0) $fatal(1, "byte0 %h dc %b", rx_q[0], rx_dc_q[0]);
    if (rx_q[1] !== 8'hA5 || rx_dc_q[1] !== 1) $fatal(1, "byte1 %h dc %b", rx_q[1], rx_dc_q[1]);
    if (rx_q[2] !== 8'h5A || rx_dc_q[2] !== 1) $fatal(1, "byte2 %h dc %b", rx_q[2], rx_dc_q[2]);
    // Second transaction: cs_req falls in the clock the byte is accepted. CS must be held low until
    // the byte completes (checked by the busy && cs_n monitor) and released right after.
    cs_req = 1;
    send_and_drop_cs(8'h3C, 1);
    if (!busy) $fatal(1, "byte not accepted");
    while (busy) @(posedge clk);
    if (cs_n !== 1'b0) $fatal(1, "CS not held until byte end");
    @(negedge clk);
    if (cs_n !== 1'b1) $fatal(1, "CS not released after byte");
    // Deselected (cs_req low, cs_n high): a pending byte must not be accepted and SCLK must not move.
    // Starts in the very clock after cs_n rose, while the tCSS counter is still saturated, so that a
    // tx_ready that does not look at cs_n would accept the byte.
    edges0 = sclk_edges;
    tx_data = 8'hFF; tx_dc = 1; tx_valid = 1;
    repeat (10) begin
      if (tx_ready !== 1'b0) $fatal(1, "tx_ready asserted while deselected");
      if (busy !== 1'b0) $fatal(1, "busy asserted while deselected");
      @(negedge clk);
    end
    if (sclk_edges != edges0) $fatal(1, "SCLK toggled while deselected");
    if (cs_n !== 1'b1) $fatal(1, "CS fell while deselected");
    @(posedge clk); #1 tx_valid = 0;
    if (rx_q.size() != 4) $fatal(1, "got %0d bytes, expected 4", rx_q.size());
    if (rx_q[3] !== 8'h3C || rx_dc_q[3] !== 1) $fatal(1, "byte3 %h dc %b", rx_q[3], rx_dc_q[3]);
    // 8 SCLK periods of exactly T_SCLK per byte: 1st to 8th rising edge = 7 periods (each period and
    // the high time are checked edge by edge above).
    for (int i = 0; i < 4; i++)
      if (byte_span_q[i] != 7 * T_SCLK)
        $fatal(1, "byte%0d spans %0t from first to last rising edge, expected %0t", i, byte_span_q[i], 7 * T_SCLK);
    // CLK_DIV=1 DUT: one byte at SCLK = clk/2.
    cs_req1 = 1; tx_data1 = 8'h96; tx_valid1 = 1;
    forever begin @(negedge clk); if (tx_ready1) break; end
    @(posedge clk); #1 tx_valid1 = 0;
    while (busy1) @(posedge clk);
    if (sclk1 !== 1'b0) $fatal(1, "CLK_DIV=1: SCLK not idle low after byte");
    repeat (2) @(posedge clk); cs_req1 = 0; repeat (2) @(posedge clk);
    if (cs_n1 !== 1'b1) $fatal(1, "CLK_DIV=1: CS not released");
    if (rx_q1.size() != 1 || rx_q1[0] !== 8'h96) $fatal(1, "CLK_DIV=1: got %0d bytes, byte0 %h", rx_q1.size(), rx_q1[0]);
    $display("PASS tb_st7789_spi_master");
    $finish;
  end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_st7789_spi_master`
Expected: `Unknown module type: st7789_spi_master`.

- [ ] **Step 3: Write the implementation**

```systemverilog
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C sim tb_st7789_spi_master`
Expected: `PASS tb_st7789_spi_master`

- [ ] **Step 5: Commit**

```bash
git add src/display/st7789_spi_master.sv sim/tb/tb_st7789_spi_master.sv
git commit -m "feat(display): ST7789V SPI master"
```

---

### Task 11: ST7789V SPI slave simulation model

**Files:**
- Create: `sim/models/st7789v_slave_model.sv`

The model decodes the 4-wire protocol, tracks the datasheet state that matters (reset, sleep-out timing, MADCTL, COLMOD, CASET/RASET window, RAMWR/WRMEMC pixel auto-increment) and can dump the frame as a binary PPM. Time limits are parameters so `SIM_FAST` controllers can be checked with scaled values.

- [ ] **Step 1: Write the model**

```systemverilog
`timescale 1ns/1ps
// Behavioural ST7789V 4-wire SPI slave. Not synthesisable.
// Timing parameters are REAL datasheet values in ns; TBs using a SIM_FAST controller must pass scaled values.
module st7789v_slave_model #(
  parameter real MIN_SCLK_PERIOD_NS   = 66.0,           // tSCYCW (datasheet Table 6)
  parameter real RESET_TO_CMD_NS      = 5_000_000.0,    // no command within 5 ms of reset release
  parameter real RESET_TO_SLPOUT_NS   = 120_000_000.0,  // SLPOUT not before 120 ms after reset
  parameter real SLPOUT_TO_CMD_NS     = 5_000_000.0,    // 5 ms quiet after SLPOUT
  parameter real SWRESET_TO_CMD_NS    = 5_000_000.0     // 5 ms quiet after SWRESET
) (
  input logic sclk,
  input logic mosi,
  input logic cs_n,
  input logic dcx,
  input logic resx_n
);
  // ---- observable state
  logic [7:0]  madctl = 8'h00, colmod = 8'h66, last_cmd = 8'h00;
  logic [15:0] xs = 0, xe = 16'h00EF, ys = 0, ye = 16'h013F;
  logic        sleep_out = 0, disp_on = 0, inverted = 0;
  int          n_frames = 0, n_pixels = 0, n_errors = 0;   // n_errors is cumulative by design (survives reset)
  logic [15:0] mem     [0:319][0:319];   // [col][page]; only 240 of one dimension is used
  bit          written [0:319][0:319];   // set on each pixel write, cleared by hardware reset

  // ---- protocol decode
  logic [7:0] sh; int nbits = 0;
  logic [15:0] col, page; int pix_phase = 0; logic [7:0] pix_hi;
  int param_idx = 0;
  realtime t_reset_rel = -1e12, t_slpout = -1e12, t_swreset = -1e12, t_edge = -1e12;
  bit have_edge = 0;

  function automatic void err(input string msg);
    n_errors++; $error("st7789v_slave_model: %s (t=%t)", msg, $realtime);
  endfunction

  always @(posedge resx_n) begin
    t_reset_rel = $realtime; t_slpout = -1e12; t_swreset = -1e12;
    sleep_out = 0; disp_on = 0; madctl = 0; colmod = 8'h66; inverted = 0;
    xs = 0; xe = 16'h00EF; ys = 0; ye = 16'h013F; nbits = 0;
    n_frames = 0; n_pixels = 0; last_cmd = 0; pix_phase = 0; param_idx = 0;
    for (int c = 0; c < 320; c++) for (int p = 0; p < 320; p++) written[c][p] = 0;
  end
  always @(negedge cs_n) begin nbits = 0; have_edge = 0; end

  function automatic bit mv(); return madctl[5]; endfunction

  task automatic handle_cmd(input logic [7:0] c);
    if ($realtime - t_reset_rel < RESET_TO_CMD_NS) err($sformatf("command %02h too soon after reset", c));
    if (t_slpout  > -1e11 && $realtime - t_slpout  < SLPOUT_TO_CMD_NS)  err($sformatf("command %02h within SLPOUT quiet time", c));
    if (t_swreset > -1e11 && $realtime - t_swreset < SWRESET_TO_CMD_NS) err($sformatf("command %02h within SWRESET quiet time", c));
    last_cmd = c; param_idx = 0;
    case (c)
      // SWRESET resets the window, keeps MADCTL/COLMOD. not modeled: "SWRESET during sleep-out sequence" rule
      8'h01: begin t_swreset = $realtime; xs = 0; ys = 0; xe = mv() ? 16'h013F : 16'h00EF; ye = mv() ? 16'h00EF : 16'h013F; end
      8'h11: begin if ($realtime - t_reset_rel < RESET_TO_SLPOUT_NS) err("SLPOUT before 120 ms"); sleep_out = 1; t_slpout = $realtime; end
      8'h10: sleep_out = 0;
      8'h20: inverted = 0;
      8'h21: inverted = 1;
      8'h28: disp_on = 0;
      8'h29: disp_on = 1;
      8'h2C: begin col = xs; page = ys; pix_phase = 0; n_frames++; n_pixels = 0; end // RAMWR
      8'h3C: pix_phase = 0;                                                        // WRMEMC continues
      default: ;
    endcase
  endtask

  task automatic handle_data(input logic [7:0] d);
    case (last_cmd)
      8'h36: madctl = d;
      8'h3A: colmod = d;
      8'h2A: case (param_idx) 0: xs[15:8] = d; 1: xs[7:0] = d; 2: xe[15:8] = d; 3: xe[7:0] = d; default: err("CASET extra param"); endcase
      8'h2B: case (param_idx) 0: ys[15:8] = d; 1: ys[7:0] = d; 2: ye[15:8] = d; 3: ye[7:0] = d; default: err("RASET extra param"); endcase
      8'h2C, 8'h3C: begin
        if (pix_phase == 0) begin
          if (colmod[2:0] != 3'b101) err("pixel data with COLMOD not 16 bpp");   // once per pixel
          pix_hi = d; pix_phase = 1;
        end else begin
          pix_phase = 0;
          if (col > xe || page > ye) err("pixel outside window");
          else begin
            mem[col][page] = {pix_hi, d};
            written[col][page] = 1;
            n_pixels++;
            // datasheet 8.12: column increments, wraps to xs and increments page; wraps to ys at ye
            if (col == xe) begin col = xs; page = (page == ye) ? ys : page + 1; end
            else col = col + 1;
          end
        end
      end
      default: ; // parameters of other commands are accepted and ignored
    endcase
    param_idx++;
  endtask

  always @(posedge sclk) if (!cs_n) begin
    if (!resx_n) err("SPI activity while RESX low");   // bit ignored
    else begin
      if (have_edge && $realtime - t_edge < MIN_SCLK_PERIOD_NS - 0.01) err("SCLK period below tSCYCW");
      t_edge = $realtime; have_edge = 1;
      sh = {sh[6:0], mosi};
      nbits++;
      if (nbits == 8) begin
        nbits = 0;
        if (dcx) handle_data(sh); else handle_cmd(sh);   // D/CX sampled on the 8th rising edge
      end
    end
  end

  // ---- image helpers. Logical image = what the host addressed: width = column range, height = page range.
  function automatic int img_w(); return mv() ? 320 : 240; endfunction
  function automatic int img_h(); return mv() ? 240 : 320; endfunction
  function automatic logic [15:0] pixel(input int x, input int y);
    if (!written[x][y]) begin err($sformatf("pixel (%0d,%0d) read before being written", x, y)); return 16'h0000; end
    return mem[x][y];
  endfunction

  task automatic dump_ppm(input string fname);
    int fd; logic [15:0] p; int r, g, b;
    fd = $fopen(fname, "wb");
    if (fd == 0) begin err({"cannot open ", fname}); return; end
    $fwrite(fd, "P6\n%0d %0d\n255\n", img_w(), img_h());
    for (int y = 0; y < img_h(); y++)
      for (int x = 0; x < img_w(); x++) begin
        if (!written[x][y]) begin r = 255; g = 0; b = 255; end   // unwritten pixels are magenta
        else begin
          p = mem[x][y];
          r = {p[15:11], p[15:13]}; g = {p[10:5], p[10:9]}; b = {p[4:0], p[4:2]};
        end
        $fwrite(fd, "%c%c%c", r, g, b);
      end
    $fclose(fd);
    $display("st7789v_slave_model: wrote %s (%0dx%0d)", fname, img_w(), img_h());
  endtask
endmodule
```

- [ ] **Step 2: Compile-check the model alone**

Run: `iverilog -g2012 -DSIM -o /dev/null sim/models/st7789v_slave_model.sv`
Expected: no errors (warnings about unused ports are acceptable).

- [ ] **Step 3: Commit**

```bash
git add sim/models/st7789v_slave_model.sv
git commit -m "test(display): behavioural ST7789V SPI slave model with PPM dump"
# review follow-up: real-time defaults, SWRESET/SLPOUT quiet windows, RESX gating, written-pixel tracking
git commit -m "test(display): st7789v model real-time defaults, SWRESET/SLPOUT windows, written-pixel tracking"
```

---

### Task 12: `st7789_ctrl` — reset, init ROM, frame streaming

**Files:**
- Create: `src/display/st7789_ctrl.sv`
- Test: `sim/tb/tb_st7789_ctrl.sv`

Pixel interface contract: `pix_x`/`pix_y` hold the address of the pixel being **fetched** and only change when a pixel is latched. The controller samples `pix_data` no earlier than the (`PIX_LAT`+1)-th clock edge after the address changed, so the source must have `pix_data` valid for the new address before that edge and hold it while the address is stable: a source with L register stages between the address and `pix_data` needs `PIX_LAT >= L` (use `PIX_LAT >= L+1` for one clock of margin; the TB uses L = 3 with `PIX_LAT = 4`). In steady state the two SPI bytes of the previous pixel already hold the address for ≥ 2·(16·CLK_DIV+1) clocks (34 at CLK_DIV=1, also for the first-to-second pixel gap with the TB's `PIX_LAT`, since the HI byte waits for the RAMWR byte to finish), so the saturating `lat_cnt` that gates `S_PIX_LATCH` is a non-binding safety net; it only stalls when `PIX_LAT` approaches the elaboration limit `PIX_LAT <= 2*(16*CLK_DIV+1)`, which guards throughput, not correctness. `init_done` asserts when the ROM end marker is read (the last init byte may still be shifting) and CS is not released between init and the first frame.

Icarus 13 notes: an enum-typed task argument cannot take a `?:` of two enum literals without a cast (use `if/else`); and a `parameter string` cannot be bound to a parameter of the enclosing module, so `rom_init`'s `INIT_FILE` is an untyped parameter (see Task 6).

The testbench also checks: `frame_done` is a single-clock pulse that arrives while CS is high, one per frame (`frames == panel.n_frames` because the next RAMWR comes ~11 bytes after the pulse); RESX low ≥ `RESET_LOW_TICKS` µs after `rst_n` release; first SPI transaction ≥ `RESET_WAIT_TICKS` µs after RESX release; CS high ≥ 40 ns between frames; and the fetch address is held ≥ `PIX_LAT` clocks between changes.

- [ ] **Step 1: Write the failing test**

```systemverilog
`timescale 1ns/1ps
module tb_st7789_ctrl;
  localparam int W = 32, H = 24, CLK_DIV = 1;  // small window keeps the sim short; 50 MHz SCLK
  localparam int RESET_LOW_TICKS = 1, RESET_WAIT_TICKS = 120;  // SIM_FAST: ticks are microseconds
  localparam int PIX_LAT = 4;                  // DUT parameter and the address-hold monitor below
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;

  logic cs_req, tx_valid, tx_ready, tx_dc, busy;
  logic [7:0] tx_data;
  logic sclk, mosi, cs_n, dcx, resx_n;
  logic [4:0] pix_x; logic [4:0] pix_y; logic [15:0] pix_data;
  logic init_done, frame_done;

  st7789_ctrl #(.CLK_HZ(100_000_000), .SIM_FAST(1), .WIDTH(W), .HEIGHT(H), .PIX_LAT(PIX_LAT), .CLK_DIV(CLK_DIV),
                .RESET_LOW_TICKS(RESET_LOW_TICKS), .RESET_WAIT_TICKS(RESET_WAIT_TICKS),
                .INIT_ROM_FILE("mem/st7789_init.mem")) dut (
    .clk(clk), .rst_n(rst_n),
    .cs_req(cs_req), .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc), .spi_busy(busy),
    .lcd_resx_n(resx_n), .pix_x(pix_x), .pix_y(pix_y), .pix_data(pix_data),
    .init_done(init_done), .frame_done(frame_done));

  st7789_spi_master #(.CLK_DIV(CLK_DIV)) u_spi (.clk(clk), .rst_n(rst_n), .cs_req(cs_req),
    .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc), .busy(busy),
    .sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dcx(dcx));

  // scaled limits: SIM_FAST turns ms into us; the model gets the same scale (ns)
  st7789v_slave_model #(.MIN_SCLK_PERIOD_NS(19.9), .RESET_TO_CMD_NS(5_000.0), .RESET_TO_SLPOUT_NS(120_000.0), .SLPOUT_TO_CMD_NS(5_000.0), .SWRESET_TO_CMD_NS(5_000.0))
    panel (.sclk(sclk), .mosi(mosi), .cs_n(cs_n), .dcx(dcx), .resx_n(resx_n));

  // pixel source with 3-cycle latency: value encodes the address
  function automatic logic [15:0] pat(input int x, input int y); return {x[7:0], y[7:0]}; endfunction
  logic [15:0] d1, d2;
  always_ff @(posedge clk) begin d1 <= pat(pix_x, pix_y); d2 <= d1; pix_data <= d2; end

  // ---- monitors
  int frames = 0;
  logic frame_done_q = 0;
  always @(posedge clk) begin
    if (frame_done) frames++;
    if (frame_done && frame_done_q) $fatal(1, "frame_done wider than one clock");
    if (frame_done && cs_n !== 1'b1) $fatal(1, "frame_done while CS is still low");
    frame_done_q <= frame_done;
  end

  // reset timing: RESX low >= RESET_LOW_TICKS us after rst_n release, first SPI byte >= RESET_WAIT_TICKS us after RESX release
  realtime t_rst_rel = -1, t_resx_rise = -1, t_first_cs = -1, t_cs_rise = -1;
  always @(posedge resx_n) t_resx_rise = $realtime;
  always @(negedge cs_n) begin
    if (t_first_cs < 0) t_first_cs = $realtime;
    if (init_done && t_cs_rise >= 0 && $realtime - t_cs_rise < 40.0)
      $fatal(1, "CS high between transactions only %0t (tCHW >= 40 ns)", $realtime - t_cs_rise);
  end
  int cs_rises_after_init = 0;
  always @(posedge cs_n) begin t_cs_rise = $realtime; if (init_done) cs_rises_after_init++; end

  // controller side of the pixel contract: the fetch address must stay stable >= PIX_LAT clocks
  logic [4:0] px_q = 0, py_q = 0; int addr_age = 0, min_age = 1 << 30;   // addr_age at a change edge = clocks held - 1
  always @(posedge clk) begin
    if (px_q !== pix_x || py_q !== pix_y) begin
      if (init_done && addr_age < PIX_LAT) $fatal(1, "pixel address changed after %0d clocks, PIX_LAT is %0d", addr_age, PIX_LAT);
      if (init_done && addr_age < min_age) min_age = addr_age;
      addr_age <= 0;
    end else addr_age <= addr_age + 1;
    px_q <= pix_x; py_q <= pix_y;
  end

  initial begin
    repeat (3) @(posedge clk); rst_n <= 1; t_rst_rel = $realtime;
    wait (init_done);
    if (!panel.sleep_out || !panel.disp_on) $fatal(1, "panel not initialised: slpout=%b dispon=%b", panel.sleep_out, panel.disp_on);
    if (panel.colmod !== 8'h55) $fatal(1, "COLMOD %h", panel.colmod);
    if (panel.madctl !== 8'h60) $fatal(1, "MADCTL %h", panel.madctl);
    if (t_resx_rise < 0 || t_first_cs < 0) $fatal(1, "reset/CS never seen");
    if (t_resx_rise - t_rst_rel < RESET_LOW_TICKS * 1000.0)
      $fatal(1, "RESX low only %0t, expected >= %0d us", t_resx_rise - t_rst_rel, RESET_LOW_TICKS);
    if (t_first_cs - t_resx_rise < RESET_WAIT_TICKS * 1000.0)
      $fatal(1, "first command %0t after RESX release, expected >= %0d us", t_first_cs - t_resx_rise, RESET_WAIT_TICKS);
    $display("RESX low %0.1f us, first command %0.1f us after RESX release", (t_resx_rise - t_rst_rel) / 1000.0, (t_first_cs - t_resx_rise) / 1000.0);
    wait (frames == 2);
    $display("frame_done pulses %0d, RAMWR count %0d, CS releases after init %0d, last CS high gap %0t, min clocks between address changes %0d", frames, panel.n_frames, cs_rises_after_init, $realtime - t_cs_rise, min_age + 1);
    // frame_done follows the CS release of a frame; the next RAMWR (which bumps n_frames) is ~11 bytes later
    if (panel.n_frames != frames) $fatal(1, "frame_done pulses %0d, RAMWR count %0d", frames, panel.n_frames);
    if (cs_rises_after_init < 2) $fatal(1, "CS released only %0d times after init, expected one per frame", cs_rises_after_init);
    if (panel.xs != 0 || panel.xe != W-1 || panel.ys != 0 || panel.ye != H-1) $fatal(1, "window %0d..%0d x %0d..%0d", panel.xs, panel.xe, panel.ys, panel.ye);
    if (panel.n_pixels != W*H) $fatal(1, "pixels per frame %0d", panel.n_pixels);
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
      if (panel.pixel(x, y) !== pat(x, y)) $fatal(1, "pixel (%0d,%0d) = %h expected %h", x, y, panel.pixel(x, y), pat(x, y));
    if (panel.n_errors != 0) $fatal(1, "%0d protocol errors", panel.n_errors);
    panel.dump_ppm("sim/build/tb_st7789_ctrl.ppm");
    $display("PASS tb_st7789_ctrl");
    $finish;
  end
  initial begin #20_000_000; $fatal(1, "timeout"); end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_st7789_ctrl`
Expected: `Unknown module type: st7789_ctrl`.

- [ ] **Step 3: Write the implementation**

```systemverilog
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C sim tb_st7789_ctrl`
Expected: `st7789v_slave_model: wrote sim/build/tb_st7789_ctrl.ppm (320x240)` (the model dumps the whole panel, unwritten pixels magenta) then `PASS tb_st7789_ctrl`. Open the PPM (e.g. `.venv/bin/python -c "from PIL import Image; Image.open('sim/build/tb_st7789_ctrl.ppm').resize((320,240)).save('sim/build/tb_st7789_ctrl.png')"`) — it must show a smooth red/green gradient encoding x/y.

- [ ] **Step 5: Commit**

```bash
git add src/display/st7789_ctrl.sv sim/tb/tb_st7789_ctrl.sv src/common/rom_init.sv
git commit -m "feat(display): ST7789V controller with init ROM and frame streaming"
```

---

### Task 13: `framebuffer` and `test_pattern_gen`

**Files:**
- Create: `src/display/framebuffer.sv`, `src/display/test_pattern_gen.sv`
- Test: `sim/tb/tb_framebuffer.sv`

- [ ] **Step 1: Write the failing test**

```systemverilog
`timescale 1ns/1ps
module tb_framebuffer;
  localparam int W = 320, H = 240;
  localparam int BARS_END = (H * 2) / 3;   // first gradient row (160)
  logic clk = 0, rst_n = 0; always #5 clk = ~clk;
  logic wr_en; logic [8:0] wr_x, rd_x = 0; logic [7:0] wr_y, rd_y = 0; logic [15:0] wr_data, rd_data;
  logic start = 0, busy, done;

  framebuffer #(.WIDTH(W), .HEIGHT(H)) fb (.clk(clk), .wr_en(wr_en), .wr_x(wr_x), .wr_y(wr_y), .wr_data(wr_data),
                                          .rd_x(rd_x), .rd_y(rd_y), .rd_data(rd_data));
  test_pattern_gen #(.WIDTH(W), .HEIGHT(H)) gen (.clk(clk), .rst_n(rst_n), .start(start), .busy(busy), .done(done),
                                                .wr_en(wr_en), .wr_x(wr_x), .wr_y(wr_y), .wr_data(wr_data));

  // Monitor: count write strobes; busy may only fall in the cycle done pulses; done is a single-cycle pulse.
  int n_wr = 0, n_done = 0; logic busy_q = 0;
  always @(posedge clk) if (rst_n) begin
    if (wr_en) n_wr++;
    if (done)  n_done++;
    if (busy_q && !busy && !done) $fatal(1, "busy fell without done");
    if (done && busy)             $fatal(1, "done asserted while busy still high");
    busy_q <= busy;
  end

  task automatic expect_px(input int x, input int y, input logic [15:0] v);
    rd_x <= x[8:0]; rd_y <= y[7:0]; repeat (2) @(posedge clk); #1;
    if (rd_data !== v) $fatal(1, "(%0d,%0d) = %h expected %h", x, y, rd_data, v);
  endtask

  initial begin
    repeat (3) @(posedge clk); rst_n = 1;
    @(posedge clk); #1;
    if (busy !== 1'b0 || wr_en !== 1'b0) $fatal(1, "busy/wr_en not idle after reset");
    @(posedge clk); start <= 1; @(posedge clk); start <= 0; #1;
    if (busy !== 1'b1) $fatal(1, "busy not high one cycle after start");
    repeat (1000) @(posedge clk); #1;
    if (busy !== 1'b1) $fatal(1, "busy dropped during fill");
    wait (done); @(posedge clk); #1;         // last write commits on the edge after done
    if (busy !== 1'b0)  $fatal(1, "busy still high after done");
    if (wr_en !== 1'b0) $fatal(1, "wr_en still high one cycle after done");
    if (n_done != 1)    $fatal(1, "done pulsed %0d times, expected 1", n_done);
    if (n_wr != W * H)  $fatal(1, "%0d write strobes, expected %0d", n_wr, W * H);
    expect_px(0,   0,   16'hFFFF);   // border white: corners and the midpoint of each side
    expect_px(319, 239, 16'hFFFF);
    expect_px(0,   120, 16'hFFFF);   // left
    expect_px(319, 120, 16'hFFFF);   // right
    expect_px(160, 0,   16'hFFFF);   // top
    expect_px(160, 239, 16'hFFFF);   // bottom
    expect_px(20,  50,  16'hFFFF);   // bar 0 white
    expect_px(60,  50,  16'hFFE0);   // bar 1 yellow
    expect_px(100, 50,  16'h07FF);   // bar 2 cyan
    expect_px(140, 50,  16'h07E0);   // bar 3 green
    expect_px(180, 50,  16'hF81F);   // bar 4 magenta
    expect_px(220, 50,  16'hF800);   // bar 5 red
    expect_px(260, 50,  16'h001F);   // bar 6 blue
    expect_px(300, 50,  16'h0000);   // bar 7 black
    // BARS_END boundary: last bar row is BARS_END-1, first gradient row is BARS_END.
    expect_px(20,  BARS_END - 1, 16'hFFFF);  // bar 0 white
    expect_px(20,  BARS_END,     16'h1082);  // x=20: lvl5 = 20*32/320 = 2, lvl6 = 20*64/320 = 4 -> {5'd2,6'd4,5'd2} = 00010_000100_00010
    expect_px(1,   200, 16'h0000);   // gradient: x=1 -> level 0
    expect_px(318, 200, 16'hFFFF);   // gradient: x=318 -> level 31
    expect_px(160, 200, 16'h8410);   // level 16 -> {5'd16,6'd32,5'd16}
    // Read latency is exactly 2 clocks: after a new address, the old value survives one edge and the
    // new value appears after the second.
    expect_px(220, 50, 16'hF800);                       // red, settled
    rd_x <= 9'd260; rd_y <= 8'd50; @(posedge clk); #1;  // blue requested
    if (rd_data !== 16'hF800) $fatal(1, "rd_data changed after 1 clock: %h (latency < 2)", rd_data);
    @(posedge clk); #1;
    if (rd_data !== 16'h001F) $fatal(1, "rd_data not updated after 2 clocks: %h (latency > 2)", rd_data);
    // A second start refills the buffer with the same image.
    @(posedge clk); start <= 1; @(posedge clk); start <= 0;
    wait (done); @(posedge clk); #1;
    if (n_wr != 2 * W * H) $fatal(1, "%0d write strobes after 2 fills, expected %0d", n_wr, 2 * W * H);
    expect_px(100, 50, 16'h07FF);
    $display("PASS tb_framebuffer");
    $finish;
  end
  initial begin #4_000_000; $fatal(1, "timeout"); end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_framebuffer`
Expected: `Unknown module type: framebuffer`.

- [ ] **Step 3: Write `framebuffer.sv`**

```systemverilog
`include "common/defs.svh"
// WIDTH x HEIGHT x RGB565 frame store in BRAM. Simple dual port, both ports on clk.
// Read latency: 2 clocks (address register + BRAM output register).
// Write: wr_en/wr_x/wr_y/wr_data are sampled on one edge and the location is updated on that edge;
// a read of the same location issued on that same edge still returns the old contents (read-first).
module framebuffer #(
  parameter int WIDTH  = 320,
  parameter int HEIGHT = 240
) (
  input  logic                      clk,
  input  logic                      wr_en,
  input  logic [$clog2(WIDTH)-1:0]  wr_x,
  input  logic [$clog2(HEIGHT)-1:0] wr_y,
  input  logic [15:0]               wr_data,
  input  logic [$clog2(WIDTH)-1:0]  rd_x,
  input  logic [$clog2(HEIGHT)-1:0] rd_y,
  output logic [15:0]               rd_data
);
  localparam int DEPTH = WIDTH * HEIGHT;
  localparam int AW    = $clog2(DEPTH);

  `PARAM_CHECK(g_chk_geom, WIDTH < 8 || HEIGHT < 8 || WIDTH % 8 != 0,
               ("framebuffer: WIDTH/HEIGHT must be >= 8 and WIDTH a multiple of 8"))

  (* ram_style = "block" *) logic [15:0] mem [0:DEPTH-1];

  // Linear address = y * WIDTH + x. Operands are widened to AW bits before the multiply so the
  // product is sized explicitly; y * WIDTH + x < DEPTH <= 2**AW, so nothing is truncated.
  logic [AW-1:0] wr_addr, rd_addr;
  always_comb begin
    wr_addr = AW'(wr_y) * AW'(WIDTH) + AW'(wr_x);
    rd_addr = AW'(rd_y) * AW'(WIDTH) + AW'(rd_x);
  end

  logic [15:0] rd_q;
  always_ff @(posedge clk) begin
    if (wr_en) mem[wr_addr] <= wr_data;
    rd_q    <= mem[rd_addr];
    rd_data <= rd_q;
  end
endmodule
```

- [ ] **Step 4: Write `test_pattern_gen.sv`**

```systemverilog
`include "common/defs.svh"
// Writes a static test image into the framebuffer once per `start` pulse:
// 1-pixel white border, rows 0..(2/3 H): 8 SMPTE-style colour bars, remaining rows: horizontal grey gradient.
//
// Timing: `done` is a one-clock pulse in the same cycle as the last `wr_en`; that final write commits
// on the following clock edge, so consumers must wait one more clock after `done` before reading the
// last pixel. `start` is ignored while `busy`.
//
// No per-pixel division: the bar index and the gradient level are tracked incrementally as `cx`
// advances along a row. A per-bar pixel counter bumps the bar index every BAR_W pixels, and the
// gradient level floor(x*64/WIDTH) comes from an accumulator that adds 64 per pixel and gives up one
// level per WIDTH taken out of it (integer division by repeated subtraction, exact for any WIDTH).
// The 5-bit level floor(x*32/WIDTH) is that value halved, since floor(floor(n/d)/2) == floor(n/(2d)).
module test_pattern_gen #(
  parameter int WIDTH  = 320,
  parameter int HEIGHT = 240
) (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic                      start,
  output logic                      busy,
  output logic                      done,
  output logic                      wr_en,
  output logic [$clog2(WIDTH)-1:0]  wr_x,
  output logic [$clog2(HEIGHT)-1:0] wr_y,
  output logic [15:0]               wr_data
);
  localparam int BAR_W    = WIDTH / 8;
  localparam int BARS_END = (HEIGHT * 2) / 3;

  `PARAM_CHECK(g_chk_geom, WIDTH < 8 || HEIGHT < 8 || WIDTH % 8 != 0,
               ("test_pattern_gen: WIDTH/HEIGHT must be >= 8 and WIDTH a multiple of 8"))

  function automatic logic [15:0] bar_colour(input logic [2:0] idx);
    case (idx)
      3'd0: return 16'hFFFF; 3'd1: return 16'hFFE0; 3'd2: return 16'h07FF; 3'd3: return 16'h07E0;
      3'd4: return 16'hF81F; 3'd5: return 16'hF800; 3'd6: return 16'h001F; default: return 16'h0000;
    endcase
  endfunction

  // cx/cy are the pattern coordinates; the write port is registered one cycle later so that
  // address and data stay aligned. done pulses in the same cycle as the last wr_en.
  localparam int XW = $clog2(WIDTH), YW = $clog2(HEIGHT);
  logic [XW-1:0] cx;
  logic [YW-1:0] cy;

  // Row state for x = cx, all zero at x = 0 and stepped once per cx increment.
  // acc6 is (cx*64) mod WIDTH and lvl6 is floor(cx*64/WIDTH); per step acc6 grows by 64 and each WIDTH
  // taken out of it is one level. One subtraction per step suffices when WIDTH >= 64; smaller
  // geometries need up to ceil(64/WIDTH), unrolled by the constant-bound loop below.
  localparam int STEPS6 = (64 + WIDTH - 1) / WIDTH;
  localparam int AW     = $clog2(WIDTH + 64);      // acc6 < WIDTH before the add, < WIDTH + 64 after
  logic [XW-1:0] bar_px;                           // pixel index within the current bar, 0..BAR_W-1
  logic [2:0]    bar_idx;
  logic [AW-1:0] acc6;
  logic [5:0]    lvl6;
  logic [AW-1:0] acc6_n;
  logic [5:0]    lvl6_n;
  always_comb begin
    acc6_n = acc6 + AW'(64);
    lvl6_n = lvl6;
    for (int i = 0; i < STEPS6; i++)
      if (acc6_n >= AW'(WIDTH)) begin acc6_n = acc6_n - AW'(WIDTH); lvl6_n = lvl6_n + 1'b1; end
  end

  // Grey gradient: R and B use the 5-bit level, G the full 6-bit one, so x=1 -> 0x0000 and x=WIDTH-2 -> 0xFFFF.
  function automatic logic [15:0] pixel(input logic [XW-1:0] x, input logic [YW-1:0] y,
                                        input logic [2:0] bar, input logic [5:0] l6);
    if (x == '0 || y == '0 || x == XW'(WIDTH - 1) || y == YW'(HEIGHT - 1)) return 16'hFFFF;
    if (y < YW'(BARS_END)) return bar_colour(bar);
    return {l6[5:1], l6, l6[5:1]};
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0; done <= 1'b0; wr_en <= 1'b0; cx <= '0; cy <= '0; wr_x <= '0; wr_y <= '0; wr_data <= '0;
      bar_px <= '0; bar_idx <= '0; acc6 <= '0; lvl6 <= '0;
    end else begin
      done  <= 1'b0;
      wr_en <= busy;
      wr_x  <= cx; wr_y <= cy; wr_data <= pixel(cx, cy, bar_idx, lvl6);
      if (!busy) begin
        if (start) begin
          busy <= 1'b1; cx <= '0; cy <= '0;
          bar_px <= '0; bar_idx <= '0; acc6 <= '0; lvl6 <= '0;
        end
      end else begin
        if (cx == XW'(WIDTH - 1)) begin
          cx <= '0;
          bar_px <= '0; bar_idx <= '0; acc6 <= '0; lvl6 <= '0;     // row start: x = 0
          if (cy == YW'(HEIGHT - 1)) begin cy <= '0; busy <= 1'b0; done <= 1'b1; end
          else cy <= cy + 1'b1;
        end else begin
          cx <= cx + 1'b1;
          if (bar_px == XW'(BAR_W - 1)) begin bar_px <= '0; bar_idx <= bar_idx + 1'b1; end
          else bar_px <= bar_px + 1'b1;
          acc6 <= acc6_n; lvl6 <= lvl6_n;
        end
      end
    end
  end
endmodule
```

The last framebuffer write happens on the cycle `done` is high, which is why the test waits one extra clock after `done`.

- [ ] **Step 5: Run test to verify it passes**

Run: `make -C sim tb_framebuffer`
Expected: `PASS tb_framebuffer`

- [ ] **Step 6: Commit**

```bash
git add src/display/framebuffer.sv src/display/test_pattern_gen.sv sim/tb/tb_framebuffer.sv
git commit -m "feat(display): BRAM framebuffer and colour-bar test pattern generator"
```

---

### Task 14: Channel table and text ROM generators

**Files:**
- Create: `tools/fpv_channels.py`, `tools/gen_chan_names.py`, `tools/gen_ui_strings.py`, `tools/test_fpv_channels.py`
- Generated: `mem/chan_names.hex` (64 entries × 8 chars), `mem/ui_strings.hex` (16 entries × 8 chars)

`fpv_channels.py` is the single source of truth for the 40-channel table; the M2 plan's `gen_channel_rom.py` imports it.

- [ ] **Step 1: Write the failing test**

```python
# tools/test_fpv_channels.py — run: .venv/bin/python tools/test_fpv_channels.py
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import fpv_channels as fc, gen_chan_names as gn, gen_ui_strings as gs

ch = fc.channels()
assert len(ch) == 40 and ch[0] == ("A1", 5865) and ch[39] == ("R8", 5917)
u = fc.unique_channels()
assert len(u) == 39, len(u)
names = [n for n, _, _ in u]
assert "F8" in names and "R7" not in names
f8 = [c for c in u if c[0] == "F8"][0]
assert f8[1] == 5880 and f8[2] == "R7", f8                     # (name, freq, alias)
srt = fc.by_frequency()
assert [f for _, f, _ in srt] == sorted(f for _, f, _ in srt) and srt[0][1] == 5645 and srt[-1][1] == 5945
assert fc.display_name(u[0]) == "A1 5865 " and len(fc.display_name(f8)) == 8

# triple-collision test: a frequency appearing three times must raise ValueError
_orig_bands = fc.BANDS
fc.BANDS = {
    "A": [9999, 1, 2, 3, 4, 5, 6, 7],
    "B": [9999, 8, 9, 10, 11, 12, 13, 14],
    "E": [9999, 15, 16, 17, 18, 19, 20, 21],
    "F": [22, 23, 24, 25, 26, 27, 28, 29],
    "R": [30, 31, 32, 33, 34, 35, 36, 37],
}
try:
    fc.unique_channels()
    raise AssertionError("expected ValueError for triple frequency collision")
except ValueError:
    pass
finally:
    fc.BANDS = _orig_bands

lines = gn.build_hex().splitlines()
data = [l for l in lines if not l.startswith("//")]
assert len(data) == 64 * 8, len(data)
assert bytes(int(x, 16) for x in data[0:8]).decode() == "A1 5865 "
assert all(x == "20" for x in data[39 * 8:64 * 8])            # all padding entries are spaces

sl = [l for l in gs.build_hex().splitlines() if not l.startswith("//")]
assert len(sl) == 16 * 8
assert bytes(int(x, 16) for x in sl[8 * gs.STR_SCAN:8 * gs.STR_SCAN + 8]).decode() == "SCAN    "
assert gs.STR_TEST == 9  # hardcoded in src/display/ui_demo.sv (Task 17)
assert all(x == "20" for x in sl[10 * 8:16 * 8])               # all padding entries are spaces
print("PASS test_fpv_channels")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/bin/python tools/test_fpv_channels.py`
Expected: `ModuleNotFoundError: No module named 'fpv_channels'`

- [ ] **Step 3: Write the modules**

`tools/fpv_channels.py`:
```python
"""Analog FPV 5.8 GHz channel table (bands A/B/E/F/R). Shared by ROM generators."""
from typing import NamedTuple

BANDS = {
    "A": [5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725],
    "B": [5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866],
    "E": [5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945],
    "F": [5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880],
    "R": [5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917],
}


class Channel(NamedTuple):
    name: str
    freq: int
    alias: str = ""


def channels():
    """All 40 (name, freq_mhz) in band order A1..R8."""
    return [(f"{b}{i + 1}", f) for b in "ABEFR" for i, f in enumerate(BANDS[b])]

def unique_channels():
    """39 Channel(name, freq_mhz, alias) with duplicate frequencies merged (F8 5880 == R7).

    Raises ValueError if a frequency appears a third time (the alias slot is already used)."""
    out, seen = [], {}
    for name, f in channels():
        if f in seen:
            i = seen[f]
            if out[i].alias:
                raise ValueError(
                    f"frequency {f} MHz collides three times: {out[i].name}/{out[i].alias}/{name}"
                )
            out[i] = Channel(out[i].name, f, name)
        else:
            seen[f] = len(out)
            out.append(Channel(name, f, ""))
    return out

def by_frequency():
    """39 unique channels sorted ascending by frequency."""
    return sorted(unique_channels(), key=lambda c: c[1])

def display_name(ch):
    """8-character OSD label, e.g. 'A1 5865 '."""
    name, f, _ = ch
    s = f"{name} {f}".ljust(8)
    assert len(s) == 8, s
    return s
```

`tools/gen_chan_names.py`:
```python
#!/usr/bin/env python3
"""Generate mem/chan_names.hex: 64 entries x 8 ASCII bytes (39 channels + space padding)."""
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import fpv_channels as fc

ENTRIES = 64

def build_hex():
    names = [fc.display_name(c) for c in fc.unique_channels()]
    names += [" " * 8] * (ENTRIES - len(names))
    lines = [f"// channel names ROM: {ENTRIES} x 8 bytes, index = unique channel index (tools/fpv_channels.py)"]
    for n in names:
        assert len(n) == 8, n
        lines += [f"{ord(c):02X}" for c in n]
    return "\n".join(lines) + "\n"

if __name__ == "__main__":
    out = pathlib.Path(__file__).resolve().parents[1] / "mem" / "chan_names.hex"
    out.write_text(build_hex()); print(f"wrote {out}")
```

`tools/gen_ui_strings.py`:
```python
#!/usr/bin/env python3
"""Generate mem/ui_strings.hex: 16 fixed 8-character OSD strings. Indices are shared with ui_ctrl users."""
import pathlib

STR_BLANK, STR_SCAN, STR_LOCK, STR_PAL, STR_NTSC, STR_INIT, STR_FAULT, STR_NOSIG, STR_CH, STR_TEST = range(10)
STRINGS = ["        ", "SCAN    ", "LOCK    ", "PAL     ", "NTSC    ", "INIT    ", "FAULT   ", "NO SIG  ", "CH      ", "TEST    "]
ENTRIES = 16

def build_hex():
    strs = STRINGS + ["        "] * (ENTRIES - len(STRINGS))
    lines = ["// fixed OSD strings ROM: 16 x 8 bytes; index constants in tools/gen_ui_strings.py"]
    for s in strs:
        assert len(s) == 8, s
        lines += [f"{ord(c):02X}" for c in s]
    return "\n".join(lines) + "\n"

if __name__ == "__main__":
    out = pathlib.Path(__file__).resolve().parents[1] / "mem" / "ui_strings.hex"
    out.write_text(build_hex()); print(f"wrote {out}")
```

- [ ] **Step 4: Run test and generate**

Run: `.venv/bin/python tools/test_fpv_channels.py && .venv/bin/python tools/gen_chan_names.py && .venv/bin/python tools/gen_ui_strings.py`
Expected: `PASS test_fpv_channels`, two `wrote ...` lines.

- [ ] **Step 5: Commit**

```bash
git add tools/fpv_channels.py tools/gen_chan_names.py tools/gen_ui_strings.py tools/test_fpv_channels.py mem/chan_names.hex mem/ui_strings.hex
git commit -m "feat(tools): FPV channel table and OSD text ROM generators"
```

---

### Task 15: Font generator, `osd_text_ram`, `osd_compositor`

**Files:**
- Create: `tools/gen_font.py`, `tools/test_gen_font.py`, `mem/font8x16.hex` (generated), `src/display/osd_text_ram.sv`, `src/display/osd_compositor.sv`
- Test: `sim/tb/tb_osd.sv`

Font: 96 glyphs (ASCII 0x20..0x7F), 16 rows each, one byte per row, MSB = leftmost pixel → 1536 lines.

- [ ] **Step 1: Write `tools/gen_font.py` and generate the font**

```python
#!/usr/bin/env python3
"""Render an 8x16 bitmap font (ASCII 0x20..0x7F) from a system monospace TTF into mem/font8x16.hex.
One byte per glyph row, MSB = leftmost pixel; 96 glyphs x 16 rows = 1536 lines.

The committed mem/font8x16.hex is the reference image. Regenerating on another OS (or with another
Pillow / FreeType version) may pick a different font from CANDIDATES or rasterise slightly
differently, so the output is not guaranteed byte-identical; only regenerate deliberately."""
import pathlib
from PIL import Image, ImageDraw, ImageFont

CANDIDATES = ["/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Monaco.ttf",
              "/Library/Fonts/Courier New.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"]

# 13 px with the baseline offset 0 is the largest Menlo render whose 96 glyphs (including the
# descenders g j p q y and the bar |) all stay inside the 8x16 cell.
SIZE, Y_OFF = 13, 0

def load_font():
    for path in CANDIDATES:
        if pathlib.Path(path).exists():
            return ImageFont.truetype(path, SIZE), path
    raise SystemExit("no monospace TTF found; add a path to CANDIDATES")

def render_glyph(font, ch):
    img = Image.new("L", (8, 16), 0)
    ImageDraw.Draw(img).text((0, Y_OFF), ch, font=font, fill=255)
    rows = []
    for y in range(16):
        b = 0
        for x in range(8):
            if img.getpixel((x, y)) >= 128:
                b |= 0x80 >> x
        rows.append(b)
    return rows

def build_hex():
    font, path = load_font()
    lines = [f"// 8x16 font, ASCII 0x20..0x7F, 16 bytes per glyph, MSB = left pixel. Source: {path}"]
    for code in range(0x20, 0x80):
        lines += [f"{b:02X}" for b in render_glyph(font, chr(code))]
    return "\n".join(lines) + "\n"

if __name__ == "__main__":
    out = pathlib.Path(__file__).resolve().parents[1] / "mem" / "font8x16.hex"
    out.write_text(build_hex()); print(f"wrote {out}")
```

Run: `.venv/bin/python tools/gen_font.py && .venv/bin/python - <<'EOT'
rows=[l for l in open('mem/font8x16.hex') if not l.startswith('//')]
assert len(rows)==1536
assert all(int(r,16)==0 for r in rows[0:16]), "space must be blank"
assert sum(bin(int(r,16)).count('1') for r in rows[(ord('#')-32)*16:(ord('#')-31)*16])>10, "# must have ink"
print("font ok")
EOT`
Expected: `wrote .../mem/font8x16.hex` and `font ok`.

Then `.venv/bin/python tools/test_gen_font.py` (plain asserts: 1536 byte rows, blank space, ink in `#`/`A`, and the generator reproducing the committed hex when the same source font exists) must print `PASS test_gen_font`.

- [ ] **Step 2: Write the failing testbench**

```systemverilog
`timescale 1ns/1ps
module tb_osd;
  localparam int W = 320, H = 240;
  logic clk = 0; always #5 clk = ~clk;
  logic rst_n = 0;
  logic [8:0] pix_x = 0; logic [7:0] pix_y = 0;
  logic [15:0] pix_data;
  logic [8:0] fb_rd_x; logic [7:0] fb_rd_y;
  logic txt_we = 0; logic [9:0] txt_waddr = 0; logic [7:0] txt_wdata = 0;

  // framebuffer stand-in with the real 2-cycle latency: solid red in text rows 0..1 (y < 32),
  // a unique-per-pixel pattern below so that a misaligned fb/glyph pipeline shows up.
  function automatic logic [15:0] fb_pat(input logic [8:0] x, input logic [7:0] y);
    return (y < 32) ? 16'hF800 : {x, y[6:0]};
  endfunction
  logic [15:0] fb_q1, fb_rd_data;
  always_ff @(posedge clk) begin fb_q1 <= fb_pat(fb_rd_x, fb_rd_y); fb_rd_data <= fb_q1; end

  osd_compositor #(.WIDTH(W), .HEIGHT(H)) dut (.clk(clk), .rst_n(rst_n),
    .pix_x(pix_x), .pix_y(pix_y), .pix_data(pix_data),
    .fb_rd_x(fb_rd_x), .fb_rd_y(fb_rd_y), .fb_rd_data(fb_rd_data),
    .txt_we(txt_we), .txt_waddr(txt_waddr), .txt_wdata(txt_wdata));

  logic [7:0] font [0:1535];
  initial $readmemh("mem/font8x16.hex", font);

  // golden model: mirror of the whole 1024-byte text RAM + the compositing rule
  logic [7:0] txt [0:1023];
  initial for (int i = 0; i < 1024; i++) txt[i] = 8'h20;
  // "dimmed by half per channel", written per RGB565 channel rather than as the RTL's bit slice
  function automatic logic [15:0] dim(input logic [15:0] c);
    logic [4:0] r, b; logic [5:0] g;
    r = c[15:11] >> 1; g = c[10:5] >> 1; b = c[4:0] >> 1;
    return {r, g, b};
  endfunction
  function automatic logic [15:0] golden(input int x, input int y);
    logic [7:0] ch; logic [15:0] fb;
    fb = fb_pat(x[8:0], y[7:0]);
    if (x >= W || y >= H) return fb;                 // outside the panel: text never applies
    ch = txt[(y / 16) * (W / 8) + x / 8];
    if (ch[6:0] <= 7'h20) return fb;
    if (font[(ch[6:0] - 7'h20) * 16 + y % 16][7 - x % 8]) return ch[7] ? 16'h07E0 : 16'hFFFF;
    return dim(fb);
  endfunction

  task automatic write_char(input int row, input int col, input logic [7:0] ch);
    @(posedge clk); txt_we <= 1; txt_waddr <= 10'(row * 40 + col); txt_wdata <= ch;
    @(posedge clk); txt_we <= 0;
    txt[row * 40 + col] = ch;
  endtask
  // Drive a new address; pix_data must equal the golden value exactly 3 clocks later and stay
  // there through the 6-clock window st7789_ctrl allows (PIX_LAT). Returns the settled value.
  task automatic read_pix(input int x, input int y, output logic [15:0] v);
    logic [15:0] v3;
    pix_x <= x[8:0]; pix_y <= y[7:0];
    repeat (3) @(posedge clk); #1 v3 = pix_data;
    if (v3 !== golden(x, y)) $fatal(1, "(%0d,%0d): pix_data %h after 3 clocks, golden %h", x, y, v3, golden(x, y));
    repeat (3) @(posedge clk); #1 v = pix_data;
    if (v !== v3) $fatal(1, "(%0d,%0d): pix_data changed after settling: %h -> %h", x, y, v3, v);
  endtask

  logic [15:0] v; int ink;
  initial begin
    repeat (2) @(posedge clk); rst_n = 1;
    write_char(0, 0, 8'h80 | "A");   // highlighted 'A' at (row0,col0)
    write_char(0, 1, "#");           // normal '#' at (row0,col1)
    // cell (0,0): glyph pixels green, background dimmed red
    ink = 0;
    for (int y = 0; y < 16; y++) for (int x = 0; x < 8; x++) begin
      read_pix(x, y, v);
      if (font[("A" - 32) * 16 + y][7 - x]) begin ink++; if (v !== 16'h07E0) $fatal(1, "A ink (%0d,%0d) = %h", x, y, v); end
      else if (v !== 16'h7800) $fatal(1, "A bg (%0d,%0d) = %h", x, y, v);
    end
    if (ink < 10) $fatal(1, "glyph A has too little ink: %0d", ink);
    // cell (0,1): '#' white ink
    read_pix(8 + 3, 7, v);
    if (v !== 16'hFFFF && v !== 16'h7800) $fatal(1, "# pixel = %h", v);
    // empty cell (1,5) -> framebuffer untouched
    read_pix(5 * 8 + 2, 16 + 3, v);
    if (v !== 16'hF800) $fatal(1, "blank cell altered: %h", v);
    // fb address passthrough
    if (fb_rd_x !== 9'd42 || fb_rd_y !== 8'd19) $fatal(1, "fb address not passed through");
    // highlighted space (bit7 set, ASCII 0x20) is still transparent: pure pass-through, no dimming
    write_char(1, 6, 8'h80 | " ");
    read_pix(6 * 8 + 1, 16 + 5, v);
    if (v !== 16'hF800) $fatal(1, "highlighted blank cell altered: %h", v);
    // Patterned framebuffer region (y >= 32): text in row 2, cols 0..1; hop between glyph pixels,
    // dimmed background and blank cells so every read changes the fb value the pipeline must align.
    write_char(2, 0, 8'h80 | "W");
    write_char(2, 1, "g");
    for (int y = 32; y < 48; y++) for (int x = 0; x < 16; x++) begin
      read_pix(x, y, v);
      read_pix(200 + x, 100 + y, v);   // blank cell: passthrough of a different pattern value
    end
    // Out-of-range addresses (never produced by st7789_ctrl, but representable in 9/8 bits) pass the
    // framebuffer through even though the text-address arithmetic aliases them onto real cells:
    // x=400 -> col 50 -> linear cell row*40+50 = cell (row+1, 10); y=250 -> row 15 (beyond the 15 rows).
    write_char(1, 10, "X");      // aliased by (400, 5)
    write_char(7, 10, "X");      // aliased by (400, 100)
    write_char(15, 2, "Y");      // aliased by (19, 250): RAM byte 602, outside the 600 used cells
    read_pix(400, 5, v);   if (v !== 16'hF800)         $fatal(1, "x out of range altered pixel: %h", v);
    read_pix(400, 100, v); if (v !== fb_pat(400, 100)) $fatal(1, "x out of range altered pattern pixel: %h", v);
    read_pix(19, 250, v);  if (v !== fb_pat(19, 250))  $fatal(1, "y out of range altered pixel: %h", v);
    // last text row / last column: the address arithmetic must reach cell (14,39)
    write_char(14, 39, "8");
    read_pix(319, 239, v);
    read_pix(319, 224, v);
    read_pix(312, 239, v);
    // reset clears the output register
    rst_n = 0; @(posedge clk); #1;
    if (pix_data !== 16'h0000) $fatal(1, "pix_data not cleared by reset: %h", pix_data);
    $display("PASS tb_osd");
    $finish;
  end
  initial begin #2_000_000; $fatal(1, "timeout"); end
endmodule
```

- [ ] **Step 3: Run test to verify it fails**

Run: `make -C sim tb_osd`
Expected: elaboration error `These modules were missing: osd_compositor`.

- [ ] **Step 4: Write `osd_text_ram.sv`**

```systemverilog
`include "common/defs.svh"
// Character RAM for the OSD: DEPTH bytes, bit7 = highlight, bits6:0 = ASCII. Initialised to spaces
// (0x20) so an unwritten screen is fully transparent. Read latency 1 clock.
//
// Read/write ordering: the read port returns the old byte when the same address is written in the
// same clock (read-first), but nothing synchronises ui_ctrl writes with the raster. A string written
// while the display is scanning that row can show a torn glyph (old and new character mixed) for
// one frame; this is accepted, the next frame is consistent.
//
// Synthesis: Vivado infers BRAM or distributed LUTRAM depending on DEPTH (either is fine at this
// size) and honours the initial-fill below as the memory's power-up contents.
module osd_text_ram #(
  parameter int DEPTH = 1024
) (
  input  logic                     clk,
  input  logic                     we,
  input  logic [$clog2(DEPTH)-1:0] waddr,
  input  logic [7:0]               wdata,
  input  logic [$clog2(DEPTH)-1:0] raddr,
  output logic [7:0]               rdata
);
  `PARAM_CHECK(g_chk_depth, DEPTH < 2, ("osd_text_ram: DEPTH must be >= 2"))

  logic [7:0] mem [0:DEPTH-1];
  initial for (int i = 0; i < DEPTH; i++) mem[i] = 8'h20;

  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    rdata <= mem[raddr];
  end
endmodule
```

- [ ] **Step 5: Write `osd_compositor.sv`**

```systemverilog
`include "common/defs.svh"
// Overlays 8x16 text on the framebuffer while the display controller scans pixels.
//
// Latency pix_x/pix_y -> pix_data: exactly 3 clocks. Two parallel paths meet in stage 2:
//   framebuffer: fb_rd_x/y (= pix_x/y, combinational) -> fb_rd_data after 2 clocks
//   text:        text RAM (1 clock) -> font ROM (1 clock)
// and the composed pixel is registered once more. pix_data is stable from the 3rd clock after an
// address change for as long as the address is held (st7789_ctrl holds it >= PIX_LAT = 6 clocks).
// All pipeline stages except the pix_data output register are intentionally reset-free: they carry
// only data derived from the current address and flush within 3 clocks of reset release.
//
// Text RAM byte: bit7 = highlight, bits6:0 = ASCII. Characters <= 0x20 are transparent (framebuffer
// shows through). Glyph ink: white, or green when highlighted. Background inside a non-space cell:
// framebuffer pixel dimmed by half per channel.
module osd_compositor #(
  parameter int WIDTH  = 320,
  parameter int HEIGHT = 240,
  parameter     FONT_FILE = {`MEM_DIR, "/font8x16.hex"}
) (
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic [$clog2(WIDTH)-1:0]  pix_x,
  input  logic [$clog2(HEIGHT)-1:0] pix_y,
  output logic [15:0]               pix_data,
  // framebuffer read port (2-cycle latency)
  output logic [$clog2(WIDTH)-1:0]  fb_rd_x,
  output logic [$clog2(HEIGHT)-1:0] fb_rd_y,
  input  logic [15:0]               fb_rd_data,
  // text RAM write port (from ui_ctrl): address = row * COLS + col
  input  logic                      txt_we,
  input  logic [9:0]                txt_waddr,
  input  logic [7:0]                txt_wdata
);
  localparam int COLS      = WIDTH / 8;    // 40 for 320
  localparam int ROWS      = HEIGHT / 16;  // 15 for 240
  localparam int TXT_DEPTH = 1024;
  localparam logic [15:0] C_WHITE = 16'hFFFF, C_GREEN = 16'h07E0;

  `PARAM_CHECK(g_chk_geom, WIDTH % 8 != 0 || HEIGHT % 16 != 0, ("osd_compositor: WIDTH must be a multiple of 8 and HEIGHT of 16"))
  `PARAM_CHECK(g_chk_cells, COLS * ROWS > TXT_DEPTH, ("osd_compositor: %0d text cells exceed the %0d-byte text RAM", COLS * ROWS, TXT_DEPTH))

  assign fb_rd_x = pix_x;
  assign fb_rd_y = pix_y;

  // stage 0: text cell address = (pix_y / 16) * COLS + pix_x / 8, all terms sized to the RAM address
  logic [9:0] txt_raddr;
  assign txt_raddr = 10'(pix_y >> 4) * 10'(COLS) + 10'(pix_x >> 3);
  logic [7:0] txt_rdata;
  osd_text_ram #(.DEPTH(TXT_DEPTH)) u_txt (.clk(clk), .we(txt_we), .waddr(txt_waddr), .wdata(txt_wdata),
                                           .raddr(txt_raddr), .rdata(txt_rdata));
  logic [2:0] x_d1; logic [3:0] y_d1; logic in_range_d1;
  always_ff @(posedge clk) begin
    x_d1 <= pix_x[2:0]; y_d1 <= pix_y[3:0];
    in_range_d1 <= (int'(pix_x) < WIDTH) && (int'(pix_y) < HEIGHT);
  end

  // stage 1: font address from the character (txt_rdata is the cell for the address of stage 0).
  // Blank cells look up glyph 0 (space) so the ROM address always stays < 96*16.
  logic [6:0]  ch_d1; logic hl_d1, blank_d1; logic [6:0] glyph_d1; logic [10:0] font_addr;
  assign ch_d1     = txt_rdata[6:0];
  assign hl_d1     = txt_rdata[7];
  assign blank_d1  = (ch_d1 <= 7'h20) || !in_range_d1;
  assign glyph_d1  = blank_d1 ? 7'd0 : ch_d1 - 7'h20;
  assign font_addr = 11'(glyph_d1) * 11'd16 + 11'(y_d1);
  logic [7:0] font_row;
  rom_init #(.WIDTH(8), .DEPTH(1536), .INIT_FILE(FONT_FILE)) u_font (.clk(clk), .addr(font_addr), .data(font_row));
  logic [2:0] x_d2; logic hl_d2, blank_d2;
  always_ff @(posedge clk) begin x_d2 <= x_d1; hl_d2 <= hl_d1; blank_d2 <= blank_d1; end

  // stage 2: compose (fb_rd_data and font_row both belong to the same pixel here)
  logic ink; logic [15:0] dim;
  assign ink = font_row[3'd7 - x_d2];
  assign dim = {1'b0, fb_rd_data[15:12], 1'b0, fb_rd_data[10:6], 1'b0, fb_rd_data[4:1]};
  always_ff @(posedge clk) begin
    if (!rst_n)        pix_data <= '0;
    else if (blank_d2) pix_data <= fb_rd_data;
    else if (ink)      pix_data <= hl_d2 ? C_GREEN : C_WHITE;
    else               pix_data <= dim;
  end
endmodule
```

- [ ] **Step 6: Run test to verify it passes**

Run: `make -C sim tb_osd`
Expected: `PASS tb_osd`

- [ ] **Step 7: Commit**

```bash
git add tools/gen_font.py mem/font8x16.hex src/display/osd_text_ram.sv src/display/osd_compositor.sv sim/tb/tb_osd.sv
git commit -m "feat(display): 8x16 font generator, text RAM and OSD compositor"
```

---

### Task 16: `ui_ctrl` — string writer

**Files:**
- Create: `src/display/ui_ctrl.sv`
- Test: `sim/tb/tb_ui_ctrl.sv`

A job = write one 8-character string (channel name `job_src=0` or fixed string `job_src=1`, index `job_idx`) at `(job_row, job_col)` with highlight `job_hl`. `job_ready` is high when idle; a job is accepted when `job_valid && job_ready`.

- [ ] **Step 1: Write the failing test**

```systemverilog
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_ui_ctrl`
Expected: `Unknown module type: ui_ctrl`.

- [ ] **Step 3: Write the implementation**

```systemverilog
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make -C sim tb_ui_ctrl`
Expected: `PASS tb_ui_ctrl`

- [ ] **Step 5: Commit**

```bash
git add src/display/ui_ctrl.sv sim/tb/tb_ui_ctrl.sv
git commit -m "feat(display): OSD string writer"
```

---

### Task 17: `ui_demo` sequencer and `lcd_test_top`

**Files:**
- Create: `src/display/ui_demo.sv`, `src/top/lcd_test_top.sv`
- Test: `sim/tb/tb_lcd_test_top.sv`

`ui_demo` writes the M1 screen: row 0 = channel 0 name + "TEST" (at `TEST_COL`, a top-level parameter, default 12); rows 1..3 at the right edge = channels 0,1,2 with the selected one highlighted. The button's short press advances the selection (0→1→2→0) and rewrites the list. `ui_demo` checks at elaboration that the channel name (cols 0..7), "TEST" and the list fit inside `COLS`; the list is on rows 1..3, so it may share columns with "TEST".

The TB uses a 160x64 window (20 text columns x 4 rows) so the header row and all three list rows are on screen. It reads `mem/font8x16.hex` and `mem/chan_names.hex` and compares each drawn cell's ink mask with the font glyph, so a wrong string, column or highlight colour fails; the pixel expectations carry their arithmetic in comments.

- [ ] **Step 1: Write the failing test**

```systemverilog
`timescale 1ns/1ps
module tb_lcd_test_top;
  // 160x64 window: 20 text columns x 4 rows, so the header row and all three list rows (1..3) are on screen.
  // Geometry used by the expectations below (test_pattern_gen, osd_compositor, ui_demo):
  //   BAR_W = 160/8 = 20      -> bar i covers x 20i..20i+19 (0 white, 1 yellow, 2 cyan, 3 green, 4 magenta, 5 red, 6 blue, 7 black)
  //   BARS_END = 64*2/3 = 42  -> y < 42 bars, y >= 42 grey gradient {lvl5, lvl6, lvl5}, lvl5 = x*32/160, lvl6 = x*64/160
  //   border: x = 0, x = 159, y = 0, y = 63 are white
  //   text cell (c, r) = x 8c..8c+7, y 16r..16r+15; LIST_COL = COLS-8 = 12 (x 96..159); TEST_COL = 12 on row 0
  localparam int W = 160, H = 64, COLS = W / 8, LIST_COL = COLS - 8, TEST_COL = 12;
  localparam logic [15:0] C_WHITE = 16'hFFFF, C_GREEN = 16'h07E0, C_DIM_WHITE = 16'h7BEF, C_MAGENTA = 16'hF81F;
  logic i_clk = 0; always #12.5 i_clk = ~i_clk;   // 40 MHz board clock (sim shim ignores the value)
  logic btn_n = 1;
  logic lcd_sclk, lcd_mosi, lcd_cs_n, lcd_dcx, lcd_resx_n;

  lcd_test_top #(.SYS_CLK_IN_HZ(40_000_000), .WIDTH(W), .HEIGHT(H), .SPI_CLK_DIV(1), .SIM_FAST(1),
                 .BTN_DEBOUNCE_MS(1), .BTN_LONG_MS(5), .TEST_COL(TEST_COL)) dut
    (.i_clk(i_clk), .btn_n(btn_n), .lcd_sclk(lcd_sclk), .lcd_mosi(lcd_mosi), .lcd_cs_n(lcd_cs_n), .lcd_dcx(lcd_dcx), .lcd_resx_n(lcd_resx_n));

  st7789v_slave_model #(.MIN_SCLK_PERIOD_NS(19.9), .RESET_TO_CMD_NS(5_000.0), .RESET_TO_SLPOUT_NS(120_000.0),
                        .SLPOUT_TO_CMD_NS(5_000.0), .SWRESET_TO_CMD_NS(5_000.0)) panel   // SIM_FAST: ms -> us
    (.sclk(lcd_sclk), .mosi(lcd_mosi), .cs_n(lcd_cs_n), .dcx(lcd_dcx), .resx_n(lcd_resx_n));

  // Reference ROMs: the font decides which pixels of a cell are ink, the channel-name ROM what the list says.
  logic [7:0] font [0:1535]; logic [7:0] names [0:511];
  initial begin $readmemh("mem/font8x16.hex", font); $readmemh("mem/chan_names.hex", names); end

  function automatic int count_cell(input int col, input int row, input logic [15:0] v);
    int n = 0;
    for (int y = row * 16; y < row * 16 + 16; y++) for (int x = col * 8; x < col * 8 + 8; x++) if (panel.pixel(x, y) == v) n++;
    return n;
  endfunction
  // Exact glyph check. Inside a non-blank cell every ink pixel is `ink` and every other pixel is a dimmed
  // framebuffer value (bit 15/10/4 clear, so never white or green): the ink mask must equal the font rows.
  function automatic bit glyph_ok(input int col, input int row, input byte ch, input logic [15:0] ink);
    for (int y = 0; y < 16; y++) for (int x = 0; x < 8; x++)
      if ((panel.pixel(col * 8 + x, row * 16 + y) == ink) != font[(int'(ch) - 32) * 16 + y][7 - x]) return 1'b0;
    return 1'b1;
  endfunction
  // Channel `idx` name (8 ROM bytes) drawn at (col,row) in `ink`; space cells are transparent and not checked.
  task automatic check_chan(input int col, input int row, input int idx, input logic [15:0] ink, input string what);
    for (int i = 0; i < 8; i++) if (names[idx * 8 + i] != 8'h20 && !glyph_ok(col + i, row, names[idx * 8 + i], ink))
      $fatal(1, "%s: channel %0d glyph '%c' at cell (%0d,%0d) not drawn in %h", what, idx, names[idx * 8 + i], col + i, row, ink);
  endtask
  task automatic check_test_hdr();
    logic [31:0] txt = "TEST";
    for (int i = 0; i < 4; i++) if (!glyph_ok(TEST_COL + i, 0, txt[31 - 8 * i -: 8], C_WHITE))
      $fatal(1, "header glyph '%c' at cell (%0d,0) not drawn in white", txt[31 - 8 * i -: 8], TEST_COL + i);
  endtask

  initial begin
    wait (panel.n_frames == 4);        // three complete frames written after init
    if (panel.n_errors != 0) $fatal(1, "protocol errors: %0d", panel.n_errors);
    // bar 1 (x 20..39) under text row 1 (y 16..31): cell (3,1) is blank -> pure yellow
    if (panel.pixel(30, 20) !== 16'hFFE0) $fatal(1, "bar pixel %h", panel.pixel(30, 20));
    // gradient row y = 50 (>= 42, not the border), cells (0,3) (7,3) (10,3) are blank (list starts at col 12):
    //   x = 1:  lvl5 = 1*32/160 = 0,   lvl6 = 1*64/160 = 0   -> 0x0000
    //   x = 60: lvl5 = 60*32/160 = 12, lvl6 = 60*64/160 = 24 -> {01100,011000,01100} = 0x630C
    //   x = 80: lvl5 = 80*32/160 = 16, lvl6 = 80*64/160 = 32 -> {10000,100000,10000} = 0x8410
    if (panel.pixel(1, 50) !== 16'h0000 || panel.pixel(60, 50) !== 16'h630C || panel.pixel(80, 50) !== 16'h8410)
      $fatal(1, "gradient wrong: %h %h %h", panel.pixel(1, 50), panel.pixel(60, 50), panel.pixel(80, 50));
    // cell (0,0) = 'A' over white bar 0 + white border: ink white + dimmed white background = whole cell
    if (count_cell(0, 0, C_WHITE) + count_cell(0, 0, C_DIM_WHITE) != 128) $fatal(1, "cell(0,0) not text-composited");
    if (count_cell(0, 0, C_WHITE) < 10) $fatal(1, "no glyph ink in cell(0,0)");
    // header row: channel 0 name at col 0, "TEST" at TEST_COL, both white
    check_chan(0, 0, 0, C_WHITE, "header");
    if (count_cell(TEST_COL, 0, C_WHITE) < 10) $fatal(1, "no glyph ink in the TEST cell");
    check_test_hdr();
    // the cell left of the list, (11,1) = x 88..95 inside bar 4 (x 80..99): untouched magenta, no dimming
    if (count_cell(LIST_COL - 1, 1, C_MAGENTA) != 128) $fatal(1, "cell left of the list is not pure bar colour");
    // list: entry 0 (row 1) highlighted green, entries 1 and 2 (rows 2, 3) white
    if (count_cell(LIST_COL, 1, C_GREEN) < 10) $fatal(1, "list entry 0 not highlighted");
    if (count_cell(LIST_COL, 2, C_GREEN) != 0) $fatal(1, "list entry 1 should not be highlighted");
    if (count_cell(LIST_COL, 2, C_WHITE) < 10) $fatal(1, "list entry 1 not drawn white");
    if (count_cell(LIST_COL, 3, C_GREEN) != 0) $fatal(1, "list entry 2 should not be highlighted");
    check_chan(LIST_COL, 1, 0, C_GREEN, "before press");
    check_chan(LIST_COL, 2, 1, C_WHITE, "before press");
    check_chan(LIST_COL, 3, 2, C_WHITE, "before press");
    // short press -> selection 1 highlighted after the next frames
    btn_n = 0; #2_000_000; btn_n = 1;   // 2 ms hold (debounce 1 ms, long 5 ms)
    wait (panel.n_frames == 7);
    if (panel.n_errors != 0) $fatal(1, "protocol errors after the press: %0d", panel.n_errors);
    if (count_cell(LIST_COL, 2, C_GREEN) < 10) $fatal(1, "list entry 1 not highlighted after button");
    if (count_cell(LIST_COL, 1, C_GREEN) != 0) $fatal(1, "list entry 0 still highlighted");
    if (count_cell(LIST_COL, 1, C_WHITE) < 10) $fatal(1, "list entry 0 not redrawn white");
    if (count_cell(LIST_COL, 3, C_GREEN) != 0) $fatal(1, "list entry 2 highlighted after button");
    check_chan(LIST_COL, 1, 0, C_WHITE, "after press");
    check_chan(LIST_COL, 2, 1, C_GREEN, "after press");
    check_chan(LIST_COL, 3, 2, C_WHITE, "after press");
    check_chan(0, 0, 0, C_WHITE, "after press"); check_test_hdr();   // header untouched by the list rewrite
    panel.dump_ppm("sim/build/tb_lcd_test_top.ppm");
    $display("PASS tb_lcd_test_top");
    $finish;
  end
  initial begin #60_000_000; $fatal(1, "timeout"); end
endmodule
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make -C sim tb_lcd_test_top`
Expected: `Unknown module type: lcd_test_top`.

- [ ] **Step 3: Write `ui_demo.sv`**

```systemverilog
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
```

- [ ] **Step 4: Write `lcd_test_top.sv`**

```systemverilog
// M1 hardware top: test pattern + OSD text on the ST7789V. Button (active low) cycles the highlighted list entry.
module lcd_test_top #(
  parameter int SYS_CLK_IN_HZ   = 40_000_000,
  parameter int WIDTH           = 320,
  parameter int HEIGHT          = 240,
  parameter int SPI_CLK_DIV     = 4,     // 100 MHz / 8 = 12.5 MHz SCLK (in spec)
  parameter bit SIM_FAST        = 0,
  parameter int BTN_DEBOUNCE_MS = 20,
  parameter int BTN_LONG_MS     = 1000,
  parameter int TEST_COL        = 12     // text column of the "TEST" header string (row 0)
) (
  input  logic i_clk,
  input  logic btn_n,
  output logic lcd_sclk,
  output logic lcd_mosi,
  output logic lcd_cs_n,
  output logic lcd_dcx,
  output logic lcd_resx_n
);
  localparam int SYS_CLK_HZ = 100_000_000;
  localparam int COLS = WIDTH / 8;

  // clocks and reset. MMCM lock is the only reset source: rst_n asserts while the MMCM is unlocked and
  // releases 4 sys_clk later; there is no reset pin, so re-resetting the design means reconfiguring the FPGA.
  logic sys_clk, locked, rst_n;
  clk_gen  #(.SYS_CLK_IN_HZ(SYS_CLK_IN_HZ), .SYS_CLK_OUT_HZ(SYS_CLK_HZ)) u_clk (.clk_in(i_clk), .clk_out(sys_clk), .locked(locked));
  rst_sync #(.N_STAGES(4)) u_rst (.clk(sys_clk), .arst_n(locked), .rst_n(rst_n));

  // display chain
  logic cs_req, tx_valid, tx_ready, tx_dc, spi_busy; logic [7:0] tx_data;
  logic [$clog2(WIDTH)-1:0] pix_x, fb_rd_x; logic [$clog2(HEIGHT)-1:0] pix_y, fb_rd_y;
  logic [15:0] pix_data, fb_rd_data;
  logic init_done;
  // status outputs not used by this top (no LEDs / debug port yet)
  /* verilator lint_off UNUSEDSIGNAL */
  logic frame_done, pat_busy, pat_done, pressed, long_press;
  /* verilator lint_on UNUSEDSIGNAL */

  st7789_spi_master #(.CLK_DIV(SPI_CLK_DIV)) u_spi (.clk(sys_clk), .rst_n(rst_n), .cs_req(cs_req),
    .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc), .busy(spi_busy),
    .sclk(lcd_sclk), .mosi(lcd_mosi), .cs_n(lcd_cs_n), .dcx(lcd_dcx));

  st7789_ctrl #(.CLK_HZ(SYS_CLK_HZ), .SIM_FAST(SIM_FAST), .WIDTH(WIDTH), .HEIGHT(HEIGHT), .PIX_LAT(6), .CLK_DIV(SPI_CLK_DIV)) u_ctrl (
    .clk(sys_clk), .rst_n(rst_n), .cs_req(cs_req), .tx_valid(tx_valid), .tx_ready(tx_ready), .tx_data(tx_data), .tx_dc(tx_dc),
    .spi_busy(spi_busy), .lcd_resx_n(lcd_resx_n), .pix_x(pix_x), .pix_y(pix_y), .pix_data(pix_data),
    .init_done(init_done), .frame_done(frame_done));

  // framebuffer + test pattern, drawn once when reset releases. The WIDTH*HEIGHT writes (76800 clocks =
  // 0.77 ms at 320x240) finish inside st7789_ctrl's 120 ms post-reset wait, so the first frame streamed
  // to the panel is already complete. (SIM_FAST shrinks that wait to 120 us: keep TB windows below ~12000 pixels.)
  logic pat_start, wr_en; logic [$clog2(WIDTH)-1:0] wr_x; logic [$clog2(HEIGHT)-1:0] wr_y; logic [15:0] wr_data;
  logic started;
  always_ff @(posedge sys_clk) begin
    if (!rst_n) begin started <= 1'b0; pat_start <= 1'b0; end
    else begin pat_start <= !started; started <= 1'b1; end
  end
  test_pattern_gen #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_pat (.clk(sys_clk), .rst_n(rst_n), .start(pat_start), .busy(pat_busy), .done(pat_done),
    .wr_en(wr_en), .wr_x(wr_x), .wr_y(wr_y), .wr_data(wr_data));
  framebuffer #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_fb (.clk(sys_clk), .wr_en(wr_en), .wr_x(wr_x), .wr_y(wr_y), .wr_data(wr_data),
    .rd_x(fb_rd_x), .rd_y(fb_rd_y), .rd_data(fb_rd_data));

  // OSD
  logic txt_we; logic [9:0] txt_waddr; logic [7:0] txt_wdata;
  osd_compositor #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_osd (.clk(sys_clk), .rst_n(rst_n), .pix_x(pix_x), .pix_y(pix_y), .pix_data(pix_data),
    .fb_rd_x(fb_rd_x), .fb_rd_y(fb_rd_y), .fb_rd_data(fb_rd_data), .txt_we(txt_we), .txt_waddr(txt_waddr), .txt_wdata(txt_wdata));

  logic job_valid, job_ready, job_src, job_hl; logic [3:0] job_row; logic [5:0] job_col, job_idx;
  ui_ctrl #(.COLS(COLS)) u_ui (.clk(sys_clk), .rst_n(rst_n), .job_valid(job_valid), .job_ready(job_ready), .job_row(job_row), .job_col(job_col),
    .job_src(job_src), .job_idx(job_idx), .job_hl(job_hl), .txt_we(txt_we), .txt_waddr(txt_waddr), .txt_wdata(txt_wdata));

  // button -> selection
  logic short_press; logic [1:0] sel;
  button_debounce #(.CLK_HZ(SYS_CLK_HZ), .DEBOUNCE_MS(BTN_DEBOUNCE_MS), .LONG_MS(BTN_LONG_MS), .ACTIVE_LOW(1)) u_btn
    (.clk(sys_clk), .rst_n(rst_n), .btn(btn_n), .pressed(pressed), .short_press(short_press), .long_press(long_press));
  always_ff @(posedge sys_clk) begin
    if (!rst_n) sel <= 2'd0;
    else if (short_press) sel <= (sel == 2'd2) ? 2'd0 : sel + 1'b1;
  end

  // ui_demo draws the screen once on the rising edge of init_done, then redraws the list on each short press
  logic init_done_d;
  always_ff @(posedge sys_clk) begin
    if (!rst_n) init_done_d <= 1'b0;
    else        init_done_d <= init_done;
  end
  ui_demo #(.COLS(COLS), .LIST_COL(COLS - 8), .TEST_COL(TEST_COL)) u_demo (.clk(sys_clk), .rst_n(rst_n), .start(init_done && !init_done_d),
    .sel_change(short_press), .sel(sel), .job_valid(job_valid), .job_ready(job_ready), .job_row(job_row), .job_col(job_col),
    .job_src(job_src), .job_idx(job_idx), .job_hl(job_hl));
endmodule
```

- [ ] **Step 5: Run the test**

Run: `make -C sim tb_lcd_test_top`
Expected: `st7789v_slave_model: wrote sim/build/tb_lcd_test_top.ppm (320x240)` (the model dumps the full MADCTL-sized panel; only the 160x64 window is written, the rest is magenta) then `PASS tb_lcd_test_top` (about 21 ms of simulated time). Convert and inspect: `.venv/bin/python -c "from PIL import Image; Image.open('sim/build/tb_lcd_test_top.ppm').crop((0,0,160,64)).resize((640,256), Image.NEAREST).save('sim/build/tb_lcd_test_top.png')"` — colour bars on top (ending at y = 42), grey gradient below, "A1 5865" over the bars at the left, "TEST" at column 12 above the list at the right (rows 1..3) with one green entry (the dump is taken after the button press, so row 2 = channel 1 is the green one).

Mutation check (done in a scratch copy, then discarded): `LIST_COL = COLS - 9` fails "cell left of the list is not pure bar colour", blanking the non-selected entries fails "list entry 1 not drawn white", `STR_TEST = 0` fails "no glyph ink in the TEST cell".

- [ ] **Step 6: Run the whole suite and lint**

Run: `make -C sim all && make -C sim lint`
Expected: every `PASS tb_*` line; Verilator reports no errors (warnings are reviewed and either fixed or waived with a `/* verilator lint_off */` comment and justification).

This is the first task where `make -C sim lint` has its top module, so warnings in earlier modules surface here. Two fixes outside this task's files: `clk_gen`'s `SIM` shim registers `locked` instead of comparing `lock_cnt` combinationally (Verilator SYNCASYNCNET: `lock_cnt` was reaching `rst_sync`'s async-reset sensitivity list through `locked`), and the lint command gets `--timescale 1ns/1ps` so modules without a `` `timescale`` no longer trip TIMESCALEMOD against `clk_gen`'s directive. The unused status outputs in `lcd_test_top` (`frame_done`, `pat_busy`, `pat_done`, `pressed`, `long_press`) are waived with `lint_off UNUSEDSIGNAL` until a debug/LED port uses them.

- [ ] **Step 7: Commit**

```bash
git add src/display/ui_demo.sv src/top/lcd_test_top.sv sim/tb/tb_lcd_test_top.sv src/common/clk_gen.sv sim/Makefile
git commit -m "feat(top): M1 LCD test top with pattern, OSD and button demo"
```

---

### Task 18: Bring-up checklist for M1 hardware

**Files:**
- Create: `docs/bringup-m1.md`

- [ ] **Step 1: Write the checklist**

```markdown
# M1 bring-up: test pattern on the ST7789V

Prerequisites: LCD pins (SCLK, SDA/MOSI, CS, DC, RESX, 3.3 V, GND) and the button pin are known and
entered in `constr/board_io.xdc` (uncomment and fill the `PACKAGE_PIN` lines). Board oscillator
frequency on N18 known (`SYS_CLK_IN_HZ`).

1. Build on the Vivado machine from the repo root:
   `vivado -mode batch -source vivado/build.tcl -tclargs lcd_test_top <SYS_CLK_IN_HZ>`
   Check `vivado/out/lcd_test_top_timing.rpt`: WNS >= 0, and `lcd_test_top_drc.rpt`: no UCIO-1 for LCD pins.
2. Program: `vivado -mode batch -source vivado/program.tcl -tclargs vivado/out/lcd_test_top.bit`
3. Expected on the panel within ~0.5 s: 1-px white border, 8 colour bars (white, yellow, cyan, green,
   magenta, red, blue, black) over the top 2/3, grey gradient below, text "A1 5865" top-left,
   "TEST" at column 12, three channel names on the right with the first one in green.
4. Short button press: the green highlight moves down (0 -> 1 -> 2 -> 0).

Troubleshooting knobs (parameters of `lcd_test_top` / constants in `tools/gen_st7789_rom.py`, then `make gen`):
- Blank / white screen: check RESX wiring and that `lcd_resx_n` pulses low at power-up (scope);
  try `INVERT = False`.
- Colours inverted: toggle `INVERT` in `gen_st7789_rom.py`.
- Mirrored / rotated: `MADCTL` 0x60 -> 0xA0 (or 0x00 / 0xC0 for portrait).
- Image shifted / wraps: panel may be 240x240 or offset; adjust CASET/RASET start in the generator.
- Washed out or dark: `VCOMS` (0xBB) 0x19..0x2B, `VRHS` (0xC3) 0x0B..0x15.
- Frame rate: raise SCLK with `SPI_CLK_DIV` 4 -> 2 -> 1 (25 / 50 MHz); watch for noise/tearing
  and check `lcd_sclk` edges on a scope (rise time <= 15 ns required by the datasheet).
```

- [ ] **Step 2: Commit**

```bash
git add docs/bringup-m1.md
git commit -m "docs: M1 LCD bring-up checklist"
```

---

## Self-review notes

- Spec coverage for M0/M1: skeleton + Makefiles (Task 1), common blocks (2–7), Tcl + XDC (8), ST7789V init ROM/SPI/ctrl (9–12), framebuffer + pattern (13), channel table (14), font/OSD (15), string writer (16), top + button (17), bring-up (18). `axil_regs` from the spec's M0 list is deferred to the M3 plan where its first consumer (`rf_regs`) appears.
- Interface names used consistently: `cs_req/tx_valid/tx_ready/tx_data/tx_dc/busy` (Tasks 10, 12, 17); `pix_x/pix_y/pix_data` (12, 15, 17); `txt_we/txt_waddr/txt_wdata` (15, 16, 17); `job_*` (16, 17); `wr_en/wr_x/wr_y/wr_data`, `rd_x/rd_y/rd_data` (13, 17).
- `st7789_ctrl` port `spi_busy` maps to the master's `busy` (Task 17 wiring).
