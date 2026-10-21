set mylib_dir  [file normalize [file dirname [info script]]]
set my_ip_list {
  zavadi_rf_capture
}

source [file join $mylib_dir .. zynq_project build_ip.tcl]
adi_build_ips $mylib_dir $my_ip_list 1
