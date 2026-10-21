`timescale 1ns/100ps

module capture_fsm (
    input  logic        data_clk,
    input  logic        data_rst,

    input  logic        data_en,

    input  logic        cmd_scan,
    input  logic        cmd_reset,
    input  logic        cmd_replay_begin,
    input  logic        cmd_replay_end,

    input  logic        hit,
    input  logic        capture_done,
    input  logic        dma_ready,

    output logic [2:0]  state,
    output logic        detector_en,
    output logic        start,
    output logic        capture_en
);

    typedef enum logic [2:0] {
        IDLE    = 3'd0,
        SCAN    = 3'd1,
        CAPTURE = 3'd2,
        PENDING = 3'd3,
        REPLAY  = 3'd4
    } state_t;

    state_t current_state, next_state;

    assign state = current_state;
    assign detector_en = current_state == SCAN || current_state == CAPTURE;
    assign capture_en  = current_state == CAPTURE;
    assign start = current_state == SCAN && next_state == CAPTURE;

    always_comb begin
        next_state = current_state; //default;

        if (cmd_reset)
            next_state = IDLE;
        else begin 
            case (current_state)
                IDLE: begin
                    if (cmd_scan) 
                        next_state = SCAN;
                end
                SCAN: begin
                    if (hit && data_en && dma_ready) // починаємо запис тоді, коил є що писати, є куди писати і є детекшен сигналу
                        next_state = CAPTURE;
                end
                CAPTURE: begin
                    if (capture_done) 
                        next_state = PENDING;
                end
                PENDING: begin
                    if (cmd_replay_begin) 
                        next_state = REPLAY;
                     else if (cmd_scan) 
                        next_state = SCAN;
                end
                REPLAY: begin
                    if (cmd_replay_end) 
                        next_state = PENDING;
                end
                default:
                    next_state = IDLE;
            endcase
        end
    end

    always_ff @(posedge data_clk) begin
        if (data_rst)
            current_state <= IDLE;
         else 
            current_state <= next_state;
    end
endmodule
