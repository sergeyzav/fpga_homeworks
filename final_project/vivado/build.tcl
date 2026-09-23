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
