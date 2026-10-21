/*
 * Driver for the zavadi_rf_capture IP (detect -> capture to DDR -> replay).
 *
 * Register map (AXI-lite, 32-bit):
 *   0x00 CMD             WO  each written 1-bit toggles one command
 *   0x04 STATE           RO  FSM state, see enum rfc_state
 *   0x08 THRESH          RW  power threshold, I^2 + Q^2 of one sample
 *   0x0C CAPTURE_SAMPLES RO  capture length, 64-bit words (2 samples each)
 *   0x10 ACTIVE_SAMPLES  RO  words that hold the signal, valid in PENDING
 *   0x14 PWR             RO  I^2 + Q^2 of the latest sample
 */
#ifndef RF_CAPTURE_H_
#define RF_CAPTURE_H_

#include <stdint.h>
#include <stdio.h>

#define RFC_REG_CMD             0x00
#define RFC_REG_STATE           0x04
#define RFC_REG_THRESH          0x08
#define RFC_REG_CAPTURE_SAMPLES 0x0C
#define RFC_REG_ACTIVE_SAMPLES  0x10
#define RFC_REG_PWR             0x14

#define RFC_CMD_SCAN            (1u << 0)
#define RFC_CMD_RESET           (1u << 1)
#define RFC_CMD_REPLAY_BEGIN    (1u << 2)
#define RFC_CMD_REPLAY_END      (1u << 3)

/* Bytes in one capture word: 2 samples x (I16 + Q16) */
#define RFC_BYTES_PER_WORD      8u

enum rfc_state {
	RFC_STATE_IDLE    = 0,
	RFC_STATE_SCAN    = 1,
	RFC_STATE_CAPTURE = 2,
	RFC_STATE_PENDING = 3,
	RFC_STATE_REPLAY  = 4,
};

struct rfc_noise {
	uint32_t avg;
	uint32_t min;
	uint32_t max;
	uint32_t reads;
};

/* Milliseconds since the first call, from the Cortex-A9 global timer */
uint32_t rfc_now_ms(void);

/* Every UART line starts with a timestamp and a tag */
#define LOG(tag, fmt, ...) \
	printf("[%8lu ms] %-7s " fmt "\r\n", (unsigned long)rfc_now_ms(), tag, ##__VA_ARGS__)

uint32_t rfc_read(uint32_t reg);
void rfc_write(uint32_t reg, uint32_t val);

const char *rfc_state_name(uint32_t state);
uint32_t rfc_state(void);

/* Writes one command (RFC_CMD_*) and logs it */
void rfc_cmd(uint32_t cmd);

/*
 * Polls STATE until it equals 'want'. Logs every state change on the way.
 * Returns 0 on success, -1 on timeout.
 */
int rfc_wait_state(uint32_t want, uint32_t timeout_ms);

/* Prints all registers in one line */
void rfc_dump_regs(const char *why);

/* Averages 'reads' PWR reads taken 'gap_us' apart */
void rfc_measure_noise(struct rfc_noise *n, uint32_t reads, uint32_t gap_us);

/*
 * Checks that the IP answers: dumps the registers and brings it to IDLE.
 * Returns 0 if the IP is in IDLE afterwards.
 */
int rfc_probe(void);

#endif
