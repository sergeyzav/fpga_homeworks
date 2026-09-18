module system_top(
//系统输入时钟
    input               i_clk,
//AD936X SPI配置
    output              o_spi_clk,
    output              o_spi_csn,
    input               i_spi_miso,
    output              o_spi_mosi,
//AD936X 状态控制引脚
    output              en_agc,
    output reg          enable,
    output reg          txnrx,
    output              chip_rst_n,
    output              sync_in,
    output      [3:0]   ctrl_in,
//AD936X 接收通道数据引脚
    input               rx_clk_in_p,
    input               rx_clk_in_n,
    input       [5:0]   rx_data_in_n,
    input       [5:0]   rx_data_in_p,
    input               rx_frame_in_n,
    input               rx_frame_in_p,
//AD936X 发射通道数据引脚
    output              tx_clk_out_n,
    output              tx_clk_out_p,
    output      [5:0]   tx_data_out_n,
    output      [5:0]   tx_data_out_p,
    output              tx_frame_out_n,
    output              tx_frame_out_p
);

/*****全局时钟与复位*****/
wire                    clk_100M    ;
wire                    pll_locked  ;
wire                    sys_rst     ;
clk_wiz_0 clk_wiz_0_u
(
    .clk_in1            (i_clk      ),
    .clk_out1           (clk_100M   ),  //100mhz
    .locked             (pll_locked )
);

assign  sys_rst = ~ pll_locked      ;

/*****产生分频时钟与复位*****/
wire                    spi_clk     ;
wire                    spi_rst     ;

CLK_DIV_module#(
    .P_CLK_DIV_CNT     (4           )     
)
CLK_DIV_module_U0
(
    .i_clk              (clk_100M   ),  
    .i_rst              (sys_rst    ),  
    .o_clk_div          (spi_clk    )   
);

rst_gen_module#
(
    .P_RST_CYCLE        (10         )   
)
rst_gen_module_U0
(
    .i_clk              (spi_clk    ),
    .o_rst              (spi_rst    )    
);

/*****AD936X 初始化*****/

//赋值936X接口
assign en_agc = 'd0;        
assign sync_in = 1'b1;
assign ctrl_in = 4'b0000;
wire   ad9361_config_init_done;    //初始化完成信号，高电平完成

AD936X_Init AD936X_Init_U0(
    .i_clk              (spi_clk                ),
    .i_rst              (spi_rst                ),
    .chip_rst_n         (chip_rst_n             ),
    .init_done          (ad9361_config_init_done),
    .o_spi_clk          (o_spi_clk              ),
    .o_spi_cs           (o_spi_csn              ),
    .o_spi_mosi         (o_spi_mosi             ),
    .i_spi_miso         (i_spi_miso             )
);
always @ (posedge spi_clk or posedge spi_rst)begin
    if (spi_rst) begin
        enable <= 1'b0;
        txnrx <= 1'b0;  
    end
    else begin  
        if (ad9361_config_init_done == 1'b1) begin
                enable <= 1'b0;
                txnrx <= 1'b1; 
        end  
    end
end

/*****AD936X驱动接口*****/

//采样时钟
wire             sample_clk;  
//信号接口
wire [11:0]      rx0_i_data;
wire [11:0]      rx0_q_data;
wire [11:0]      rx1_i_data;
wire [11:0]      rx1_q_data;
wire  [11:0]     tx0_i_data;
wire  [11:0]     tx0_q_data;
wire  [11:0]     tx1_i_data;
wire  [11:0]     tx1_q_data;

DDS #
(
    .CLK_Freq(32'd56_000_000),
    .Out_Freq_mHz(64'd1_000_000_000),
    .Pword(0)
)
DDS_tx0_i(
    .clk        (sample_clk),
    .reset_n    (1),
    .sine_out   (tx0_q_data)
);

DDS #
(
    .CLK_Freq(32'd56_000_000),
    .Out_Freq_mHz(64'd1_000_000_000),
    .Pword(1024)
)
DDS_tx0_q(
    .clk        (sample_clk),
    .reset_n    (1),
    .sine_out   (tx0_i_data)
);


DDS #
(
    .CLK_Freq(32'd56_000_000),
    .Out_Freq_mHz(64'd2_000_000_000),
    .Pword(0)
)
DDS_tx1_i(
    .clk        (sample_clk),
    .reset_n    (1),
    .sine_out   (tx1_q_data)
);

DDS #
(
    .CLK_Freq(32'd56_000_000),
    .Out_Freq_mHz(64'd2_000_000_000),
    .Pword(1024)
)
DDS_tx1_q(
    .clk        (sample_clk),
    .reset_n    (1),
    .sine_out   (tx1_i_data)
);

ila_0 ila_U0 (
	.clk(sample_clk),        // input wire clk
	.probe0(rx0_i_data),     // input wire [11:0]  probe0  
	.probe1(rx0_q_data),     // input wire [11:0]  probe1 
	.probe2(rx1_i_data),     // input wire [11:0]  probe2 
	.probe3(rx1_q_data),     // input wire [11:0]  probe3
    .probe4(tx0_i_data),     // input wire [11:0]  probe0  
	.probe5(tx0_q_data),     // input wire [11:0]  probe1 
	.probe6(tx1_i_data),     // input wire [11:0]  probe2 
	.probe7(tx1_q_data)      // input wire [11:0]  probe3
);

data_process data_process_U0(
//接收数据通道
    .rx_clk_in_p                (rx_clk_in_p   ),
    .rx_clk_in_n                (rx_clk_in_n   ),
    .rx_frame_in_p              (rx_frame_in_p ),   
    .rx_frame_in_n              (rx_frame_in_n ),
    .rx_data_in_p               (rx_data_in_p  ),
    .rx_data_in_n               (rx_data_in_n  ),
//发送数据通道
    .tx_clk_out_p               (tx_clk_out_p  ),
    .tx_clk_out_n               (tx_clk_out_n  ),
    .tx_frame_out_p             (tx_frame_out_p),
    .tx_frame_out_n             (tx_frame_out_n),
    .tx_data_out_p              (tx_data_out_p ),
    .tx_data_out_n              (tx_data_out_n ),
//复位信号
    .reset                      (~ad9361_config_init_done),
    .sample_clk                 (sample_clk),
//接收数据信号
    .rx0_i_data                 (rx0_i_data ),
    .rx0_q_data                 (rx0_q_data ),
    .rx1_i_data                 (rx1_i_data ),
    .rx1_q_data                 (rx1_q_data ),
     
    .tx0_i_data                 (tx0_i_data),
    .tx0_q_data                 (tx0_q_data),
    .tx1_i_data                 (tx1_i_data),
    .tx1_q_data                 (tx1_q_data)
    );

endmodule
