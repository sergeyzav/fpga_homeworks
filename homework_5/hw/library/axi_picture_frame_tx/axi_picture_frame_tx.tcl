set ip_name "axi_picture_frame_tx"
set ip_vendor "zavada.org"
set ip_library "user"
set ip_version "1.0"

set script_dir [file normalize [file dirname [info script]]]
set work_dir [file normalize "$script_dir/../../../build/ip_repo/${ip_name}"]

create_project -in_memory -part xc7z020clg400-1
add_files -norecurse "$script_dir/${ip_name}.sv"
update_compile_order -fileset sources_1

ipx::package_project -root_dir $work_dir -vendor $ip_vendor -library $ip_library -taxonomy /UserIP -version $ip_version -import_files

set core [ipx::current_core]
set_property display_name "AXI Picture Frame TX" $core
set_property description "AXI Picture Frame Transmitter" $core

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core