# constraints
# ad9361
# i_clk (N18), the MMCM CLKIN1 CLOCK_DEDICATED_ROUTE workaround, and the UCIO-1 severity downgrade
# moved to constr/board_io.xdc: clk_gen's MMCM exists on every top, not just the RF ones, and this
# file is now only read for tops that instantiate the AD9363 RF interface (see vivado/build.tcl).

set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports rx_clk_in_p]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports rx_clk_in_n]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports rx_frame_in_p]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports rx_frame_in_n]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_p[0]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_n[0]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_p[1]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_n[1]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_p[2]}]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_n[2]}]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_p[3]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_n[3]}]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_p[4]}]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_n[4]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_p[5]}]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVDS_25 DIFF_TERM 1} [get_ports {rx_data_in_n[5]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVDS_25} [get_ports tx_clk_out_p]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVDS_25} [get_ports tx_clk_out_n]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVDS_25} [get_ports tx_frame_out_p]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVDS_25} [get_ports tx_frame_out_n]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p[0]}]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n[0]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p[1]}]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n[1]}]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p[2]}]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n[2]}]
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p[3]}]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n[3]}]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p[4]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n[4]}]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVDS_25} [get_ports {tx_data_out_p[5]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVDS_25} [get_ports {tx_data_out_n[5]}]

                        
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS25} [get_ports {ctrl_in[0]}]
set_property -dict {PACKAGE_PIN K14 IOSTANDARD LVCMOS25} [get_ports {ctrl_in[1]}]
set_property -dict {PACKAGE_PIN L17 IOSTANDARD LVCMOS25} [get_ports {ctrl_in[2]}]
set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS25} [get_ports {ctrl_in[3]}]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS25} [get_ports en_agc]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS25} [get_ports sync_in]
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS25} [get_ports chip_rst_n]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS25} [get_ports enable]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS25} [get_ports txnrx]


set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS25 PULLUP true} [get_ports o_spi_csn]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS25} [get_ports o_spi_clk]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS25} [get_ports o_spi_mosi]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS25} [get_ports i_spi_miso]



# clocks
create_clock -period 12.500 -name rx_clk [get_ports rx_clk_in_p]
