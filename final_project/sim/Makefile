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
	cd $(ROOT) && set -o pipefail && $(VERILATOR) --lint-only -Wall -DSIM -Wno-DECLFILENAME -Wno-UNUSEDPARAM --timescale 1ns/1ps \
	  -Isrc $(SRCS) --top-module lcd_test_top 2>&1 | tee $(BUILD)/lint.log

clean:
	rm -rf $(BUILD)
