// axi_full_ram.v
// Простий AXI4 (Full) slave з пам'яттю, що інферується в Block RAM.
// Масив mem винесено в окремі always-блоки БЕЗ скидання (вимога BRAM).

module axi_full_ram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,
    parameter MEM_DEPTH  = 256
) (
    input  wire                        s_axi_aclk,
    input  wire                        s_axi_aresetn,

    input  wire [ADDR_WIDTH-1:0]       s_axi_awaddr,
    input  wire [7:0]                  s_axi_awlen,
    input  wire [2:0]                  s_axi_awsize,
    input  wire [1:0]                  s_axi_awburst,
    input  wire                        s_axi_awvalid,
    output wire                        s_axi_awready,

    input  wire [DATA_WIDTH-1:0]       s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]     s_axi_wstrb,
    input  wire                        s_axi_wlast,
    input  wire                        s_axi_wvalid,
    output wire                        s_axi_wready,

    output reg  [1:0]                  s_axi_bresp,
    output reg                         s_axi_bvalid,
    input  wire                        s_axi_bready,

    input  wire [ADDR_WIDTH-1:0]       s_axi_araddr,
    input  wire [7:0]                  s_axi_arlen,
    input  wire [2:0]                  s_axi_arsize,
    input  wire [1:0]                  s_axi_arburst,
    input  wire                        s_axi_arvalid,
    output wire                        s_axi_arready,

    output wire [DATA_WIDTH-1:0]       s_axi_rdata,
    output reg                         s_axi_rlast,
    output reg  [1:0]                  s_axi_rresp,
    output reg                         s_axi_rvalid,
    input  wire                        s_axi_rready
);

    localparam BYTES = DATA_WIDTH/8;
    localparam LSB   = $clog2(BYTES);        // 2 для 32 біт
    localparam AW    = $clog2(MEM_DEPTH);    // розрядність індексу слова

    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // ------------------------------------------------------------
    // Канал запису
    // ------------------------------------------------------------
    localparam WRIDLE = 2'd0, WRDATA = 2'd1, WRRESP = 2'd2;
    reg [1:0] wstate;
    reg [ADDR_WIDTH-1:0] waddr_cur;
    reg [7:0] wburst_cnt;

    assign s_axi_awready = (wstate == WRIDLE);
    assign s_axi_wready  = (wstate == WRDATA);

    wire wr_fire = s_axi_wvalid && s_axi_wready;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            wstate       <= WRIDLE;
            s_axi_bvalid <= 1'b0;
        end else case (wstate)
            WRIDLE: begin
                if (s_axi_awvalid) begin
                    waddr_cur  <= s_axi_awaddr;
                    wburst_cnt <= s_axi_awlen;
                    wstate     <= WRDATA;
                end
            end
            WRDATA: begin
                if (wr_fire) begin
                    waddr_cur <= waddr_cur + BYTES;
                    if (wburst_cnt == 0) begin
                        wstate <= WRRESP;
                    end else begin
                        wburst_cnt <= wburst_cnt - 1'b1;
                    end
                end
            end
            WRRESP: begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
                if (s_axi_bvalid && s_axi_bready) begin
                    s_axi_bvalid <= 1'b0;
                    wstate <= WRIDLE;
                end
            end
        endcase
    end

    // Порт запису BRAM: без скидання, з байтовими масками
    integer i;
    always @(posedge s_axi_aclk) begin
        if (wr_fire) begin
            for (i = 0; i < BYTES; i = i + 1)
                if (s_axi_wstrb[i])
                    mem[waddr_cur[LSB +: AW]][8*i +: 8] <= s_axi_wdata[8*i +: 8];
        end
    end

    // ------------------------------------------------------------
    // Канал читання
    // ------------------------------------------------------------
    localparam RDIDLE = 2'd0, RDDATA = 2'd1;
    reg [1:0] rstate;
    reg [ADDR_WIDTH-1:0] raddr_cur;
    reg [7:0] rburst_cnt;

    assign s_axi_arready = (rstate == RDIDLE);

    wire rd_en = (rstate == RDDATA) && (!s_axi_rvalid || s_axi_rready);

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            rstate       <= RDIDLE;
            s_axi_rvalid <= 1'b0;
        end else case (rstate)
            RDIDLE: begin
                s_axi_rvalid <= 1'b0;
                if (s_axi_arvalid) begin
                    raddr_cur  <= s_axi_araddr;
                    rburst_cnt <= s_axi_arlen;
                    rstate     <= RDDATA;
                end
            end
            RDDATA: begin
                if (rd_en) begin
                    s_axi_rresp  <= 2'b00;
                    s_axi_rvalid <= 1'b1;
                    s_axi_rlast  <= (rburst_cnt == 0);
                    if (rburst_cnt != 0) begin
                        raddr_cur  <= raddr_cur + BYTES;
                        rburst_cnt <= rburst_cnt - 1'b1;
                    end else if (s_axi_rvalid && s_axi_rready) begin
                        rstate <= RDIDLE;
                    end
                end
            end
        endcase
    end

    // Порт читання BRAM: синхронне читання, без скидання.
    // Регістр mem_rdata оновлюється в той самий такт, що й rvalid.
    reg [DATA_WIDTH-1:0] mem_rdata;
    always @(posedge s_axi_aclk) begin
        if (rd_en)
            mem_rdata <= mem[raddr_cur[LSB +: AW]];
    end
    assign s_axi_rdata = mem_rdata;

endmodule