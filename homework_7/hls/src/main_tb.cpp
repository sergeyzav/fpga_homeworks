#include <stdio.h>
#include <limits.h>
#include "moving_max.h"

#define N_TESTS 5

void moving_max_ref(int in_data[N_SAMPLES], int out_data[N_SAMPLES]) {
    for (int n = 0; n < N_SAMPLES; n++) {
        int m = in_data[n];
        for (int i = n - 1; i >= 0 && n - i < WINDOW; i--) {
            if (in_data[i] > m) m = in_data[i];
        }
        out_data[n] = m;
    }
}

int test(int t_key, int in_data[N_SAMPLES]) {
    int errors = 0;
    int out_data[N_SAMPLES], golden[N_SAMPLES];

    moving_max_ref(in_data, golden);
    moving_max(in_data, out_data);

    for (int n = 0; n < N_SAMPLES; n++) {
        if (out_data[n] != golden[n]) {
            printf("MISMATCH: виклик %d, відлік %d: DUT=%d, еталон=%d\n",
                   t_key, n, out_data[n], golden[n]);
            errors++;
        }
    }
    return errors;
}

int main(void) {
    int errors = 0;
    int test_cases[N_TESTS][N_SAMPLES];
    unsigned int seed = 12345;

    for (int n = 0; n < N_SAMPLES; n++) {
        test_cases[0][n] = 1;                              /* усі одиниці     */
        test_cases[1][n] = n + 1;                          /* 1, 2, ..., 64   */
        test_cases[2][n] = N_SAMPLES - n;                  /* 64, 63, ..., 1  */
        test_cases[3][n] = (n % 2 == 0) ? -64 : 64;        /* -64, 64, ...    */

        seed = seed * 1103515245u + 12345u;                /* псевдовипадкові */
        test_cases[4][n] = (int)((seed >> 16) % 201) - 100;   /* -100..100 */
    }

    for (int t = 0; t < N_TESTS; t++) {
        errors += test(t + 1, test_cases[t]);
    }

    if (errors == 0) {
        printf("Test passed !\n");
        return 0;
    }
    printf("Test FAILED: %d помилок\n", errors);
    return 1;
}