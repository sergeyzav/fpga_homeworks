`timescale 1ns/100ps

module axi_lite_cfg #(
  parameter int ADDR_WIDTH    = 12,
  parameter int CAPTURE_SAMPLES = 1_000_000
) (
  input  logic                    s_axi_aclk,
  input  logic                    s_axi_aresetn,

  input  logic                    s_axi_awvalid,
  input  logic [ADDR_WIDTH-1:0]   s_axi_awaddr,
  output logic                    s_axi_awready,

  input  logic                    s_axi_wvalid,
  input  logic [31:0]             s_axi_wdata,
  input  logic [3:0]              s_axi_wstrb,
  output logic                    s_axi_wready,

  output logic                    s_axi_bvalid,
  output logic [1:0]              s_axi_bresp,
  input  logic                    s_axi_bready,

  input  logic                    s_axi_arvalid,
  input  logic [ADDR_WIDTH-1:0]   s_axi_araddr,
  output logic                    s_axi_arready,

  output logic                    s_axi_rvalid,
  output logic [31:0]             s_axi_rdata,
  output logic [1:0]              s_axi_rresp,
  input  logic                    s_axi_rready,

  output logic [31:0] threshold,     
  output logic [3:0]  cmd_tgl,       
  input  logic [2:0]  state,        
  input  logic [31:0] active_samples,  
  input  logic [31:0] pwr        
);

  localparam logic [ADDR_WIDTH-1:0] CMD_TGL_ADDR      = 'h000; // wo
  localparam logic [ADDR_WIDTH-1:0] STATE_ADDR        = 'h004; // ro
  localparam logic [ADDR_WIDTH-1:0] THRESHOLD_ADDR    = 'h008; // rw
  localparam logic [ADDR_WIDTH-1:0] CAPTURE_SAMPLES_ADDR     = 'h00C; // ro
  localparam logic [ADDR_WIDTH-1:0] ACTIVE_SAMPLES_ADDR = 'h010; // ro
  localparam logic [ADDR_WIDTH-1:0] PWR_ADDR          = 'h014; // ro

  localparam logic [1:0] RESP_OK     = 2'b00;
  localparam logic [1:0] RESP_DECERR = 2'b11;
  localparam logic [31:0] MAX_THRESHOLD = 32'hFFFF_FFFF;

  logic [31:0] threshold_reg;
  assign threshold = threshold_reg;

  //read
  logic [31:0] rdata_d;
  logic [1:0]  rresp_d;

  always_comb begin
    rdata_d = '0;
    rresp_d = RESP_OK;
    case (s_axi_araddr)
      STATE_ADDR:        rdata_d = 32'(state);
      THRESHOLD_ADDR:    rdata_d = threshold_reg;
      ACTIVE_SAMPLES_ADDR: rdata_d = active_samples;
      CAPTURE_SAMPLES_ADDR: rdata_d = CAPTURE_SAMPLES;
      PWR_ADDR:          rdata_d = pwr;
      default:           rresp_d = RESP_DECERR;
    endcase
  end

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn)
      s_axi_arready <= 1'b0;
    else if (s_axi_arvalid && !s_axi_arready && !s_axi_rvalid)
      s_axi_arready <= 1'b1;
    else
      s_axi_arready <= 1'b0;
  end

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      s_axi_rvalid <= 1'b0;
      s_axi_rdata  <= '0;
      s_axi_rresp  <= RESP_OK;
    end else if (s_axi_arvalid && s_axi_arready && !s_axi_rvalid) begin   // AR handshake
      s_axi_rvalid <= 1'b1;
      s_axi_rdata  <= rdata_d;
      s_axi_rresp  <= rresp_d;
    end else if (s_axi_rvalid && s_axi_rready) begin     // R handshake
      s_axi_rvalid <= 1'b0;
    end
  end

  //write
  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin 
      s_axi_awready <= 1'b0;
      s_axi_wready  <= 1'b0;
    end else if (s_axi_awvalid && s_axi_wvalid && !s_axi_awready && !s_axi_wready && !s_axi_bvalid) begin
      s_axi_awready <= 1'b1;
      s_axi_wready  <= 1'b1;
    end else begin
      s_axi_awready <= 1'b0;
      s_axi_wready  <= 1'b0;
    end
  end

  always_ff @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      s_axi_bvalid  <= 1'b0;
      s_axi_bresp   <= RESP_OK;
      cmd_tgl       <= '0;
      threshold_reg <= MAX_THRESHOLD;
    end else if (s_axi_awready && s_axi_wready) begin 
      s_axi_bvalid <= 1'b1;
      s_axi_bresp  <= RESP_DECERR;
      if (s_axi_wstrb == 4'b1111) begin
        if (s_axi_awaddr == CMD_TGL_ADDR) begin
          cmd_tgl     <= cmd_tgl ^ s_axi_wdata[3:0]; 
          s_axi_bresp <= RESP_OK;
        end else if (s_axi_awaddr == THRESHOLD_ADDR) begin
          threshold_reg <= s_axi_wdata;
          s_axi_bresp   <= RESP_OK;
        end
      end
    end else if (s_axi_bvalid && s_axi_bready) begin 
      s_axi_bvalid <= 1'b0;
    end
  end

endmodule