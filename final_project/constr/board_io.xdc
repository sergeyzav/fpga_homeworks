# Board oscillator input and MMCM/DRC essentials. Kept here (not constr/ad9363.xdc) because
# clk_gen's MMCM exists on every top, not just the AD9363 RF ones, and this file is always read
# by vivado/build.tcl and vivado/create_project.tcl regardless of top.
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS25} [get_ports i_clk]
# The MMCM input net name depends on our RTL hierarchy, not the old clk_wiz project this was
# adapted from.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -of_objects [get_pins -hierarchical -filter {NAME =~ */u_mmcm/CLKIN1}]]
# UCIO-1 (unconstrained/partially-constrained I/O) is downgraded to a warning ONLY until the LCD
# and button PACKAGE_PINs below are known; remove this downgrade once they are filled in.
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

# LCD (ST7789V, 4-wire SPI) and button. PACKAGE_PINs are NOT KNOWN YET - fill in before hardware use.
# Until then UCIO-1 is downgraded above (only until the LCD/button pins are known) and Vivado
# will auto-place these ports: do not connect the panel to a bitstream built with unassigned pins.
#
# Choosing IOSTANDARD: match the VCCO of the bank the LCD/button pins end up in. The AD9363 banks
# and N18 are 2.5 V (LVCMOS25) on this board; a 2.5 V high level is marginal against the ST7789V's
# VIH = 0.7 * VDDI if the module's IOVCC is 3.3 V. Either place these pins in a 3.3 V bank
# (LVCMOS33, the placeholder below) or power the module's VDDI at 2.5-2.8 V instead. Keep
# LVCMOS33 as the placeholder until the real bank is known.
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
