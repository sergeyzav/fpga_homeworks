# Creates a Vivado project for GUI work (schematic, ILA, timing analysis). Run from repo root:
#   vivado -mode batch -source vivado/create_project.tcl -tclargs <top> <sys_clk_in_hz>
set top  [lindex $argv 0]
set fin  [lindex $argv 1]
set root [file normalize [file join [file dirname [info script]] ..]]
create_project -force ${top}_proj $root/vivado/proj_$top -part xc7z020clg400-1
add_files -norecurse [lsort [glob $root/src/*/*.sv]]
add_files -norecurse [glob -nocomplain $root/mem/*.mem $root/mem/*.hex]
# Same RF-top scoping as vivado/build.tcl: ad9363.xdc's RF pins only apply to tops that
# instantiate the AD9363 interface; board_io.xdc/timing.xdc apply to every top.
add_files -fileset constrs_1 -norecurse $root/constr/board_io.xdc
add_files -fileset constrs_1 -norecurse $root/constr/timing.xdc
set rf_tops {fpv_detector_top}
if {[lsearch -exact $rf_tops $top] >= 0} { add_files -fileset constrs_1 -norecurse $root/constr/ad9363.xdc }
set_property include_dirs $root/src [current_fileset]
set_property top $top [current_fileset]
set_property generic SYS_CLK_IN_HZ=$fin [current_fileset]
set_property verilog_define MEM_DIR=\"$root/mem\" [current_fileset]
update_compile_order -fileset sources_1
puts "PROJECT CREATED: $root/vivado/proj_$top"
