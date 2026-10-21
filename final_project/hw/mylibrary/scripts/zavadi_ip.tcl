set zavadi_lib_dir [file normalize [file join [file dirname [info script]] ..]]

source [file join $zavadi_lib_dir .. scripts adi_env.tcl]
source $ad_hdl_dir/library/scripts/adi_ip_xilinx.tcl

proc zavadi_ip_finish {} {
  set cc [ipx::current_core]
  set_property vendor              zavadi    $cc
  set_property library             user      $cc
  set_property vendor_display_name {Zavadi}  $cc
  set_property company_url         {}        $cc
  set_property taxonomy            {/Zavadi} $cc
  ipx::create_xgui_files $cc
  ipx::update_checksums  $cc
  ipx::save_core         $cc
}
