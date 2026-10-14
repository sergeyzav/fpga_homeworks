#include <climits>
#include "moving_max.h"

void moving_max(int in_data[N_SAMPLES], int out_data[N_SAMPLES]) {
    int window[WINDOW];     

INIT_LOOP:
    for (int k = 0; k < WINDOW; k++) {
        window[k] = INT_MIN;                         
    }

MAIN_LOOP:
    for (int n = 0; n < N_SAMPLES; n++) {
#pragma HLS PIPELINE II=1

    SHIFT_LOOP:
        for (int k = WINDOW - 1; k > 0; k--) {       
            window[k] = window[k - 1];
        }

        window[0] = in_data[n];                      

        int max_val = window[0];                     
    MAX_LOOP:
        for (int k = 1; k < WINDOW; k++) {
            if (window[k] > max_val) {
                max_val = window[k];
            }
        }
        out_data[n] = max_val;
    }
}