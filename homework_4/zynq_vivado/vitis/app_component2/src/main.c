#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"

int main() {


    // Запис напряму у TRI-регістр LEDS (0x41210004)
    Xil_Out32(0x41210000 + 0x4, 0x0); 


    while(1) {
        // Увімкнути обидва LED напряму (запис 0x3 у DATA-регістр 0x41210000)
        Xil_Out32(0x41210000, 0x0);
    }

    return 0;
}