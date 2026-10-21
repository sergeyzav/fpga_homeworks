#include "rf_capture.h"

#include <xil_io.h>
#include <xiltimer.h>

#include "no_os_delay.h"
#include "parameters.h"

uint32_t rfc_now_ms(void)
{
	static XTime t0;
	static int started;
	XTime now;

	XTime_GetTime(&now);
	if (!started) {
		t0 = now;
		started = 1;
	}
	return (uint32_t)((now - t0) / ((COUNTS_PER_SECOND) / 1000u));
}

uint32_t rfc_read(uint32_t reg)
{
	return Xil_In32(RF_CAPTURE_BASEADDR + reg);
}

void rfc_write(uint32_t reg, uint32_t val)
{
	Xil_Out32(RF_CAPTURE_BASEADDR + reg, val);
}

const char *rfc_state_name(uint32_t state)
{
	switch (state) {
	case RFC_STATE_IDLE:    return "IDLE";
	case RFC_STATE_SCAN:    return "SCAN";
	case RFC_STATE_CAPTURE: return "CAPTURE";
	case RFC_STATE_PENDING: return "PENDING";
	case RFC_STATE_REPLAY:  return "REPLAY";
	default:                return "???";
	}
}

uint32_t rfc_state(void)
{
	return rfc_read(RFC_REG_STATE);
}

static const char *cmd_name(uint32_t cmd)
{
	switch (cmd) {
	case RFC_CMD_SCAN:         return "SCAN";
	case RFC_CMD_RESET:        return "RESET";
	case RFC_CMD_REPLAY_BEGIN: return "REPLAY_BEGIN";
	case RFC_CMD_REPLAY_END:   return "REPLAY_END";
	default:                   return "???";
	}
}

void rfc_cmd(uint32_t cmd)
{
	uint32_t before = rfc_state();

	rfc_write(RFC_REG_CMD, cmd);
	LOG("CMD", "%s (0x%lx), state before: %s",
	    cmd_name(cmd), (unsigned long)cmd, rfc_state_name(before));
}

int rfc_wait_state(uint32_t want, uint32_t timeout_ms)
{
	uint32_t t_start = rfc_now_ms();
	uint32_t last = rfc_state();

	while (last != want) {
		uint32_t now_state;

		if (rfc_now_ms() - t_start >= timeout_ms) {
			LOG("ERROR", "timeout %lu ms waiting for %s, state is %s",
			    (unsigned long)timeout_ms, rfc_state_name(want),
			    rfc_state_name(last));
			return -1;
		}
		no_os_udelay(10);
		now_state = rfc_state();
		if (now_state != last) {
			LOG("STATE", "%s -> %s", rfc_state_name(last),
			    rfc_state_name(now_state));
			last = now_state;
		}
	}
	LOG("STATE", "reached %s after %lu ms", rfc_state_name(want),
	    (unsigned long)(rfc_now_ms() - t_start));
	return 0;
}

void rfc_dump_regs(const char *why)
{
	uint32_t st = rfc_state();

	LOG("REGS", "%s: STATE=%lu(%s) THRESH=%lu CAPTURE=%lu ACTIVE=%lu PWR=%lu",
	    why, (unsigned long)st, rfc_state_name(st),
	    (unsigned long)rfc_read(RFC_REG_THRESH),
	    (unsigned long)rfc_read(RFC_REG_CAPTURE_SAMPLES),
	    (unsigned long)rfc_read(RFC_REG_ACTIVE_SAMPLES),
	    (unsigned long)rfc_read(RFC_REG_PWR));
}

void rfc_measure_noise(struct rfc_noise *n, uint32_t reads, uint32_t gap_us)
{
	uint64_t sum = 0;

	n->min = UINT32_MAX;
	n->max = 0;
	n->reads = reads;

	for (uint32_t i = 0; i < reads; i++) {
		uint32_t p = rfc_read(RFC_REG_PWR);

		sum += p;
		if (p < n->min)
			n->min = p;
		if (p > n->max)
			n->max = p;
		no_os_udelay(gap_us);
	}
	n->avg = (uint32_t)(sum / reads);

	LOG("NOISE", "%lu reads, %lu us apart: avg=%lu min=%lu max=%lu",
	    (unsigned long)reads, (unsigned long)gap_us,
	    (unsigned long)n->avg, (unsigned long)n->min, (unsigned long)n->max);
}

int rfc_probe(void)
{
	uint32_t st;

	LOG("PROBE", "zavadi_rf_capture at 0x%08lx",
	    (unsigned long)RF_CAPTURE_BASEADDR);
	rfc_dump_regs("after power-up");

	st = rfc_state();
	if (st > RFC_STATE_REPLAY) {
		LOG("ERROR", "STATE=%lu is not a valid state: wrong base address or no bitstream?",
		    (unsigned long)st);
		return -1;
	}

	if (st != RFC_STATE_IDLE) {
		LOG("PROBE", "IP is not in IDLE, sending RESET");
		rfc_cmd(RFC_CMD_RESET);
		if (rfc_wait_state(RFC_STATE_IDLE, 10) < 0)
			return -1;
	}

	if (rfc_read(RFC_REG_CAPTURE_SAMPLES) == 0) {
		LOG("ERROR", "CAPTURE_SAMPLES reads 0");
		return -1;
	}
	return 0;
}
