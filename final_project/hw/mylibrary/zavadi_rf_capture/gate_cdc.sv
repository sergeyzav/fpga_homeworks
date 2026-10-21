`timescale 1ns/100ps

module gate_cdc #(
    parameter SYNC_FF        = 4,
    parameter SIM_ASSERT_CHK = 0,
    parameter INIT_SYNC_FF   = 0
) (
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    input  logic [3:0]  cmd_tgl_axi,
    input  logic [31:0] threshold_axi,

    output logic [2:0]  state_axi,
    output logic [31:0] active_samples_axi,
    output logic [31:0] pwr_axi,

    input  logic        clk_div,
    input  logic        rst_div,

    output logic [3:0]  cmd_pulse_div,
    output logic [31:0] threshold_div,

    input  logic [2:0]  state_div,
    input  logic [31:0] active_samples_div,
    input  logic [31:0] pwr_div
);
    localparam DIV_TO_AXI_DATA_WIDTH = 3 + 32 + 32; // state (3) + active_samples (32) + pwr (32)
    localparam AXI_TO_DIV_DATA_WIDTH = 4 + 32; // cmd_tgl (4) + threshold (32)

    logic [AXI_TO_DIV_DATA_WIDTH-1:0] src_axi_data;
    logic [AXI_TO_DIV_DATA_WIDTH-1:0] dest_div_data;
    logic src_axi_send;
    logic src_axi_rcv;
    logic dest_div_req;

    logic [DIV_TO_AXI_DATA_WIDTH-1:0] src_div_data;
    logic [DIV_TO_AXI_DATA_WIDTH-1:0] dest_axi_data;
    logic src_div_send;
    logic src_div_rcv;
    logic dest_axi_req;

    logic [3:0] cmd_tgl_div = '0;

    // xpm_cdc_handshake: Bus Synchronizer with Full Handshake
    xpm_cdc_handshake #(
    .DEST_EXT_HSK   (0),   // 0 = внутрішній handshake (dest_req = імпульс 1 такт), 1 = зовнішній (dest_ack)
    .DEST_SYNC_FF   (SYNC_FF),   
    .INIT_SYNC_FF   (INIT_SYNC_FF),
    .SIM_ASSERT_CHK (SIM_ASSERT_CHK),
    .SRC_SYNC_FF    (SYNC_FF),   
    .WIDTH          (AXI_TO_DIV_DATA_WIDTH)
    ) axi_to_div_cdc (
    // домен джерела
    .src_clk  (s_axi_aclk),
    .src_in   (src_axi_data),    // [WIDTH-1:0], тримати стабільним, поки src_send=1
    .src_send (src_axi_send),    // запит на передачу
    .src_rcv  (src_axi_rcv),     // підтвердження, що dest прийняв дані

    // домен приймача
    .dest_clk (clk_div),
    .dest_out (dest_div_data),   // [WIDTH-1:0], валідні, коли dest_req=1
    .dest_req (dest_div_req),    // нові дані доступні
    .dest_ack (1'b0)
    );

    always_ff @(posedge s_axi_aclk) begin  
        if (!s_axi_aresetn) begin
            src_axi_send <= 1'b0;
        end else if (src_axi_rcv) begin
            src_axi_send <= 1'b0;
        end else if (!src_axi_send) begin
            src_axi_data <= {cmd_tgl_axi, threshold_axi};
            src_axi_send <= 1'b1;
        end
    end

    always_ff @(posedge clk_div) begin  
        if (dest_div_req) begin
            cmd_tgl_div <= dest_div_data[AXI_TO_DIV_DATA_WIDTH-1:AXI_TO_DIV_DATA_WIDTH-4];
            threshold_div <= dest_div_data[AXI_TO_DIV_DATA_WIDTH-5:0];
            cmd_pulse_div <= cmd_tgl_div ^ dest_div_data[AXI_TO_DIV_DATA_WIDTH-1:AXI_TO_DIV_DATA_WIDTH-4];
        end else 
            cmd_pulse_div <= 4'b0;
    end

    xpm_cdc_handshake #(
    .DEST_EXT_HSK   (0),   // 0 = внутрішній handshake (dest_req = імпульс 1 такт), 1 = зовнішній (dest_ack)
    .DEST_SYNC_FF   (SYNC_FF),   
    .INIT_SYNC_FF   (INIT_SYNC_FF),
    .SIM_ASSERT_CHK (SIM_ASSERT_CHK),
    .SRC_SYNC_FF    (SYNC_FF),   
    .WIDTH          (DIV_TO_AXI_DATA_WIDTH)
    ) div_to_axi_cdc (
    // домен джерела
    .src_clk  (clk_div),
    .src_in   (src_div_data),    // [WIDTH-1:0], тримати стабільним, поки src_send=1
    .src_send (src_div_send),    // запит на передачу
    .src_rcv  (src_div_rcv),     // підтвердження, що dest прийняв дані
    // домен приймача
    .dest_clk (s_axi_aclk),
    .dest_out (dest_axi_data),   // [WIDTH-1:0], валідні, коли dest_req=1
    .dest_req (dest_axi_req),    // нові дані доступні
    .dest_ack (1'b0)
    );

    always_ff @(posedge clk_div) begin  
        if (rst_div) begin
            src_div_send <= 1'b0;
        end else if (src_div_rcv) begin
            src_div_send <= 1'b0;
        end else if (!src_div_send) begin
            src_div_data <= {state_div, active_samples_div, pwr_div};
            src_div_send <= 1'b1;
        end
    end

    always_ff @(posedge s_axi_aclk) begin  
         if (dest_axi_req) begin
            state_axi <= dest_axi_data[DIV_TO_AXI_DATA_WIDTH-1:DIV_TO_AXI_DATA_WIDTH-3];
            active_samples_axi <= dest_axi_data[DIV_TO_AXI_DATA_WIDTH-4:DIV_TO_AXI_DATA_WIDTH-35];
            pwr_axi <= dest_axi_data[DIV_TO_AXI_DATA_WIDTH-36:0];
        end
    end

    

endmodule
