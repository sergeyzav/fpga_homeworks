/***************************************************************************//**
 *   @file   ad9361/src/main.c
 *   @brief  Implementation of Main Function.
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

/*
 * AD9361 (FMCOMMS2) + zavadi_rf_capture on Zynq-7000, bare metal:
 *  - configures the AD9361 over PS SPI0 (1R1T),
 *  - measures the noise floor and sets the detector threshold,
 *  - loop: arm the RX DMA, SCAN, the IP captures a burst into DDR,
 *          replay the burst through the TX DMA (cyclic), back to SCAN.
 * Everything is logged over the UART.
 */

#include <inttypes.h>
#include <stdio.h>

#include <xil_cache.h>

#include "app_config.h"
#include "parameters.h"
#include "rf_capture.h"
#include "ad9361_api.h"
#include "axi_adc_core.h"
#include "axi_dac_core.h"
#include "axi_dmac.h"
#include "gpio_extra.h"
#include "no_os_delay.h"
#include "no_os_util.h"
#include "spi_extra.h"

/*
 * One capture, shared by RX and TX. Per sample one 32-bit word:
 * [15:0] = channel 0 (I), [31:16] = channel 1 (Q); two samples per IP word.
 * Aligned to the cache line for flush/invalidate.
 */
static uint32_t capture_buf[CAPTURE_BUFFER_WORDS * 2] __attribute__((aligned(32)));

static struct xil_spi_init_param xil_spi_param = {
	.type = SPI_PS,
	.flags = 0
};

static struct xil_gpio_init_param xil_gpio_param = {
	.type = GPIO_PS,
	.device_id = GPIO_DEVICE_ID
};

#define GPIO_OPS	&xil_gpio_ops
#define SPI_OPS		&xil_spi_ops
#define GPIO_PARAM	&xil_gpio_param
#define SPI_PARAM	&xil_spi_param

static struct axi_adc_init rx_adc_init = {
	"cf-ad9361-lpc",
	RX_CORE_BASEADDR,
	ADC_CHANNELS
};

static struct axi_dac_init tx_dac_init = {
	"cf-ad9361-dds-core-lpc",
	TX_CORE_BASEADDR,
	DAC_CHANNELS,
	NULL
};

static struct axi_dmac_init rx_dmac_init = {
	"rx_dmac",
	CF_AD9361_RX_DMA_BASEADDR,
	IRQ_DISABLED
};

static struct axi_dmac_init tx_dmac_init = {
	"tx_dmac",
	CF_AD9361_TX_DMA_BASEADDR,
	IRQ_DISABLED
};

static struct axi_dmac *rx_dmac;
static struct axi_dmac *tx_dmac;
static struct ad9361_rf_phy *ad9361_phy;

static AD9361_InitParam default_init_param = {
	/* Device selection */
	ID_AD9361,	// dev_sel
	/* Reference Clock */
	40000000UL,	//reference_clk_rate
	/* Base Configuration */
	0,		//two_rx_two_tx_mode_enable (1R1T: RX1 + TX1 only) *** adi,2rx-2tx-mode-enable
	1,		//one_rx_one_tx_mode_use_rx_num *** adi,1rx-1tx-mode-use-rx-num
	1,		//one_rx_one_tx_mode_use_tx_num *** adi,1rx-1tx-mode-use-tx-num
	1,		//frequency_division_duplex_mode_enable *** adi,frequency-division-duplex-mode-enable
	0,		//frequency_division_duplex_independent_mode_enable *** adi,frequency-division-duplex-independent-mode-enable
	0,		//tdd_use_dual_synth_mode_enable *** adi,tdd-use-dual-synth-mode-enable
	0,		//tdd_skip_vco_cal_enable *** adi,tdd-skip-vco-cal-enable
	0,		//tx_fastlock_delay_ns *** adi,tx-fastlock-delay-ns
	0,		//rx_fastlock_delay_ns *** adi,rx-fastlock-delay-ns
	0,		//rx_fastlock_pincontrol_enable *** adi,rx-fastlock-pincontrol-enable
	0,		//tx_fastlock_pincontrol_enable *** adi,tx-fastlock-pincontrol-enable
	0,		//external_rx_lo_enable *** adi,external-rx-lo-enable
	0,		//external_tx_lo_enable *** adi,external-tx-lo-enable
	5,		//dc_offset_tracking_update_event_mask *** adi,dc-offset-tracking-update-event-mask
	6,		//dc_offset_attenuation_high_range *** adi,dc-offset-attenuation-high-range
	5,		//dc_offset_attenuation_low_range *** adi,dc-offset-attenuation-low-range
	0x28,	//dc_offset_count_high_range *** adi,dc-offset-count-high-range
	0x32,	//dc_offset_count_low_range *** adi,dc-offset-count-low-range
	0,		//split_gain_table_mode_enable *** adi,split-gain-table-mode-enable
	MAX_SYNTH_FREF,	//trx_synthesizer_target_fref_overwrite_hz *** adi,trx-synthesizer-target-fref-overwrite-hz
	0,		// qec_tracking_slow_mode_enable *** adi,qec-tracking-slow-mode-enable
	/* ENSM Control */
	0,		//ensm_enable_pin_pulse_mode_enable *** adi,ensm-enable-pin-pulse-mode-enable
	0,		//ensm_enable_txnrx_control_enable *** adi,ensm-enable-txnrx-control-enable
	/* LO Control */
	RF_LO_HZ,	//rx_synthesizer_frequency_hz (see parameters.h) *** adi,rx-synthesizer-frequency-hz
	RF_LO_HZ,	//tx_synthesizer_frequency_hz (same LO: replay lands on the same RF) *** adi,tx-synthesizer-frequency-hz
	1,				//tx_lo_powerdown_managed_enable *** adi,tx-lo-powerdown-managed-enable
	/* Rate & BW Control */
	{960000000, 240000000, 120000000, 60000000, 30000000, 15000000},// rx_path_clock_frequencies[6] *** adi,rx-path-clock-frequencies
	{960000000, 240000000, 120000000, 60000000, 30000000, 15000000},// tx_path_clock_frequencies[6] *** adi,tx-path-clock-frequencies
	RF_BW_HZ,//rf_rx_bandwidth_hz *** adi,rf-rx-bandwidth-hz
	RF_BW_HZ,//rf_tx_bandwidth_hz *** adi,rf-tx-bandwidth-hz
	/* RF Port Control */
	0,		//rx_rf_port_input_select *** adi,rx-rf-port-input-select
	0,		//tx_rf_port_input_select *** adi,tx-rf-port-input-select
	/* TX Attenuation Control */
	TX_ATTEN_MDB,	//tx_attenuation_mdB *** adi,tx-attenuation-mdB
	0,		//update_tx_gain_in_alert_enable *** adi,update-tx-gain-in-alert-enable
	/* Reference Clock Control */
	0,		//xo_disable_use_ext_refclk_enable *** adi,xo-disable-use-ext-refclk-enable
	{8, 5920},	//dcxo_coarse_and_fine_tune[2] *** adi,dcxo-coarse-and-fine-tune
	CLKOUT_DISABLE,	//clk_output_mode_select *** adi,clk-output-mode-select
	/* Gain Control */
	2,		//gc_rx1_mode *** adi,gc-rx1-mode
	2,		//gc_rx2_mode *** adi,gc-rx2-mode
	58,		//gc_adc_large_overload_thresh *** adi,gc-adc-large-overload-thresh
	4,		//gc_adc_ovr_sample_size *** adi,gc-adc-ovr-sample-size
	47,		//gc_adc_small_overload_thresh *** adi,gc-adc-small-overload-thresh
	8192,	//gc_dec_pow_measurement_duration *** adi,gc-dec-pow-measurement-duration
	0,		//gc_dig_gain_enable *** adi,gc-dig-gain-enable
	800,	//gc_lmt_overload_high_thresh *** adi,gc-lmt-overload-high-thresh
	704,	//gc_lmt_overload_low_thresh *** adi,gc-lmt-overload-low-thresh
	24,		//gc_low_power_thresh *** adi,gc-low-power-thresh
	15,		//gc_max_dig_gain *** adi,gc-max-dig-gain
	0,		//gc_use_rx_fir_out_for_dec_pwr_meas_enable *** adi,gc-use-rx-fir-out-for-dec-pwr-meas-enable
	/* Gain MGC Control */
	2,		//mgc_dec_gain_step *** adi,mgc-dec-gain-step
	2,		//mgc_inc_gain_step *** adi,mgc-inc-gain-step
	0,		//mgc_rx1_ctrl_inp_enable *** adi,mgc-rx1-ctrl-inp-enable
	0,		//mgc_rx2_ctrl_inp_enable *** adi,mgc-rx2-ctrl-inp-enable
	0,		//mgc_split_table_ctrl_inp_gain_mode *** adi,mgc-split-table-ctrl-inp-gain-mode
	/* Gain AGC Control */
	10,		//agc_adc_large_overload_exceed_counter *** adi,agc-adc-large-overload-exceed-counter
	2,		//agc_adc_large_overload_inc_steps *** adi,agc-adc-large-overload-inc-steps
	0,		//agc_adc_lmt_small_overload_prevent_gain_inc_enable *** adi,agc-adc-lmt-small-overload-prevent-gain-inc-enable
	10,		//agc_adc_small_overload_exceed_counter *** adi,agc-adc-small-overload-exceed-counter
	4,		//agc_dig_gain_step_size *** adi,agc-dig-gain-step-size
	3,		//agc_dig_saturation_exceed_counter *** adi,agc-dig-saturation-exceed-counter
	1000,	// agc_gain_update_interval_us *** adi,agc-gain-update-interval-us
	0,		//agc_immed_gain_change_if_large_adc_overload_enable *** adi,agc-immed-gain-change-if-large-adc-overload-enable
	0,		//agc_immed_gain_change_if_large_lmt_overload_enable *** adi,agc-immed-gain-change-if-large-lmt-overload-enable
	10,		//agc_inner_thresh_high *** adi,agc-inner-thresh-high
	1,		//agc_inner_thresh_high_dec_steps *** adi,agc-inner-thresh-high-dec-steps
	12,		//agc_inner_thresh_low *** adi,agc-inner-thresh-low
	1,		//agc_inner_thresh_low_inc_steps *** adi,agc-inner-thresh-low-inc-steps
	10,		//agc_lmt_overload_large_exceed_counter *** adi,agc-lmt-overload-large-exceed-counter
	2,		//agc_lmt_overload_large_inc_steps *** adi,agc-lmt-overload-large-inc-steps
	10,		//agc_lmt_overload_small_exceed_counter *** adi,agc-lmt-overload-small-exceed-counter
	5,		//agc_outer_thresh_high *** adi,agc-outer-thresh-high
	2,		//agc_outer_thresh_high_dec_steps *** adi,agc-outer-thresh-high-dec-steps
	18,		//agc_outer_thresh_low *** adi,agc-outer-thresh-low
	2,		//agc_outer_thresh_low_inc_steps *** adi,agc-outer-thresh-low-inc-steps
	1,		//agc_attack_delay_extra_margin_us; *** adi,agc-attack-delay-extra-margin-us
	0,		//agc_sync_for_gain_counter_enable *** adi,agc-sync-for-gain-counter-enable
	/* Fast AGC */
	64,		//fagc_dec_pow_measuremnt_duration ***  adi,fagc-dec-pow-measurement-duration
	260,	//fagc_state_wait_time_ns ***  adi,fagc-state-wait-time-ns
	/* Fast AGC - Low Power */
	0,		//fagc_allow_agc_gain_increase ***  adi,fagc-allow-agc-gain-increase-enable
	5,		//fagc_lp_thresh_increment_time ***  adi,fagc-lp-thresh-increment-time
	1,		//fagc_lp_thresh_increment_steps ***  adi,fagc-lp-thresh-increment-steps
	/* Fast AGC - Lock Level (Lock Level is set via slow AGC inner high threshold) */
	1,		//fagc_lock_level_lmt_gain_increase_en ***  adi,fagc-lock-level-lmt-gain-increase-enable
	5,		//fagc_lock_level_gain_increase_upper_limit ***  adi,fagc-lock-level-gain-increase-upper-limit
	/* Fast AGC - Peak Detectors and Final Settling */
	1,		//fagc_lpf_final_settling_steps ***  adi,fagc-lpf-final-settling-steps
	1,		//fagc_lmt_final_settling_steps ***  adi,fagc-lmt-final-settling-steps
	3,		//fagc_final_overrange_count ***  adi,fagc-final-overrange-count
	/* Fast AGC - Final Power Test */
	0,		//fagc_gain_increase_after_gain_lock_en ***  adi,fagc-gain-increase-after-gain-lock-enable
	/* Fast AGC - Unlocking the Gain */
	0,		//fagc_gain_index_type_after_exit_rx_mode ***  adi,fagc-gain-index-type-after-exit-rx-mode
	1,		//fagc_use_last_lock_level_for_set_gain_en ***  adi,fagc-use-last-lock-level-for-set-gain-enable
	1,		//fagc_rst_gla_stronger_sig_thresh_exceeded_en ***  adi,fagc-rst-gla-stronger-sig-thresh-exceeded-enable
	5,		//fagc_optimized_gain_offset ***  adi,fagc-optimized-gain-offset
	10,		//fagc_rst_gla_stronger_sig_thresh_above_ll ***  adi,fagc-rst-gla-stronger-sig-thresh-above-ll
	1,		//fagc_rst_gla_engergy_lost_sig_thresh_exceeded_en ***  adi,fagc-rst-gla-engergy-lost-sig-thresh-exceeded-enable
	1,		//fagc_rst_gla_engergy_lost_goto_optim_gain_en ***  adi,fagc-rst-gla-engergy-lost-goto-optim-gain-enable
	10,		//fagc_rst_gla_engergy_lost_sig_thresh_below_ll ***  adi,fagc-rst-gla-engergy-lost-sig-thresh-below-ll
	8,		//fagc_energy_lost_stronger_sig_gain_lock_exit_cnt ***  adi,fagc-energy-lost-stronger-sig-gain-lock-exit-cnt
	1,		//fagc_rst_gla_large_adc_overload_en ***  adi,fagc-rst-gla-large-adc-overload-enable
	1,		//fagc_rst_gla_large_lmt_overload_en ***  adi,fagc-rst-gla-large-lmt-overload-enable
	0,		//fagc_rst_gla_en_agc_pulled_high_en ***  adi,fagc-rst-gla-en-agc-pulled-high-enable
	0,		//fagc_rst_gla_if_en_agc_pulled_high_mode ***  adi,fagc-rst-gla-if-en-agc-pulled-high-mode
	64,		//fagc_power_measurement_duration_in_state5 ***  adi,fagc-power-measurement-duration-in-state5
	2,		//fagc_large_overload_inc_steps *** adi,fagc-adc-large-overload-inc-steps
	/* RSSI Control */
	1,		//rssi_delay *** adi,rssi-delay
	1000,	//rssi_duration *** adi,rssi-duration
	3,		//rssi_restart_mode *** adi,rssi-restart-mode
	0,		//rssi_unit_is_rx_samples_enable *** adi,rssi-unit-is-rx-samples-enable
	1,		//rssi_wait *** adi,rssi-wait
	/* Aux ADC Control */
	256,	//aux_adc_decimation *** adi,aux-adc-decimation
	40000000UL,	//aux_adc_rate *** adi,aux-adc-rate
	/* AuxDAC Control */
	1,		//aux_dac_manual_mode_enable ***  adi,aux-dac-manual-mode-enable
	0,		//aux_dac1_default_value_mV ***  adi,aux-dac1-default-value-mV
	0,		//aux_dac1_active_in_rx_enable ***  adi,aux-dac1-active-in-rx-enable
	0,		//aux_dac1_active_in_tx_enable ***  adi,aux-dac1-active-in-tx-enable
	0,		//aux_dac1_active_in_alert_enable ***  adi,aux-dac1-active-in-alert-enable
	0,		//aux_dac1_rx_delay_us ***  adi,aux-dac1-rx-delay-us
	0,		//aux_dac1_tx_delay_us ***  adi,aux-dac1-tx-delay-us
	0,		//aux_dac2_default_value_mV ***  adi,aux-dac2-default-value-mV
	0,		//aux_dac2_active_in_rx_enable ***  adi,aux-dac2-active-in-rx-enable
	0,		//aux_dac2_active_in_tx_enable ***  adi,aux-dac2-active-in-tx-enable
	0,		//aux_dac2_active_in_alert_enable ***  adi,aux-dac2-active-in-alert-enable
	0,		//aux_dac2_rx_delay_us ***  adi,aux-dac2-rx-delay-us
	0,		//aux_dac2_tx_delay_us ***  adi,aux-dac2-tx-delay-us
	/* Temperature Sensor Control */
	256,	//temp_sense_decimation *** adi,temp-sense-decimation
	1000,	//temp_sense_measurement_interval_ms *** adi,temp-sense-measurement-interval-ms
	0xCE,	//temp_sense_offset_signed *** adi,temp-sense-offset-signed
	1,		//temp_sense_periodic_measurement_enable *** adi,temp-sense-periodic-measurement-enable
	/* Control Out Setup */
	0xFF,	//ctrl_outs_enable_mask *** adi,ctrl-outs-enable-mask
	0,		//ctrl_outs_index *** adi,ctrl-outs-index
	/* External LNA Control */
	0,		//elna_settling_delay_ns *** adi,elna-settling-delay-ns
	0,		//elna_gain_mdB *** adi,elna-gain-mdB
	0,		//elna_bypass_loss_mdB *** adi,elna-bypass-loss-mdB
	0,		//elna_rx1_gpo0_control_enable *** adi,elna-rx1-gpo0-control-enable
	0,		//elna_rx2_gpo1_control_enable *** adi,elna-rx2-gpo1-control-enable
	0,		//elna_gaintable_all_index_enable *** adi,elna-gaintable-all-index-enable
	/* Digital Interface Control */
	0,		//digital_interface_tune_skip_mode *** adi,digital-interface-tune-skip-mode
	0,		//digital_interface_tune_fir_disable *** adi,digital-interface-tune-fir-disable
	1,		//pp_tx_swap_enable *** adi,pp-tx-swap-enable
	1,		//pp_rx_swap_enable *** adi,pp-rx-swap-enable
	0,		//tx_channel_swap_enable *** adi,tx-channel-swap-enable
	0,		//rx_channel_swap_enable *** adi,rx-channel-swap-enable
	1,		//rx_frame_pulse_mode_enable *** adi,rx-frame-pulse-mode-enable
	0,		//two_t_two_r_timing_enable *** adi,2t2r-timing-enable
	0,		//invert_data_bus_enable *** adi,invert-data-bus-enable
	0,		//invert_data_clk_enable *** adi,invert-data-clk-enable
	0,		//fdd_alt_word_order_enable *** adi,fdd-alt-word-order-enable
	0,		//invert_rx_frame_enable *** adi,invert-rx-frame-enable
	0,		//fdd_rx_rate_2tx_enable *** adi,fdd-rx-rate-2tx-enable
	0,		//swap_ports_enable *** adi,swap-ports-enable
	0,		//single_data_rate_enable *** adi,single-data-rate-enable
	1,		//lvds_mode_enable *** adi,lvds-mode-enable
	0,		//half_duplex_mode_enable *** adi,half-duplex-mode-enable
	0,		//single_port_mode_enable *** adi,single-port-mode-enable
	0,		//full_port_enable *** adi,full-port-enable
	0,		//full_duplex_swap_bits_enable *** adi,full-duplex-swap-bits-enable
	0,		//delay_rx_data *** adi,delay-rx-data
	0,		//rx_data_clock_delay *** adi,rx-data-clock-delay
	4,		//rx_data_delay *** adi,rx-data-delay
	7,		//tx_fb_clock_delay *** adi,tx-fb-clock-delay
	0,		//tx_data_delay *** adi,tx-data-delay
	150,	//lvds_bias_mV *** adi,lvds-bias-mV
	1,		//lvds_rx_onchip_termination_enable *** adi,lvds-rx-onchip-termination-enable
	0,		//rx1rx2_phase_inversion_en *** adi,rx1-rx2-phase-inversion-enable
	0xFF,	//lvds_invert1_control *** adi,lvds-invert1-control
	0x0F,	//lvds_invert2_control *** adi,lvds-invert2-control
	/* GPO Control */
	0,		//gpo_manual_mode_enable *** adi,gpo-manual-mode-enable
	0,		//gpo_manual_mode_enable_mask *** adi,gpo-manual-mode-enable-mask
	0,		//gpo0_inactive_state_high_enable *** adi,gpo0-inactive-state-high-enable
	0,		//gpo1_inactive_state_high_enable *** adi,gpo1-inactive-state-high-enable
	0,		//gpo2_inactive_state_high_enable *** adi,gpo2-inactive-state-high-enable
	0,		//gpo3_inactive_state_high_enable *** adi,gpo3-inactive-state-high-enable
	0,		//gpo0_slave_rx_enable *** adi,gpo0-slave-rx-enable
	0,		//gpo0_slave_tx_enable *** adi,gpo0-slave-tx-enable
	0,		//gpo1_slave_rx_enable *** adi,gpo1-slave-rx-enable
	0,		//gpo1_slave_tx_enable *** adi,gpo1-slave-tx-enable
	0,		//gpo2_slave_rx_enable *** adi,gpo2-slave-rx-enable
	0,		//gpo2_slave_tx_enable *** adi,gpo2-slave-tx-enable
	0,		//gpo3_slave_rx_enable *** adi,gpo3-slave-rx-enable
	0,		//gpo3_slave_tx_enable *** adi,gpo3-slave-tx-enable
	0,		//gpo0_rx_delay_us *** adi,gpo0-rx-delay-us
	0,		//gpo0_tx_delay_us *** adi,gpo0-tx-delay-us
	0,		//gpo1_rx_delay_us *** adi,gpo1-rx-delay-us
	0,		//gpo1_tx_delay_us *** adi,gpo1-tx-delay-us
	0,		//gpo2_rx_delay_us *** adi,gpo2-rx-delay-us
	0,		//gpo2_tx_delay_us *** adi,gpo2-tx-delay-us
	0,		//gpo3_rx_delay_us *** adi,gpo3-rx-delay-us
	0,		//gpo3_tx_delay_us *** adi,gpo3-tx-delay-us
	/* Tx Monitor Control */
	37000,	//low_high_gain_threshold_mdB *** adi,txmon-low-high-thresh
	0,		//low_gain_dB *** adi,txmon-low-gain
	24,		//high_gain_dB *** adi,txmon-high-gain
	0,		//tx_mon_track_en *** adi,txmon-dc-tracking-enable
	0,		//one_shot_mode_en *** adi,txmon-one-shot-mode-enable
	511,	//tx_mon_delay *** adi,txmon-delay
	8192,	//tx_mon_duration *** adi,txmon-duration
	2,		//tx1_mon_front_end_gain *** adi,txmon-1-front-end-gain
	2,		//tx2_mon_front_end_gain *** adi,txmon-2-front-end-gain
	48,		//tx1_mon_lo_cm *** adi,txmon-1-lo-cm
	48,		//tx2_mon_lo_cm *** adi,txmon-2-lo-cm
	/* GPIO definitions */
	{
		.number = -1,
		.platform_ops = GPIO_OPS,
		.extra = GPIO_PARAM
	},		//gpio_resetb *** reset-gpios
	/* MCS Sync */
	{
		.number = -1,
		.platform_ops = GPIO_OPS,
		.extra = GPIO_PARAM
	},		//gpio_sync *** sync-gpios

	{
		.number = -1,
		.platform_ops = GPIO_OPS,
		.extra = GPIO_PARAM
	},		//gpio_cal_sw1 *** cal-sw1-gpios

	{
		.number = -1,
		.platform_ops = GPIO_OPS,
		.extra = GPIO_PARAM
	},		//gpio_cal_sw2 *** cal-sw2-gpios

	{
		.device_id = SPI_DEVICE_ID,
		.mode = NO_OS_SPI_MODE_1,
		.chip_select = SPI_CS,
		.platform_ops = SPI_OPS,
		.extra = SPI_PARAM
	},

	/* External LO clocks */
	NULL,	//(*ad9361_rfpll_ext_recalc_rate)()
	NULL,	//(*ad9361_rfpll_ext_round_rate)()
	NULL,	//(*ad9361_rfpll_ext_set_rate)()
	&rx_adc_init,	// *rx_adc_init
	&tx_dac_init,   // *tx_dac_init
};

static uint32_t sample_rate_hz;

/* ---------------------------------------------------------------------------
 * DMA helpers. IRQ_PENDING is write-1-to-clear; the no-OS wait function never
 * clears it, so a second transfer would look "done" at once without this.
 * ------------------------------------------------------------------------- */
static void dma_clear_irq(struct axi_dmac *dmac)
{
	axi_dmac_write(dmac, AXI_DMAC_REG_IRQ_PENDING,
		       AXI_DMAC_IRQ_SOT | AXI_DMAC_IRQ_EOT);
}

static int dma_wait_eot(struct axi_dmac *dmac, uint32_t timeout_ms)
{
	uint32_t t0 = rfc_now_ms();
	uint32_t reg = 0;

	do {
		axi_dmac_read(dmac, AXI_DMAC_REG_IRQ_PENDING, &reg);
		if (reg & AXI_DMAC_IRQ_EOT) {
			dma_clear_irq(dmac);
			return 0;
		}
	} while (rfc_now_ms() - t0 < timeout_ms);

	LOG("ERROR", "%s: no end of transfer after %lu ms (IRQ_PENDING=0x%lx)",
	    dmac->name, (unsigned long)timeout_ms, (unsigned long)reg);
	return -1;
}

/* Words (64-bit) -> microseconds of air time */
static uint32_t words_to_us(uint32_t words)
{
	if (!sample_rate_hz)
		return 0;
	return (uint32_t)(((uint64_t)words * 2u * 1000000u) / sample_rate_hz);
}

/* ---------------------------------------------------------------------------
 * Radio
 * ------------------------------------------------------------------------- */
static int32_t radio_setup(void)
{
	uint64_t lo_hz = 0;
	uint32_t bw_hz = 0;
	int32_t gain_db = 0;
	int32_t status;

	uint8_t rx_fir = 0, tx_fir = 0;

	/* The example FIRs are band-pass (3/20..1/4 fs) and would cut the remote
	 * out at 2.5 MS/s; keep them off. */
	ad9361_set_rx_fir_en_dis(ad9361_phy, 0);
	ad9361_set_tx_fir_en_dis(ad9361_phy, 0);
	ad9361_get_rx_fir_en_dis(ad9361_phy, &rx_fir);
	ad9361_get_tx_fir_en_dis(ad9361_phy, &tx_fir);
	LOG("RADIO", "FIR: RX %s, TX %s", rx_fir ? "on" : "off", tx_fir ? "on" : "off");

	/* Sets the RX and TX clock chains together */
	status = ad9361_set_rx_sampling_freq(ad9361_phy, RF_SAMPLE_RATE_HZ);
	if (status < 0) {
		LOG("ERROR", "set sample rate %d: %"PRIi32, RF_SAMPLE_RATE_HZ, status);
		return status;
	}
	ad9361_set_rx_rf_bandwidth(ad9361_phy, RF_BW_HZ);
	ad9361_set_tx_rf_bandwidth(ad9361_phy, RF_BW_HZ);
	LOG("RADIO", "target: remote %lu kHz, LO %lu kHz (offset -%lu kHz), %d S/s",
	    (unsigned long)(RF_SIGNAL_HZ / 1000), (unsigned long)(RF_LO_HZ / 1000),
	    (unsigned long)(RF_LO_OFFSET_HZ / 1000), RF_SAMPLE_RATE_HZ);

#if RX_GAIN_MANUAL
	status = ad9361_set_rx_gain_control_mode(ad9361_phy, 0, RF_GAIN_MGC);
	if (status < 0) {
		LOG("ERROR", "set RX gain mode MGC: %"PRIi32, status);
		return status;
	}
	status = ad9361_set_rx_rf_gain(ad9361_phy, 0, RX_GAIN_DB);
	if (status < 0) {
		LOG("ERROR", "set RX gain %d dB: %"PRIi32, RX_GAIN_DB, status);
		return status;
	}
	LOG("RADIO", "RX1 gain: manual, %d dB requested", RX_GAIN_DB);
#else
	LOG("RADIO", "RX1 gain: AGC (noise floor will move with the gain)");
#endif

	ad9361_get_rx_lo_freq(ad9361_phy, &lo_hz);
	ad9361_get_rx_sampling_freq(ad9361_phy, &sample_rate_hz);
	ad9361_get_rx_rf_bandwidth(ad9361_phy, &bw_hz);
	ad9361_get_rx_rf_gain(ad9361_phy, 0, &gain_db);
	LOG("RADIO", "RX LO=%lu kHz  fs=%lu Hz  BW=%lu Hz  gain=%ld dB",
	    (unsigned long)(lo_hz / 1000), (unsigned long)sample_rate_hz,
	    (unsigned long)bw_hz, (long)gain_db);
	return 0;
}

static int32_t tx_dac_setup(void)
{
	int32_t status;

	status = axi_dac_init(&ad9361_phy->tx_dac, &tx_dac_init);
	if (status < 0) {
		LOG("ERROR", "axi_dac_init: %"PRIi32, status);
		return status;
	}
	/* DAC plays only what the TX DMA sends; silent until the first replay */
	axi_dac_set_datasel(ad9361_phy->tx_dac, -1, AXI_DAC_DATA_SEL_DMA);
	LOG("TX", "DAC data source: DMA");
	return 0;
}

/* ---------------------------------------------------------------------------
 * Threshold
 * ------------------------------------------------------------------------- */
static uint32_t calibrate_threshold(void)
{
	struct rfc_noise n;
	uint64_t thr;

	LOG("CALIB", "measuring noise floor (keep the air quiet)");
	rfc_measure_noise(&n, NOISE_READS, NOISE_GAP_US);

	thr = (uint64_t)n.avg * THRESH_FACTOR;
	if (thr < THRESH_MIN)
		thr = THRESH_MIN;
	if (thr > UINT32_MAX)
		thr = UINT32_MAX;
	/* Single-sample noise power has a long tail: max ~7x avg over 1000 reads
	 * is normal, the detector also needs HIT_LEN samples in a row */
	LOG("CALIB", "noise max/avg = %lu", (unsigned long)(n.avg ? n.max / n.avg : 0));

	rfc_write(RFC_REG_THRESH, (uint32_t)thr);
	if (rfc_read(RFC_REG_THRESH) != (uint32_t)thr) {
		LOG("ERROR", "THRESH readback 0x%08lx != 0x%08lx",
		    (unsigned long)rfc_read(RFC_REG_THRESH), (unsigned long)thr);
	}
	LOG("CALIB", "THRESH = %lu (noise avg %lu x %d)",
	    (unsigned long)thr, (unsigned long)n.avg, THRESH_FACTOR);
	return (uint32_t)thr;
}

/* ---------------------------------------------------------------------------
 * One capture
 * ------------------------------------------------------------------------- */
static int32_t rx_arm(uint32_t words)
{
	struct axi_dma_transfer transfer = {
		.size = words * RFC_BYTES_PER_WORD,
		.transfer_done = 0,
		.cyclic = NO,
		.src_addr = 0,
		.dest_addr = (uintptr_t)capture_buf
	};
	int32_t status;

	/* Drop stale cache lines before the DMA writes the buffer */
	Xil_DCacheInvalidateRange((uintptr_t)capture_buf, transfer.size);
	dma_clear_irq(rx_dmac);

	status = axi_dmac_transfer_start(rx_dmac, &transfer);
	if (status < 0) {
		LOG("ERROR", "RX DMA start: %"PRIi32, status);
		return status;
	}
	LOG("RXDMA", "armed: %lu bytes -> 0x%08lx",
	    (unsigned long)transfer.size, (unsigned long)(uintptr_t)capture_buf);
	return 0;
}

/* Waits for SCAN -> CAPTURE -> PENDING. 1 = captured, 0 = timeout, <0 = error */
static int wait_for_capture(uint32_t thresh)
{
	uint32_t t0 = rfc_now_ms();
	uint32_t t_beat = t0;
	uint32_t t_trig = 0;
	uint32_t last = rfc_state();
	uint32_t pwr_peak = 0, pwr_above = 0, pwr_reads = 0;

	for (;;) {
		uint32_t st = rfc_state();
		uint32_t now = rfc_now_ms();
		uint32_t pwr = rfc_read(RFC_REG_PWR);

		/* OOK: one PWR read every 2 s often lands in a gap, so track the peak */
		pwr_reads++;
		if (pwr > pwr_peak)
			pwr_peak = pwr;
		if (pwr >= thresh)
			pwr_above++;

		if (st != last) {
			LOG("STATE", "%s -> %s", rfc_state_name(last), rfc_state_name(st));
			if (st == RFC_STATE_CAPTURE) {
				t_trig = now;
				LOG("TRIG", "signal detected after %lu ms of scanning",
				    (unsigned long)(now - t0));
			}
			last = st;
		}

		if (st == RFC_STATE_PENDING) {
			if (t_trig)
				LOG("CAPT", "capture took %lu ms (expected ~%lu ms)",
				    (unsigned long)(now - t_trig),
				    (unsigned long)(words_to_us(rfc_read(RFC_REG_CAPTURE_SAMPLES)) / 1000));
			return 1;
		}
		if (st == RFC_STATE_IDLE || st > RFC_STATE_REPLAY) {
			LOG("ERROR", "unexpected state %s while waiting for capture",
			    rfc_state_name(st));
			return -1;
		}
		if (st == RFC_STATE_SCAN && now - t0 >= SCAN_TIMEOUT_MS) {
			LOG("SCAN", "nothing above THRESH for %d ms", SCAN_TIMEOUT_MS);
			return 0;
		}
		if (now - t_beat >= SCAN_HEARTBEAT_MS) {
			LOG("SCAN", "state=%s PWR now=%lu peak=%lu (%lu x THRESH/100) above=%lu/%lu THRESH=%lu",
			    rfc_state_name(st), (unsigned long)pwr, (unsigned long)pwr_peak,
			    (unsigned long)((uint64_t)pwr_peak * 100 / (thresh ? thresh : 1)),
			    (unsigned long)pwr_above, (unsigned long)pwr_reads,
			    (unsigned long)thresh);
			t_beat = now;
			pwr_peak = pwr_above = pwr_reads = 0;
		}
		no_os_udelay(50);
	}
}

static void capture_report(uint32_t active)
{
	const uint32_t n = active * 2;	/* samples */
	int32_t peak_i = 0, peak_q = 0;
	uint64_t pwr_sum = 0;

	for (uint32_t k = 0; k < n; k++) {
		int32_t i = (int16_t)(capture_buf[k] & 0xFFFF);
		int32_t q = (int16_t)(capture_buf[k] >> 16);

		if (i < 0) i = -i;
		if (q < 0) q = -q;
		if (i > peak_i) peak_i = i;
		if (q > peak_q) peak_q = q;
		pwr_sum += (uint64_t)(i * i) + (uint64_t)(q * q);
	}

	LOG("CAPT", "ACTIVE=%lu words = %lu samples = %lu us",
	    (unsigned long)active, (unsigned long)n,
	    (unsigned long)words_to_us(active));
	LOG("CAPT", "peak |I|=%ld |Q|=%ld (12-bit full scale 2047), mean I^2+Q^2=%lu",
	    (long)peak_i, (long)peak_q,
	    (unsigned long)(n ? pwr_sum / n : 0));
	if (peak_i >= 2047 || peak_q >= 2047)
		LOG("WARN", "samples hit full scale: lower RX_GAIN_DB");

	for (uint32_t k = 0; k < DUMP_SAMPLES && k < n; k++)
		LOG("DATA", "s[%lu] I=%d Q=%d", (unsigned long)k,
		    (int)(int16_t)(capture_buf[k] & 0xFFFF),
		    (int)(int16_t)(capture_buf[k] >> 16));
}

/*
 * RX gives 12-bit samples sign-extended to 16 bits, the DAC takes the 12 MSBs
 * of a 16-bit word. Shift by 4 in place, otherwise the replay is 24 dB down.
 */
static void replay_prepare(uint32_t active)
{
	const uint32_t n = active * 2;

	for (uint32_t k = 0; k < n; k++) {
		uint16_t i = (uint16_t)(capture_buf[k] & 0xFFFF);
		uint16_t q = (uint16_t)(capture_buf[k] >> 16);

		capture_buf[k] = ((uint32_t)(uint16_t)(q << 4) << 16) | (uint16_t)(i << 4);
	}
	Xil_DCacheFlushRange((uintptr_t)capture_buf, active * RFC_BYTES_PER_WORD);
	LOG("REPLAY", "buffer scaled 12 -> 16 bit and flushed (%lu bytes)",
	    (unsigned long)(active * RFC_BYTES_PER_WORD));
}

static int32_t replay(uint32_t active)
{
	struct axi_dma_transfer transfer = {
		.size = active * RFC_BYTES_PER_WORD,
		.transfer_done = 0,
		.cyclic = CYCLIC,
		.src_addr = (uintptr_t)capture_buf,
		.dest_addr = 0
	};
	uint32_t t0;
	int32_t status;

	replay_prepare(active);

	dma_clear_irq(tx_dmac);
	status = axi_dmac_transfer_start(tx_dmac, &transfer);
	if (status < 0) {
		LOG("ERROR", "TX DMA start: %"PRIi32, status);
		return status;
	}
	LOG("TXDMA", "cyclic: %lu bytes from 0x%08lx (%lu us per loop)",
	    (unsigned long)transfer.size, (unsigned long)(uintptr_t)capture_buf,
	    (unsigned long)words_to_us(active));

	rfc_cmd(RFC_CMD_REPLAY_BEGIN);
	if (rfc_wait_state(RFC_STATE_REPLAY, 10) < 0) {
		axi_dmac_transfer_stop(tx_dmac);
		return -1;
	}

	t0 = rfc_now_ms();
	while (rfc_now_ms() - t0 < REPLAY_TIME_MS)
		no_os_mdelay(10);
	LOG("REPLAY", "played for %d ms", REPLAY_TIME_MS);

	axi_dmac_transfer_stop(tx_dmac);
	LOG("TXDMA", "stopped");

	rfc_cmd(RFC_CMD_REPLAY_END);
	return rfc_wait_state(RFC_STATE_PENDING, 10);
}

/* Brings the IP and the RX DMA back to a clean IDLE */
static void abort_capture(const char *why)
{
	LOG("ABORT", "%s", why);
	rfc_cmd(RFC_CMD_RESET);
	axi_dmac_transfer_stop(rx_dmac);
	dma_clear_irq(rx_dmac);
	rfc_wait_state(RFC_STATE_IDLE, 10);
	rfc_dump_regs("after abort");
}

static void capture_loop(uint32_t words)
{
	uint32_t thresh = calibrate_threshold();
	uint32_t ok = 0, timeouts = 0, errors = 0;

	for (uint32_t iter = 1; NUM_CAPTURES == 0 || iter <= NUM_CAPTURES; iter++) {
		uint32_t active;
		int r;

		LOG("LOOP", "==== capture #%lu (ok=%lu timeouts=%lu errors=%lu) ====",
		    (unsigned long)iter, (unsigned long)ok,
		    (unsigned long)timeouts, (unsigned long)errors);

		if (rx_arm(words) < 0) {
			errors++;
			abort_capture("RX DMA did not start");
			continue;
		}

		/* SCAN comes from IDLE (first pass, after abort) or from PENDING */
		rfc_cmd(RFC_CMD_SCAN);
		if (rfc_wait_state(RFC_STATE_SCAN, 10) < 0 &&
		    rfc_state() != RFC_STATE_CAPTURE &&
		    rfc_state() != RFC_STATE_PENDING) {
			errors++;
			abort_capture("IP did not enter SCAN");
			continue;
		}

		r = wait_for_capture(thresh);
		if (r == 0) {
			timeouts++;
			abort_capture("scan timeout, re-arming");
			thresh = calibrate_threshold();
			continue;
		}
		if (r < 0) {
			errors++;
			abort_capture("FSM error");
			continue;
		}

		if (dma_wait_eot(rx_dmac, 1000) < 0) {
			errors++;
			abort_capture("IP is in PENDING but the RX DMA did not finish");
			continue;
		}
		Xil_DCacheInvalidateRange((uintptr_t)capture_buf, words * RFC_BYTES_PER_WORD);
		LOG("RXDMA", "transfer done, cache invalidated");

		active = rfc_read(RFC_REG_ACTIVE_SAMPLES);
		if (active == 0 || active > words) {
			errors++;
			LOG("ERROR", "ACTIVE_SAMPLES=%lu out of range 1..%lu",
			    (unsigned long)active, (unsigned long)words);
			abort_capture("bad ACTIVE_SAMPLES");
			continue;
		}
		capture_report(active);

		if (replay(active) < 0) {
			errors++;
			abort_capture("replay failed");
			continue;
		}
		ok++;
		rfc_dump_regs("end of capture");
	}

	LOG("LOOP", "finished: ok=%lu timeouts=%lu errors=%lu",
	    (unsigned long)ok, (unsigned long)timeouts, (unsigned long)errors);
}

int main(void)
{
	uint32_t words;
	int32_t status;

	Xil_ICacheEnable();
	Xil_DCacheEnable();

	printf("\r\n\r\n");
	LOG("BOOT", "zavadi_rf_capture demo, built " __DATE__ " " __TIME__);

	default_init_param.gpio_resetb.number = GPIO_RESET_PIN;
	default_init_param.gpio_sync.number = -1;
	default_init_param.gpio_cal_sw1.number = -1;
	default_init_param.gpio_cal_sw2.number = -1;

	LOG("RADIO", "ad9361_init...");
	status = ad9361_init(&ad9361_phy, &default_init_param);
	if (status < 0) {
		LOG("ERROR", "ad9361_init: %"PRIi32, status);
		return status;
	}
	LOG("RADIO", "ad9361_init done");

	if (radio_setup() < 0)
		return -1;

	status = axi_dmac_init(&tx_dmac, &tx_dmac_init);
	if (status < 0) {
		LOG("ERROR", "axi_dmac_init tx: %"PRIi32, status);
		return status;
	}
	status = axi_dmac_init(&rx_dmac, &rx_dmac_init);
	if (status < 0) {
		LOG("ERROR", "axi_dmac_init rx: %"PRIi32, status);
		return status;
	}
	LOG("DMA", "RX DMA at 0x%08lx, TX DMA at 0x%08lx",
	    (unsigned long)CF_AD9361_RX_DMA_BASEADDR,
	    (unsigned long)CF_AD9361_TX_DMA_BASEADDR);

	if (tx_dac_setup() < 0)
		return -1;

	if (rfc_probe() < 0) {
		LOG("ERROR", "zavadi_rf_capture probe failed, stopping");
		return -1;
	}

	words = rfc_read(RFC_REG_CAPTURE_SAMPLES);
	LOG("PROBE", "CAPTURE_SAMPLES=%lu words = %lu bytes = %lu us of air",
	    (unsigned long)words, (unsigned long)(words * RFC_BYTES_PER_WORD),
	    (unsigned long)words_to_us(words));
	if (words > CAPTURE_BUFFER_WORDS) {
		LOG("ERROR", "capture (%lu words) does not fit the buffer (%d words)",
		    (unsigned long)words, CAPTURE_BUFFER_WORDS);
		return -1;
	}

	capture_loop(words);

	ad9361_remove(ad9361_phy);
	Xil_DCacheDisable();
	Xil_ICacheDisable();
	return 0;
}
