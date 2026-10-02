set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {gpio_leds_tri_io[0]}]
set_property -dict {PACKAGE_PIN U9 IOSTANDARD LVCMOS33} [get_ports {gpio_leds_tri_io[1]}]

set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {gpio_btn_tri_io[0]}]

set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {gpio_sw_tri_io[0]}]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {gpio_sw_tri_io[1]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {gpio_sw_tri_io[2]}]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {gpio_sw_tri_io[3]}]
