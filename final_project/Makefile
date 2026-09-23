# Top-level convenience targets. Simulation lives in sim/Makefile.
PYTHON ?= .venv/bin/python

.PHONY: sim lint gen venv clean tclcheck pytests test
sim:
	$(MAKE) -C sim all
lint:
	$(MAKE) -C sim lint
tclcheck:
	@for f in vivado/*.tcl constr/*.xdc; do \
		echo "proc unknown {args} {}; proc get_hw_devices {args} {return {xc7z020_dummy}}; set argv {lcd_test_top 40000000}; if {[catch {source $$f} err]} { puts stderr \$$err; exit 1 }" | tclsh || exit 1; \
	done
	@echo "tclcheck ok"
pytests:
	@for f in tools/test_*.py; do \
		$(PYTHON) $$f || exit 1; \
	done
test: sim lint tclcheck pytests
gen:
	$(PYTHON) tools/gen_st7789_rom.py
	$(PYTHON) tools/gen_font.py
	$(PYTHON) tools/gen_chan_names.py
	$(PYTHON) tools/gen_ui_strings.py
venv:
	python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
clean:
	$(MAKE) -C sim clean
