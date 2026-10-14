#ifndef MOVING_MAX_H
#define MOVING_MAX_H

#define N_SAMPLES 64   /* скільки відліків обробляє один виклик */
#define WINDOW    8    /* розмір вікна: скільки останніх відліків враховуємо */

void moving_max(int in_data[N_SAMPLES], int out_data[N_SAMPLES]);

#endif