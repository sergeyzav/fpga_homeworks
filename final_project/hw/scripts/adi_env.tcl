# Minimal ADI environment for packing IPs from hw/library/*/*_ip.tcl
# (replacement for hdl/scripts/adi_env.tcl from the ADI hdl repo)

# hw/ plays the role of the ADI hdl root (contains library/)
set ad_hdl_dir  [file normalize [file join [file dirname [info script]] ".."]]
set ad_ghdl_dir $ad_hdl_dir

# Accept the installed Vivado version (ADI scripts otherwise call `exit 2` on mismatch)
set required_vivado_version [version -short]
set IGNORE_VERSION_CHECK 1

# projects/scripts/adi_xilinx_msg.tcl is not in this repo
set ::env(ADI_DISABLE_MESSAGE_SUPPRESION) 1
