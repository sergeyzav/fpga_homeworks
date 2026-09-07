
set project_name "led_blinker"
#fpga_homeworks/build
set build_dir "../../build" 

create_project $project_name "$build_dir/$project_name" -part xc7z020clg400-1 -force

set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob -nocomplain ../src/*.sv]
add_files -fileset sim_1 [glob -nocomplain ../sim/*.sv]
add_files -fileset constrs_1 [glob -nocomplain ../constr/*.xdc]

set_property top led_blinker [get_filesets sources_1]
set_property top tb_led_blinker [get_filesets sim_1]
set_property target_constrs_file [get_files ../constr/led_blinker.xdc] [get_filesets constrs_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
