#include "xparameters.h"
#include "xgpio.h"
#include "xaxidma.h"
#include "xstatus.h"
#include "sleep.h"
#include <xil_types.h>

#define GPIO_BTN_BASEADDR  XPAR_AXI_GPIO_BTN_BASEADDR
#define DMA_BASEADDR       XPAR_AXI_DMA_0_BASEADDR
#define RAM_BASE         XPAR_AXI_FULL_RAM_0_BASEADDR

#define FRAME_BYTES        (64000 * 4)

#define BTN_CH             1
#define CTRL_CH            2
#define BTN_MASK           0x1

XGpio   gpio;
XAxiDma dma;

int main(void)
{
    XGpio_Config *gcfg = XGpio_LookupConfig(GPIO_BTN_BASEADDR);
    XGpio_CfgInitialize(&gpio, gcfg, gcfg->BaseAddress);


    XGpio_SetDataDirection(&gpio, BTN_CH, BTN_MASK);
    XGpio_SetDataDirection(&gpio, CTRL_CH, 0x0);
    XGpio_DiscreteWrite(&gpio, CTRL_CH, 0);

    XAxiDma_Config *dcfg = XAxiDma_LookupConfig(DMA_BASEADDR);
    XAxiDma_CfgInitialize(&dma, dcfg);


    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    int running = 0;

    while (1) {
        u32 btn = XGpio_DiscreteRead(&gpio, BTN_CH) & BTN_MASK;

        if (btn && !running) {
            XAxiDma_SimpleTransfer(&dma, RAM_BASE, FRAME_BYTES,
                                            XAXIDMA_DEVICE_TO_DMA);
            XGpio_DiscreteWrite(&gpio, CTRL_CH, 1);
            running = 1;
        }

        if (running && !XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA)) {
            while (1); //stop after TLAST
        }
    }

    return XST_SUCCESS;
}