source ../scripts/zavadi_ip.tcl

adi_ip_create zavadi_rf_capture
adi_ip_files zavadi_rf_capture [list \
  "axi_lite_cfg.sv" \
  "gate_cdc.sv" \
  "power_detector.sv" \
  "record_counter.sv" \
  "capture_fsm.sv" \
  "zavadi_rf_capture.sv" ]

adi_ip_properties zavadi_rf_capture

# Input: from util_cpack2/packed_fifo_wr
adi_add_bus "s_fifo_wr" "slave" \
  "analog.com:interface:fifo_wr_rtl:1.0" \
  "analog.com:interface:fifo_wr:1.0" \
  { \
    {"s_fifo_wr_en"       "EN"} \
    {"s_fifo_wr_data"     "DATA"} \
    {"s_fifo_wr_overflow" "OVERFLOW"} \
  }

# Output: to axi_dmac/fifo_wr 
adi_add_bus "m_fifo_wr" "master" \
  "analog.com:interface:fifo_wr_rtl:1.0" \
  "analog.com:interface:fifo_wr:1.0" \
  { \
    {"m_fifo_wr_en"       "EN"} \
    {"m_fifo_wr_data"     "DATA"} \
    {"m_fifo_wr_overflow" "OVERFLOW"} \
    {"m_fifo_wr_xfer_req" "XFER_REQ"} \
  }

adi_add_bus_clock "clk" "s_fifo_wr:m_fifo_wr" "reset"


zavadi_ip_finish
