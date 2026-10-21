set main_dir [file normalize [file dirname [info script]]]
set project_name "final_project_"
set build_dir    [file normalize "$main_dir/../../build"]

create_project $project_name "$build_dir/$project_name" -part xc7z020clg400-2 -force
set main_proj [current_project]

set_property target_language Verilog $main_proj

add_files -fileset constrs_1 -norecurse "$main_dir/board.xdc"

# add_files -fileset sources_1 [glob -nocomplain ../src/*.sv]
# add_files -fileset sim_1 [glob -nocomplain "$main_dir/sim/*.sv"]

# set_property top tb_microblaze_wrapper [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1


set adi_ip_modules {
    "axi_ad9361"
    "axi_dmac"
    "util_rfifo"
    "util_wfifo"
    "util_pack/util_cpack2"
    "util_pack/util_upack2"
    "xilinx/util_clkdiv"
    "util_tdd_sync"
}


foreach ip $adi_ip_modules {
    set ip_dir [file normalize "$main_dir/../library/$ip"]
    if {![file exists "$ip_dir/component.xml"]} {
        set ip_name [file tail $ip]
        set script_path "$ip_dir/${ip_name}_ip.tcl"
        if {![file exists $script_path]} {
            error "not found $script_path"
        }

        puts "-> Pack ADI IP: $ip"
        # ADI scripts use paths relative to their own folder
        set old_dir [pwd]
        cd $ip_dir
        source $script_path
        close_project
        cd $old_dir
        current_project $main_proj
    }
    lappend repo_paths $ip_dir
}
set_property IP_REPO_PATHS $repo_paths [current_project]
update_ip_catalog -rebuild

source "$main_dir/adi_base.tcl"

set bd_file [get_files microblaze.bd]
make_wrapper -files $bd_file -top
add_files -norecurse [file normalize "$build_dir/$project_name/${project_name}.gen/sources_1/bd/microblaze/hdl/microblaze_wrapper.v"]
set_property top microblaze_wrapper [current_fileset]
update_compile_order -fileset sources_1