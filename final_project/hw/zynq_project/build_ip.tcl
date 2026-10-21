# Builds the ADI library IPs used by the "system" block design.
# Each IP is packaged by its own <name>_ip.tcl (creates component.xml).
# Already packaged IPs are skipped unless force = 1.

# Order matters: interfaces and helper cores first.
set adi_ip_list {
  interfaces
  util_cdc
  util_axis_fifo
  axi_dmac
  axi_ad9361
  xilinx/util_clkdiv
  util_pack/util_cpack2
  util_pack/util_upack2
  util_rfifo
  util_wfifo
  util_tdd_sync
}

proc adi_build_ips {lib_dir ip_list {force 0}} {
  # ADI scripts expect Vivado 2021.1; turn the hard error into a warning.
  set ::env(ADI_IGNORE_VERSION_CHECK) 1

  set start_dir [pwd]
  foreach ip $ip_list {
    set ip_dir  [file join $lib_dir $ip]
    set ip_name [file tail $ip]
    set ip_tcl  [file join $ip_dir ${ip_name}_ip.tcl]

    if {$ip_name eq "interfaces"} {
      set done [file exists [file join $ip_dir fifo_wr.xml]]
    } else {
      set done [file exists [file join $ip_dir component.xml]]
    }
    if {$done && !$force} {
      puts "INFO: \[adi_build_ips\] $ip already packaged, skipping"
      continue
    }
    if {![file exists $ip_tcl]} {
      error "IP script not found: $ip_tcl"
    }

    puts "INFO: \[adi_build_ips\] packaging $ip"
    cd $ip_dir
    # Source at global level: the ADI procs read ad_hdl_dir etc. as globals.
    set rc [catch {uplevel #0 [list source [file tail $ip_tcl]]} msg]
    catch {close_project}
    cd $start_dir
    if {$rc} {
      error "Failed to package $ip: $msg"
    }
  }
}
