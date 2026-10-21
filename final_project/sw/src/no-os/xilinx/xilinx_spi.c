/***************************************************************************//**
 *   @file   xilinx/xilinx_spi.c
 *   @brief  Implementation of Xilinx SPI Generic Driver.
 *   @author Antoniu Miclaus (antoniu.miclaus@analog.com)
********************************************************************************
 * Copyright 2019(c) Analog Devices, Inc.
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
 * Zynq PS SPI (XSpiPs) only. Adapted to the Vitis SDT flow:
 * param->device_id holds the controller base address, and the input clock
 * comes from the driver config instead of XPAR_*_SPI_CLK_FREQ_HZ.
 */

#include <stdlib.h>

#include <xspips.h>

#include "no_os_error.h"
#include "no_os_spi.h"
#include "spi_extra.h"

/* Pick the smallest prescaler that keeps SCLK <= max_speed_hz */
static uint32_t spi_prescaler(uint32_t input_clock, uint32_t max_speed_hz)
{
	uint32_t prescaler = XSPIPS_CLK_PRESCALE_4;

	if (max_speed_hz == 0)
		return XSPIPS_CLK_PRESCALE_64;

	/* Register value p divides the input clock by 2^(p + 1) */
	while (prescaler < XSPIPS_CLK_PRESCALE_256 &&
	       (input_clock >> (prescaler + 1)) > max_speed_hz)
		prescaler++;

	return prescaler;
}

/**
 * @brief Initialize the SPI communication peripheral.
 * @param desc - The SPI descriptor.
 * @param param - The structure that contains the SPI parameters.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_spi_init(struct no_os_spi_desc **desc,
		     const struct no_os_spi_init_param *param)
{
	struct no_os_spi_desc *spi;
	struct xil_spi_desc *xdesc;
	struct xil_spi_init_param *xinit;
	XSpiPs_Config *config;
	XSpiPs *instance;

	if (!param || !param->extra)
		return -1;

	xinit = param->extra;
	if (xinit->type != SPI_PS)
		return -1;

	spi = calloc(1, sizeof(*spi));
	xdesc = calloc(1, sizeof(*xdesc));
	instance = calloc(1, sizeof(*instance));
	if (!spi || !xdesc || !instance)
		goto error;

	config = XSpiPs_LookupConfig(param->device_id);
	if (!config)
		goto error;

	if (XSpiPs_CfgInitialize(instance, config, config->BaseAddress) != 0)
		goto error;

	if (XSpiPs_SetClkPrescaler(instance,
				   spi_prescaler(config->InputClockHz,
						 param->max_speed_hz)) != 0)
		goto error;

	spi->max_speed_hz = param->max_speed_hz;
	spi->mode = param->mode;
	spi->bit_order = param->bit_order;
	spi->chip_select = param->chip_select;

	xdesc->type = SPI_PS;
	xdesc->flags = xinit->flags;
	xdesc->config = config;
	xdesc->instance = instance;
	spi->extra = xdesc;

	*desc = spi;
	return 0;

error:
	free(instance);
	free(xdesc);
	free(spi);
	return -1;
}

/**
 * @brief Free the resources allocated by no_os_spi_init().
 * @param desc - The SPI descriptor.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_spi_remove(struct no_os_spi_desc *desc)
{
	struct xil_spi_desc *xdesc;

	if (!desc || !desc->extra)
		return -1;

	xdesc = desc->extra;
	free(xdesc->instance);
	free(xdesc);
	free(desc);

	return 0;
}

/**
 * @brief Write and read data to/from SPI.
 * @param desc - The SPI descriptor.
 * @param data - The buffer with the transmitted/received data.
 * @param bytes_number - Number of bytes to write/read.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_spi_write_and_read(struct no_os_spi_desc *desc,
			       uint8_t *data,
			       uint16_t bytes_number)
{
	struct xil_spi_desc *xdesc;
	XSpiPs *instance;
	uint32_t options;

	if (!desc || !desc->extra)
		return -1;

	xdesc = desc->extra;
	instance = xdesc->instance;

	options = XSPIPS_MASTER_OPTION | XSPIPS_FORCE_SSELECT_OPTION;
	if (xdesc->flags & SPI_CS_DECODE)
		options |= XSPIPS_DECODE_SSELECT_OPTION;
	if (desc->mode & NO_OS_SPI_CPOL)
		options |= XSPIPS_CLK_ACTIVE_LOW_OPTION;
	if (desc->mode & NO_OS_SPI_CPHA)
		options |= XSPIPS_CLK_PHASE_1_OPTION;

	if (XSpiPs_SetOptions(instance, options) != 0)
		return -1;

	if (XSpiPs_SetSlaveSelect(instance, desc->chip_select) != 0)
		return -1;

	if (XSpiPs_PolledTransfer(instance, data, data, bytes_number) != 0)
		return -1;

	if (XSpiPs_SetSlaveSelect(instance, SPI_DEASSERT_CURRENT_SS) != 0)
		return -1;

	return 0;
}

/**
 * @brief Xilinx platform specific SPI platform ops structure
 */
const struct no_os_spi_platform_ops xil_spi_ops = {
	.init = &xil_spi_init,
	.write_and_read = &xil_spi_write_and_read,
	.remove = &xil_spi_remove
};
