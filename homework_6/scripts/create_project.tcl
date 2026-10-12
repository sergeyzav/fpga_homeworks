
set script_dir   [file dirname [file normalize [info script]]]
set project_name "homework6_ila_vio"
set part         "xc7z020clg400-1"

# fpga_homeworks/build
set build_dir    [file normalize "$script_dir/../../build"]
set proj_dir     "$build_dir/$project_name"

set src_dir      [file normalize "$script_dir/../src"]
set sim_dir      [file normalize "$script_dir/../sim"]
set constr_dir   [file normalize "$script_dir/../constr"]


create_project $project_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]


proc add_if_exist {fileset pattern} {
    set files [glob -nocomplain $pattern]
    if {[llength $files] > 0} {
        add_files -norecurse -fileset $fileset $files
    } else {
        puts "WARNING: no files matched $pattern"
    }
}


add_if_exist sources_1 "$src_dir/*.sv"
add_if_exist sources_1 "$src_dir/*.v"
add_if_exist sim_1     "$sim_dir/*.sv"
add_if_exist constrs_1 "$constr_dir/*.xdc"


set xdc [get_files -quiet led_blinker.xdc]
if {$xdc ne ""} {
    set_property target_constrs_file $xdc [get_filesets constrs_1]
}


set_property top tb_led_blinker [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

update_compile_order -fileset sources_1


source "$script_dir/top_wrapper.tcl"

set bd_file [get_files top_wrapper.bd]
generate_target all $bd_file


set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse -fileset sources_1 $wrapper

set_property top top_wrapper_wrapper [get_filesets sources_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "INFO: project created at $proj_dir"
