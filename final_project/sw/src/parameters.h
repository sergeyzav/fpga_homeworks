/***************************************************************************//**
 *   @file   ad9361/src/parameters.h
 *   @brief  Parameters Definitions.
 *   @author DBogdan (dragos.bogdan@analog.com)
********************************************************************************
 * Copyright 2013(c) Analog Devices, Inc.
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *  - Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  - Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *  - Neither the name of Analog Devices, Inc. nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *  - The use of this software may or may not infringe the patent rights
 *    of one or more patent holders.  This license does not release you
 *    from the requirement that you obtain separate licenses from these
 *    patent holders to use this software.
 *  - Use of the software either in source or binary form, must be run
 *    on or directly connected to an Analog Devices Inc. component.
 *
 * THIS SOFTWARE IS PROVIDED BY ANALOG DEVICES "AS IS" AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, NON-INFRINGEMENT,
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL ANALOG DEVICES BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, INTELLECTUAL PROPERTY RIGHTS, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*******************************************************************************/
#ifndef __PARAMETERS_H__
#define __PARAMETERS_H__

#include <xparameters.h>

/*
 * Vitis SDT flow: PS drivers look up their config by base address,
 * so the "device id" fields hold base addresses.
 */
#define SPI_DEVICE_ID			XPAR_XSPIPS_0_BASEADDR	/* PS SPI0 (EMIO) */
#define SPI_CS				0
#define GPIO_DEVICE_ID			XPAR_XGPIOPS_0_BASEADDR

/* PS GPIO numbers: EMIO pin n = 54 + n (see system_top.v) */
#define GPIO_RESET_PIN			100	/* gpio_o[46] -> gpio_resetb */

/* axi_ad9361: RX core at the base, TX core at +0x4000 */
#define RX_CORE_BASEADDR		XPAR_AXI_AD9361_0_BASEADDR
#define TX_CORE_BASEADDR		(XPAR_AXI_AD9361_0_BASEADDR + 0x4000)

#define CF_AD9361_RX_DMA_BASEADDR	XPAR_AXI_AD9361_ADC_DMA_BASEADDR
#define CF_AD9361_TX_DMA_BASEADDR	XPAR_AXI_AD9361_DAC_DMA_BASEADDR

/* zavadi_rf_capture (address from the block design) */
#ifdef XPAR_ZAVADI_RF_CAPTURE_0_BASEADDR
#define RF_CAPTURE_BASEADDR		XPAR_ZAVADI_RF_CAPTURE_0_BASEADDR
#else
#warning "XPAR_ZAVADI_RF_CAPTURE_0_BASEADDR not in xparameters.h, using 0x43C00000"
#define RF_CAPTURE_BASEADDR		0x43C00000
#endif

/* 1R1T mode: RX1 and TX1 only, I + Q per channel */
#define ADC_CHANNELS			2
#define DAC_CHANNELS			2

/* ---- radio: C074 remote, 433.92 MHz OOK (research/remote_c074.md) ---- */

/* LO 300 kHz below the remote, so the signal sits away from DC and the LO
 * leakage (same as the PlutoSDR captures). RX and TX share the LO, so the
 * replay lands on the same RF frequency. */
#define RF_SIGNAL_HZ			433920000ULL
#define RF_LO_OFFSET_HZ			300000ULL
#define RF_LO_HZ			(RF_SIGNAL_HZ - RF_LO_OFFSET_HZ)
#define RF_SAMPLE_RATE_HZ		2500000	/* >= 2.08 MS/s: no FIR needed */
#define RF_BW_HZ			1500000

/* TX power: 0 = max. Keep it low for 433 MHz ISM (<= 10 mW EIRP) */
#define TX_ATTEN_MDB			20000	/* 20 dB */

/* ---- capture / replay settings ---- */

/* Buffer for one capture. Must hold CAPTURE_SAMPLES words of the IP */
#define CAPTURE_BUFFER_WORDS		625000	/* 64-bit words, 5 MB */

/* THRESH = noise average * THRESH_FACTOR (8 = +9 dB) */
#define THRESH_FACTOR			8
#define THRESH_MIN			2000	/* above the ~434.3 MHz interferer (PWR 200-450) */
#define NOISE_READS			1000
#define NOISE_GAP_US			100

/* RX gain: manual, so the noise floor stays put (AGC would move it) */
#define RX_GAIN_MANUAL			1
#define RX_GAIN_DB			20	/* PlutoSDR captures used 20 dB */

#define SCAN_TIMEOUT_MS			60000	/* re-arm if nothing came */
#define SCAN_HEARTBEAT_MS		2000	/* PWR log while scanning */
#define REPLAY_TIME_MS			5000	/* how long to replay one capture */
#define NUM_CAPTURES			0	/* 0 = forever */
#define DUMP_SAMPLES			8	/* first samples printed per capture */

#endif // __PARAMETERS_H__
