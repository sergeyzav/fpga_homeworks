/***************************************************************************//**
 *   @file   xilinx/xilinx_gpio.c
 *   @brief  Implementation of Xilinx GPIO Generic Driver.
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
 * Zynq PS GPIO (XGpioPs, MIO + EMIO) only.
 * Vitis SDT flow: xil_gpio_init_param.device_id holds the controller base address.
 */

#include <stdlib.h>

#include <xgpiops.h>

#include "no_os_error.h"
#include "no_os_gpio.h"
#include "gpio_extra.h"

static XGpioPs *gpio_instance(struct no_os_gpio_desc *desc)
{
	return ((struct xil_gpio_desc *)desc->extra)->instance;
}

/**
 * @brief Obtain the GPIO decriptor.
 * @param desc - The GPIO descriptor.
 * @param param - GPIO initialization parameters
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_gpio_get(struct no_os_gpio_desc **desc,
		     const struct no_os_gpio_init_param *param)
{
	struct no_os_gpio_desc *gpio;
	struct xil_gpio_desc *xdesc;
	struct xil_gpio_init_param *xinit;
	XGpioPs_Config *config;
	XGpioPs *instance;

	if (!param || !param->extra)
		return -1;

	xinit = param->extra;
	if (xinit->type != GPIO_PS)
		return -1;

	gpio = calloc(1, sizeof(*gpio));
	xdesc = calloc(1, sizeof(*xdesc));
	instance = calloc(1, sizeof(*instance));
	if (!gpio || !xdesc || !instance)
		goto error;

	config = XGpioPs_LookupConfig(xinit->device_id);
	if (!config)
		goto error;

	if (XGpioPs_CfgInitialize(instance, config, config->BaseAddr) != 0)
		goto error;

	xdesc->type = GPIO_PS;
	xdesc->config = config;
	xdesc->instance = instance;

	gpio->number = param->number;
	gpio->extra = xdesc;

	*desc = gpio;
	return 0;

error:
	free(instance);
	free(xdesc);
	free(gpio);
	return -1;
}

/**
 * @brief Get the value of an optional GPIO.
 * @param desc - The GPIO descriptor.
 * @param param - GPIO Initialization parameters.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_gpio_get_optional(struct no_os_gpio_desc **desc,
			      const struct no_os_gpio_init_param *param)
{
	if (param == NULL) {
		*desc = NULL;
		return 0;
	}

	return xil_gpio_get(desc, param);
}

/**
 * @brief Free the resources allocated by no_os_gpio_get().
 * @param desc - The GPIO descriptor.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_gpio_remove(struct no_os_gpio_desc *desc)
{
	if (desc != NULL) {
		free(gpio_instance(desc));
		free(desc->extra);
		free(desc);
	}

	return 0;
}

/**
 * @brief Enable the input direction of the specified GPIO.
 * @param desc - The GPIO descriptor.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_gpio_direction_input(struct no_os_gpio_desc *desc)
{
	if (!desc)
		return -1;

	XGpioPs_SetDirectionPin(gpio_instance(desc), desc->number, NO_OS_GPIO_IN);

	return 0;
}

/**
 * @brief Enable the output direction of the specified GPIO.
 * @param desc - The GPIO descriptor.
 * @param value - The value.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_gpio_direction_output(struct no_os_gpio_desc *desc,
				  uint8_t value)
{
	XGpioPs *instance;

	if (!desc)
		return -1;

	instance = gpio_instance(desc);
	XGpioPs_SetDirectionPin(instance, desc->number, NO_OS_GPIO_OUT);
	XGpioPs_SetOutputEnablePin(instance, desc->number, NO_OS_GPIO_OUT);
	XGpioPs_WritePin(instance, desc->number, value);

	return 0;
}

/**
 * @brief Get the direction of the specified GPIO.
 * @param desc - The GPIO descriptor.
 * @param direction - The direction.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_gpio_get_direction(struct no_os_gpio_desc *desc,
			       uint8_t *direction)
{
	if (!desc || !direction)
		return -1;

	*direction = XGpioPs_GetDirectionPin(gpio_instance(desc), desc->number);

	return 0;
}

/**
 * @brief Set the value of the specified GPIO.
 * @param desc - The GPIO descriptor.
 * @param value - The value.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_gpio_set_value(struct no_os_gpio_desc *desc,
			   uint8_t value)
{
	if (!desc)
		return -1;

	XGpioPs_WritePin(gpio_instance(desc), desc->number, value);

	return 0;
}

/**
 * @brief Get the value of the specified GPIO.
 * @param desc - The GPIO descriptor.
 * @param value - The value.
 * @return 0 in case of success, -1 otherwise.
 */
int32_t xil_gpio_get_value(struct no_os_gpio_desc *desc,
			   uint8_t *value)
{
	if (!desc || !value)
		return -1;

	*value = XGpioPs_ReadPin(gpio_instance(desc), desc->number);

	return 0;
}

/**
 * @brief Xilinx platform specific GPIO platform ops structure
 */
const struct no_os_gpio_platform_ops xil_gpio_ops = {
	.gpio_ops_get = &xil_gpio_get,
	.gpio_ops_get_optional = &xil_gpio_get_optional,
	.gpio_ops_remove = &xil_gpio_remove,
	.gpio_ops_direction_input = &xil_gpio_direction_input,
	.gpio_ops_direction_output = &xil_gpio_direction_output,
	.gpio_ops_get_direction = &xil_gpio_get_direction,
	.gpio_ops_set_value = &xil_gpio_set_value,
	.gpio_ops_get_value = &xil_gpio_get_value,
};
