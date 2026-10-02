// main.c -- проста версія: кнопки напряму на світлодіоди.
// Перемикачі фізично підключені й ініціалізовані, але в логіці
// не використовуються -- залишені на майбутнє, якщо захочете
// розширити.

#include "xparameters.h"
#include "xil_io.h"
#include "xgpio.h"

// ---- ПЕРЕВІРИТИ реальні назви у вашому xparameters.h ----
#define LED_BASEADDR   XPAR_AXI_GPIO_LEDS_BASEADDR
#define BTN_BASEADDR   XPAR_AXI_GPIO_BTN_BASEADDR
#define TIMER_BASEADDR    XPAR_AXI_TIMER_0_BASEADDR

XGpio led_gpio, btn_gpio, sw_gpio;

int main() {
    XGpio_Config *cfg_ptr;

    cfg_ptr = XGpio_LookupConfig(LED_BASEADDR);
    XGpio_CfgInitialize(&led_gpio, cfg_ptr, cfg_ptr->BaseAddress);

    cfg_ptr = XGpio_LookupConfig(BTN_BASEADDR);
    XGpio_CfgInitialize(&btn_gpio, cfg_ptr, cfg_ptr->BaseAddress);

    XGpio_SetDataDirection(&led_gpio, 1, 0x0); // вихід
    XGpio_SetDataDirection(&btn_gpio, 1, 0xF); // вхід

    while (1) {
        u32 btn_value = XGpio_DiscreteRead(&btn_gpio, 1);

        // Пряме дзеркалення: яка кнопка натиснута -- той LED світиться
        //XGpio_DiscreteWrite(&led_gpio, 1, btn_value & 0xF);
        XGpio_DiscreteWrite(&led_gpio, 1, 3);
    
    }

    return 0;
}