
set project_name "homework3_task3_pipelined"
#fpga_homeworks/build
set build_dir "../../../build" 

create_project $project_name "$build_dir/$project_name" -part xc7z020clg400-1 -force

set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob -nocomplain ../src/*.sv]
add_files -fileset constrs_1 [glob -nocomplain ../constr/*.xdc]

#set_property top pythagoras_squares_comb  [get_filesets sources_1]
set_property top pythagoras_squares_pipelined  [get_filesets sources_1]
set_property target_constrs_file [get_files ../constr/clock.xdc] [get_filesets constrs_1]

update_compile_order -fileset sources_1

