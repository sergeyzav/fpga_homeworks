`timescale 1ns / 1ps

module lock_controller (
     input logic clk,
     input logic rst,
     input logic [3:0] digit_in,
     output logic unlocked_led
    );

    localparam PASSKEY_1 = 4'd3;
    localparam PASSKEY_2 = 4'd5;
    localparam PASSKEY_3 = 4'd7;

    typedef enum logic[1:0] { 
        LOCKED,
        WAIT_D2,
        WAIT_D3,
        UNLOCKED
     } locker_state_t;

    locker_state_t current_state, next_state;


    always_ff @(posedge clk, posedge rst) begin
       if (rst) 
            current_state <= LOCKED;
        else 
            current_state <= next_state;
    end

    always_comb begin
       unlocked_led = current_state === UNLOCKED;
    end

    always_comb begin
       next_state = LOCKED;

       if (current_state === LOCKED && digit_in === PASSKEY_1)
            next_state = WAIT_D2;

       if (current_state === WAIT_D2 && digit_in === PASSKEY_2)
            next_state = WAIT_D3;

       if (current_state === WAIT_D3 && digit_in === PASSKEY_3)
            next_state = UNLOCKED;

       if (current_state === UNLOCKED)
            next_state = UNLOCKED;
    end


    
endmodule
