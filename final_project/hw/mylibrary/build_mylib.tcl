# Packs every IP core in hw/mylibrary.
# Always repackages: these cores are under development.
#
# Standalone (from any folder):
#   vivado -mode batch -source <path>/hw/mylibrary/build_mylib.tcl
# Also sourced by hw/zynq_project/create_project.tcl.
#
# Requires the ADI "interfaces" core (fifo_wr) to be packaged already:
# run create_project.tcl once, or package hw/library/interfaces first.

set mylib_dir  [file normalize [file dirname [info script]]]
set my_ip_list {
  zavadi_rf_capture
}

# adi_build_ips: cd into each core folder and source <name>_ip.tcl
source [file join $mylib_dir .. zynq_project build_ip.tcl]
adi_build_ips $mylib_dir $my_ip_list 1
