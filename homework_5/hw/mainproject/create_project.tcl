set main_dir [file normalize [file dirname [info script]]]
set project_name "homework5_main_project"
set build_dir    [file normalize "$main_dir/../../build"]

create_project $project_name "$build_dir/$project_name" -part xc7z020clg400-1 -force
set main_proj [current_project]

set_property target_language Verilog $main_proj

add_files -fileset constrs_1 -norecurse "$main_dir/constraints.xdc"

# add_files -fileset sources_1 [glob -nocomplain ../src/*.sv]
add_files -fileset sim_1 [glob -nocomplain "$main_dir/sim/*.sv"]

set_property top tb_microblaze_wrapper [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1


set ip_modules {
    "axi_full_ram"
    "axi_picture_frame_tx"
}

foreach ip $ip_modules {
    set script_path [file normalize "$main_dir/../library/$ip/${ip}.tcl"]
    if {![file exists $script_path]} {
        error "not found $script_path"
        
    } 

    puts "-> Pack IP: $ip"
    source $script_path

    close_project
    current_project $main_proj
}

set repo_paths {}
foreach ip $ip_modules {
    lappend repo_paths [file normalize "$build_dir/ip_repo/$ip"]
}
set_property IP_REPO_PATHS $repo_paths [current_project]
update_ip_catalog -rebuild

source "$main_dir/microblaze.tcl"

set bd_file [get_files microblaze.bd]
make_wrapper -files $bd_file -top
add_files -norecurse [file normalize "$build_dir/$project_name/${project_name}.gen/sources_1/bd/microblaze/hdl/microblaze_wrapper.v"]
set_property top microblaze_wrapper [current_fileset]
update_compile_order -fileset sources_1
