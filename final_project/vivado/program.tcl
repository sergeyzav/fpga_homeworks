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
