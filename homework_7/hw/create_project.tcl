set main_dir [file normalize [file dirname [info script]]]
set project_name "homework7_hls"
set build_dir    [file normalize "$main_dir/../../build"]

create_project $project_name "$build_dir/$project_name" -part xc7z020clg400-1 -force
set main_proj [current_project]

set_property target_language Verilog $main_proj

add_files -fileset sim_1 [glob -nocomplain "$main_dir/sim/*.sv"]
set_property top tb_hls [get_filesets sim_1]
update_compile_order -fileset sim_1

import_files [glob $main_dir/ip/hdl/verilog/*.v]
update_compile_order -fileset sources_1
