`timescale 1ns/100ps

module tb_axi_lite_cfg;

  localparam logic [11:0] CMD_TGL_ADDR      = 'h000; // wo
  localparam logic [11:0] STATE_ADDR        = 'h004; // ro
  localparam logic [11:0] THRESHOLD_ADDR    = 'h008; // rw
  localparam logic [11:0] CAPTURE_SAMPLES_ADDR     = 'h00C; // ro
  localparam logic [11:0] ACTIVE_SAMPLES_ADDR = 'h010; // ro
  localparam logic [11:0] PWR_ADDR          = 'h014; // ro
  
  localparam logic [11:0] INVALID_ADDR = 'hFFF;

  reg s_axi_aclk;
  reg s_axi_aresetn;
  reg s_axi_awvalid;
  reg [11:0] s_axi_awaddr;
  wire s_axi_awready;

  reg s_axi_wvalid;
  reg [31:0] s_axi_wdata;
  reg [3:0] s_axi_wstrb;
  wire s_axi_wready;

  wire s_axi_bvalid;
  wire [1:0] s_axi_bresp;
  reg s_axi_bready;

  reg s_axi_arvalid;
  reg [11:0] s_axi_araddr;
  wire s_axi_arready;

  wire s_axi_rvalid;
  wire [31:0] s_axi_rdata;
  wire [1:0] s_axi_rresp;
  reg s_axi_rready;

  wire [31:0] threshold;
  wire [3:0] cmd_tgl;
  reg [2:0] state;
  reg [31:0] active_samples;
  reg [31:0] pwr;
  
  reg [31:0] data;
  reg [1:0] resp;

  axi_lite_cfg #(
    .ADDR_WIDTH      (12),
    .CAPTURE_SAMPLES (1000)
  ) dut_1 (
    .s_axi_aclk     (s_axi_aclk),
    .s_axi_aresetn  (s_axi_aresetn),

    .s_axi_awvalid  (s_axi_awvalid),
    .s_axi_awaddr   (s_axi_awaddr),
    .s_axi_awready  (s_axi_awready),

    .s_axi_wvalid   (s_axi_wvalid),
    .s_axi_wdata    (s_axi_wdata),
    .s_axi_wstrb    (s_axi_wstrb),
    .s_axi_wready   (s_axi_wready),

    .s_axi_bvalid   (s_axi_bvalid),
    .s_axi_bresp    (s_axi_bresp),
    .s_axi_bready   (s_axi_bready),

    .s_axi_arvalid  (s_axi_arvalid),
    .s_axi_araddr   (s_axi_araddr),
    .s_axi_arready  (s_axi_arready),

    .s_axi_rvalid   (s_axi_rvalid),
    .s_axi_rdata    (s_axi_rdata),
    .s_axi_rresp    (s_axi_rresp),
    .s_axi_rready   (s_axi_rready),

    .threshold      (threshold),
    .cmd_tgl        (cmd_tgl),
    .state          (state),
    .active_samples (active_samples),
    .pwr            (pwr)
  );

  always #5 s_axi_aclk = ~s_axi_aclk;
  initial s_axi_aclk = 0;
  

  task automatic read_from_addr_task(input logic [11:0] addr, output logic [31:0] response, output logic [1:0] resp);
    @(posedge s_axi_aclk);
    s_axi_arvalid <= 1'b1;
    s_axi_araddr <= addr;

    while (!s_axi_arready) @(posedge s_axi_aclk);
    s_axi_arvalid <= 1'b0;

    s_axi_rready <= 1'b1;
    @(posedge s_axi_aclk);
    while (!s_axi_rvalid) @(posedge s_axi_aclk);
    response = s_axi_rdata;
    resp = s_axi_rresp;
    s_axi_rready <= 1'b0;
  endtask

  task automatic write_to_addr_task(input logic [11:0] addr, input logic [31:0] data, output logic [1:0] bresp);
    @(posedge s_axi_aclk);
    s_axi_awaddr <= addr;
    s_axi_awvalid <= 1'b1;

    s_axi_wdata <= data;
    s_axi_wstrb <= 4'b1111;
    s_axi_wvalid <= 1'b1;
    
    while (!s_axi_awready) @(posedge s_axi_aclk);
    s_axi_awvalid <= 1'b0;

    while (!s_axi_wready) @(posedge s_axi_aclk);
    s_axi_wvalid <= 1'b0;

    s_axi_bready <= 1'b1;
    while (!s_axi_bvalid) @(posedge s_axi_aclk);
    bresp = s_axi_bresp;
    s_axi_bready <= 1'b0;
  endtask

initial begin
    s_axi_awvalid  = 1'b0;
    s_axi_awaddr   = 12'b0;
    s_axi_wvalid   = 1'b0;
    s_axi_wdata    = 32'b0;
    s_axi_wstrb    = 4'b0;
    s_axi_bready   = 1'b0;
    s_axi_arvalid  = 1'b0;
    s_axi_araddr   = 12'b0;
    s_axi_rready   = 1'b0;
    state          = 3'b0;
    active_samples = 32'b0;
    pwr            = 32'b0;

    s_axi_aresetn = 1'b0;
    repeat (3) @(posedge s_axi_aclk);
    s_axi_aresetn <= 1'b1;
    
    
    //test read/write
    write_to_addr_task(THRESHOLD_ADDR, 32'd1234567, resp);
    if (resp != 2'b00)
        $error("Bad resp(%b) during write_to_addr_task - THRESHOLD_ADDR expected (%b)", resp, 2'b00);   
    if (threshold != 32'd1234567)
        $error("Bad threshold val(%d) during write_to_addr_task - THRESHOLD_ADDR expected (%d)", threshold, 32'd1234567); 
    
    read_from_addr_task(THRESHOLD_ADDR, data, resp);
    if (resp != 2'b00)
        $error("Bad resp(%b) during read_from_addr_task - THRESHOLD_ADDR expected (%b)", resp, 2'b00);   
    if (data != 32'd1234567)
        $error("Bad threshold val(%d) during read_from_addr_task - THRESHOLD_ADDR expected (%d)", data, 32'd1234567); 
        
    //test only write;
    write_to_addr_task(CMD_TGL_ADDR, {28'b0, 4'b1010}, resp);
    if (resp != 2'b00)
        $error("Bad resp(%b) during write_to_addr_task - CMD_TGL_ADDR expected (%b)", resp, 2'b00);   
    if (cmd_tgl != 4'b1010)
        $error("Bad cmd_tgl val(%b) during write_to_addr_task - CMD_TGL_ADDR expected (%b)", cmd_tgl, 4'b1010); 
    
    //forbbiden read
    read_from_addr_task(CMD_TGL_ADDR, data, resp);
    if (resp != 2'b11)
        $error("Bad resp(%b) during read_from_addr_task - CMD_TGL_ADDR expected (%b)", resp, 2'b11);
        
    //test only read; forbbiden write
    pwr = 32'd123;
    write_to_addr_task(PWR_ADDR, 32'd0, resp);
    if (resp != 2'b11)
        $error("Bad resp(%b) during write_to_addr_task - PWR_ADDR expected (%b)", resp, 2'b11);   
    
    read_from_addr_task(PWR_ADDR, data, resp);
    if (resp != 2'b00)
        $error("Bad resp(%b) during read_from_addr_task - PWR_ADDR expected (%b)", resp, 2'b00);   
    if (data != pwr)
        $error("Bad threshold val(%d) during read_from_addr_task - PWR_ADDR expected (%d)", data, pwr);  
        
    //test read/write invalid addr
    write_to_addr_task(INVALID_ADDR, 32'd1234567, resp);
    if (resp != 2'b11)
        $error("Bad resp(%b) during write_to_addr_task - INVALID_ADDR expected (%b)", resp, 2'b11);   
    
    read_from_addr_task(INVALID_ADDR, data, resp);
    if (resp != 2'b11)
        $error("Bad resp(%b) during read_from_addr_task - INVALID_ADDR expected (%b)", resp, 2'b11);

    $display("tb_axi_lite_cfg: done");
    $finish;
end

endmodule