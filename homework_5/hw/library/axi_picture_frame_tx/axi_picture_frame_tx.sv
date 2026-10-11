module axi_picture_frame_tx #(
   parameter PICTUTE_WIDTH = 320,
   parameter PICTURE_HEIGHT = 200, 
   parameter CDC_SYNC_STAGES = 3,             
   parameter FIFO_DEPTH = 2048,              
   parameter FIFO_MEMORY_TYPE = "auto",      
   parameter RELATED_CLOCKS = 0
) (
   input logic m_axi_aclk,
   input logic m_axi_aresetn, 
   // external 
   input logic aclk_external,
   input logic [7:0] data,
   input logic enabled,
   // m_axis
   output logic [31:0] m_axis_tdata,
   output logic m_axis_tvalid,
   input  logic m_axis_tready,
   output logic m_axis_tlast
);
   localparam WORDS_IN_PICTURE = PICTUTE_WIDTH * PICTURE_HEIGHT; // one pixel = 4 bytes

   logic [31:0] shift_data;
   logic [31:0] final_data;
   logic data_last;
   logic data_valid;

   logic [1:0] words_counter;
   logic [31:0] pixel_counter;
   logic s_axis_tready_int;
   logic push_new_word;

   assign push_new_word = enabled && s_axis_tready_int && (words_counter == 2'b11);

   always_ff @(posedge aclk_external, negedge m_axi_aresetn) begin 
      if (!m_axi_aresetn) begin
         shift_data    <= 32'b0;
         final_data    <= 32'b0;
         data_last     <= 1'b0;
         data_valid    <= 1'b0;
         words_counter <= 2'b0;
         pixel_counter <= 32'b0;
      end else begin 
         if (enabled && s_axis_tready_int) begin
            shift_data <= {shift_data[23:0], data[7:0]};
            words_counter <= words_counter + 1;
            
            if (words_counter == 2'b11) begin
               data_valid    <= 1'b1;
               final_data    <= {shift_data[23:0], data[7:0]};
               pixel_counter <= pixel_counter + 1;
               
               if (pixel_counter == WORDS_IN_PICTURE - 1) begin
                  pixel_counter <= 0;
                  data_last     <= 1'b1;
               end else begin
                  data_last     <= 1'b0;
               end
            end else begin
               data_valid    <= 1'b0;
               data_last     <= 1'b0;
            end
         end else begin
            data_valid    <= 1'b0; 
         end
      end
   end

   xpm_fifo_axis #(
      .CDC_SYNC_STAGES(CDC_SYNC_STAGES),            
      .CLOCKING_MODE("independent_clock"), 
      .FIFO_DEPTH(FIFO_DEPTH),              
      .FIFO_MEMORY_TYPE(FIFO_MEMORY_TYPE),      
      .RELATED_CLOCKS(RELATED_CLOCKS)            
   ) fifo_for_cdc (
      .s_aresetn(m_axi_aresetn), 
      .s_aclk(aclk_external),
      .m_aclk(m_axi_aclk), 

      .s_axis_tvalid(data_valid), 
      .s_axis_tready(s_axis_tready_int), 
      .s_axis_tlast(data_last), 
      .s_axis_tdata(final_data),

      .s_axis_tstrb(4'b1111), 
      .s_axis_tkeep(4'b1111), 
      .s_axis_tid(1'b0), 
      .s_axis_tdest(1'b0), 
      .s_axis_tuser(1'b0), 

      .m_axis_tvalid(m_axis_tvalid),
      .m_axis_tready(m_axis_tready),
      .m_axis_tlast(m_axis_tlast), 
      .m_axis_tdata(m_axis_tdata),

      .m_axis_tstrb(),
      .m_axis_tkeep(),
      .m_axis_tid(), 
      .m_axis_tdest(), 
      .m_axis_tuser(), 

      .prog_full_axis(), 
      .almost_full_axis(),
      .wr_data_count_axis(), 
      .prog_empty_axis(), 
      .almost_empty_axis(),
      .rd_data_count_axis(), 
      .injectsbiterr_axis(1'b0), 
      .injectdbiterr_axis(1'b0), 
      .sbiterr_axis(),
      .dbiterr_axis() 
   );
endmodule