#v10
set_property -dict {PACKAGE_PIN U10 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {reset_rtl}]

set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {gpio_btn_tri_i[0]}]
set_property -dict {PACKAGE_PIN U9 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {gpio_btn_tri_t[0]}]

set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {data[0]}]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {data[1]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {data[2]}]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {data[3]}]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {data[4]}]
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {data[5]}]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {data[6]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS18 PULLUP true} [get_ports {data[7]}]

set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS25} [get_ports clk_100]
# create_clock -period 10.000 -name clk_100 [get_ports clk_100]

set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS25} [get_ports aclk_external]
create_clock -period 1000.000 -name aclk_external [get_ports aclk_external]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets aclk_external_IBUF]