`timescale 1ns/100ps

module zavadi_rf_capture #(
  parameter int HIT_LEN       = 16,
  parameter int CAPTURE_SAMPLES = 625000,
  parameter int HANG_SAMPLES    = 31250
) (
  // AXI-lite slave 
  input  logic        s_axi_aclk,
  input  logic        s_axi_aresetn,

  input  logic        s_axi_awvalid,
  input  logic [11:0] s_axi_awaddr,
  input  logic [ 2:0] s_axi_awprot,
  output logic        s_axi_awready,

  input  logic        s_axi_wvalid,
  input  logic [31:0] s_axi_wdata,
  input  logic [ 3:0] s_axi_wstrb,
  output logic        s_axi_wready,

  output logic        s_axi_bvalid,
  output logic [ 1:0] s_axi_bresp,
  input  logic        s_axi_bready,

  input  logic        s_axi_arvalid,
  input  logic [11:0] s_axi_araddr,
  input  logic [ 2:0] s_axi_arprot,
  output logic        s_axi_arready,

  output logic        s_axi_rvalid,
  output logic [31:0] s_axi_rdata,
  output logic [ 1:0] s_axi_rresp,
  input  logic        s_axi_rready,

  // data domain
  input  logic        clk,
  input  logic        reset,

  // input data FIFO
  input  logic        s_fifo_wr_en,
  input  logic [63:0] s_fifo_wr_data,
  output logic        s_fifo_wr_overflow,

  // output data FIFO
  output logic        m_fifo_wr_en,
  output logic [63:0] m_fifo_wr_data,
  input  logic        m_fifo_wr_overflow,
  input  logic        m_fifo_wr_xfer_req
);

  logic [31:0] threshold_axi;     
  logic [3:0]  cmd_tgl_axi;       
  logic [2:0]  state_axi;        
  logic [31:0] active_samples_axi;  
  logic [31:0] pwr_axi;

  logic [31:0] threshold_div;     
  logic [3:0]  cmd_pulse_div;       
  logic [2:0]  state_div;        
  logic [31:0] active_samples_div;  
  logic [31:0] pwr_div; 

  logic detector_en;
  logic capture_en;
  logic start_recording;
  logic hit;
  logic capture_done;

  assign m_fifo_wr_data = s_fifo_wr_data;
  assign s_fifo_wr_overflow = m_fifo_wr_overflow;
  assign m_fifo_wr_en = s_fifo_wr_en && capture_en;

  axi_lite_cfg #(.CAPTURE_SAMPLES(CAPTURE_SAMPLES), .ADDR_WIDTH(12)) i_axi_lite_cfg (
    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awready(s_axi_awready),

    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wready(s_axi_wready),

    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bready(s_axi_bready),

    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arready(s_axi_arready),

    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rready(s_axi_rready),

    .threshold(threshold_axi),     
    .cmd_tgl(cmd_tgl_axi),       
    .state(state_axi),  
    .active_samples(active_samples_axi),    
    .pwr(pwr_axi)        
  );

  gate_cdc i_gate_cdc (
    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),

    .cmd_tgl_axi(cmd_tgl_axi),
    .threshold_axi(threshold_axi),
    .state_axi(state_axi),
    .active_samples_axi(active_samples_axi),
    .pwr_axi(pwr_axi),

    .clk_div(clk),
    .rst_div(reset),             

    .cmd_pulse_div(cmd_pulse_div),        
    .threshold_div(threshold_div),
    .state_div(state_div),
    .active_samples_div(active_samples_div),
    .pwr_div(pwr_div)
);

power_detector #(.HIT_LEN(HIT_LEN)) i_power_detector (
  .data_clk(clk), 
  .data_rst(reset),
  .data_en(s_fifo_wr_en),          
  .data(s_fifo_wr_data),        
  .thresh(threshold_div),      
  .detector_en(detector_en),   
  .hit(hit),         
  .pwr(pwr_div)
);

record_counter #(.CAPTURE_SAMPLES(CAPTURE_SAMPLES), .HANG_SAMPLES(HANG_SAMPLES)) i_record_counter (
  .data_clk(clk),
  .data_rst(reset),
  .data_en(m_fifo_wr_en),
  .start(start_recording),
  .hit(hit),            
  .capture_done(capture_done),  
  .active_samples(active_samples_div)    
);

capture_fsm i_capture_fsm (
    .data_clk(clk),
    .data_rst(reset),

    .data_en(s_fifo_wr_en),        
    .cmd_scan(cmd_pulse_div[0]),
    .cmd_reset(cmd_pulse_div[1]),
    .cmd_replay_begin(cmd_pulse_div[2]),
    .cmd_replay_end(cmd_pulse_div[3]),

    .hit(hit),
    .capture_done(capture_done),
    .dma_ready(m_fifo_wr_xfer_req),

    .state(state_div),
    .detector_en(detector_en),
    .start(start_recording),
    .capture_en(capture_en)
);
endmodule
