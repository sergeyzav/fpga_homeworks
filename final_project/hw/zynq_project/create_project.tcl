set script_dir [file normalize [file dirname [info script]]]
set hdl_dir    [file normalize [file join $script_dir ..]]
set lib_dir    [file join $hdl_dir library]
set mylib_dir  [file join $hdl_dir mylibrary]

set proj_name  zc702
set build_dir  [file normalize [file join $script_dir ../../build]]
set proj_dir   [file join $build_dir $proj_name]
set part       xc7z020clg400-1
set jobs       8

set do_build  [expr {[lsearch $argv build]    >= 0}]
set force_ip  [expr {[lsearch $argv force_ip] >= 0}]

# 1. ADI library IPs
source [file join $script_dir build_ip.tcl]
adi_build_ips $lib_dir $adi_ip_list $force_ip

# 1b. Own IPs from hw/mylibrary 
source [file join $mylib_dir build_mylib.tcl]

# 2. Project
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]
set_property ip_repo_paths [list $lib_dir $mylib_dir] [current_project]
update_ip_catalog

# 3. Block design 
source [file join $script_dir bd system_bd.tcl]
set bd_file [get_files system.bd]
validate_bd_design
save_bd_design
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper

add_files -norecurse [list \
  [file join $script_dir src system_top.v] \
  [file join $lib_dir common ad_iobuf.v] \
]
add_files -fileset constrs_1 -norecurse [list \
  [file join $script_dir constr system_constr.xdc] \
]
set_property top system_top [current_fileset]
update_compile_order -fileset sources_1

# fix WHS
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE ExploreWithAggressiveHoldFix [get_runs impl_1]

if {$do_build} {
  launch_runs impl_1 -to_step write_bitstream -jobs $jobs
  wait_on_run impl_1
  if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed, see $proj_dir/$proj_name.runs/impl_1"
  }
  open_run impl_1
  write_hw_platform -fixed -include_bit -force \
    -file [file join $build_dir system_top.xsa]
  puts "INFO: done -> [file join $build_dir system_top.xsa]"
}
