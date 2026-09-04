
set project_name "homework1_counter"
#fpga_homeworks/build
set build_dir "../../../build" 

create_project $project_name "$build_dir/$project_name" -part xc7z020clg400-1 -force

set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob -nocomplain ../src/*.sv]
add_files -fileset sim_1 [glob -nocomplain ../sim/*.sv]

set_property top led [get_filesets sources_1]
set_property top tb_led [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
