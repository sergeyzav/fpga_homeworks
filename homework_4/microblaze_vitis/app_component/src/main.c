#include "xparameters.h"
#include "xgpio.h"
#include "xtmrctr.h"
#include "xil_exception.h"
#include "xinterrupt_wrap.h"
#include <xil_types.h>

#define LED_BASEADDR          XPAR_AXI_LEDS_BASEADDR
#define BTN_BASEADDR          XPAR_AXI_BTN_BASEADDR
#define SW_BASEADDR           XPAR_AXI_SW_BASEADDR
#define XTMRCTR_BASEADDRESS   XPAR_AXI_TIMER_BASEADDR
#define TIMER_CLOCK_FREQUENCY XPAR_AXI_TIMER_CLOCK_FREQUENCY

#define TIMER_CNTR_0          0
#define RESET_VALUE           0xFFFF0000
#define LED_MAX               0x03  

XGpio ledsGpio, btnGpio, swGpio;
XTmrCtr TimerCounterInst;

static volatile int ledValue = 0;
static volatile int direction = 0;
static volatile int timerCounter = 0;
static volatile u32 btnPrev = 0;

int SetupTimer(XTmrCtr *InstancePtr, UINTPTR BaseAddr);
static void TimerHandler(void *CallBackRef, u8 TmrCtrNumber);

void TimerHandler(void*, u8)
{
    u32 btn = XGpio_DiscreteRead(&btnGpio, 1);
    
    if (btn && btn != btnPrev) {
        direction = !direction;
        ledValue = LED_MAX;
    }

    btnPrev = btn;



    u32 speed = XGpio_DiscreteRead(&swGpio, 1);
    
    timerCounter++;
    if (timerCounter % (100*(1 + speed)) == 0) {
        ledValue = (ledValue + 1) & LED_MAX;
        if (direction) {
            XGpio_DiscreteWrite(&ledsGpio, 1, ledValue);
        } else {
             XGpio_DiscreteWrite(&ledsGpio, 1, (~ledValue) & LED_MAX);
        }
        
    }
}

int SetupTimer(XTmrCtr *TmrCtrInstancePtr, UINTPTR BaseAddr)
{
    int Status;

    Status = XTmrCtr_Initialize(TmrCtrInstancePtr, BaseAddr);
    if (Status != XST_SUCCESS) return XST_FAILURE;

    Status = XTmrCtr_SelfTest(TmrCtrInstancePtr, TIMER_CNTR_0);
    if (Status != XST_SUCCESS) return XST_FAILURE;

    Status = XSetupInterruptSystem(TmrCtrInstancePtr, 
                                   (XInterruptHandler)XTmrCtr_InterruptHandler,
                                   TmrCtrInstancePtr->Config.IntrId, 
                                   TmrCtrInstancePtr->Config.IntrParent,
                                   XINTERRUPT_DEFAULT_PRIORITY);
    if (Status != XST_SUCCESS) return XST_FAILURE;

    XTmrCtr_SetHandler(TmrCtrInstancePtr, TimerHandler, TmrCtrInstancePtr);

    XTmrCtr_SetOptions(TmrCtrInstancePtr, TIMER_CNTR_0,
                       XTC_INT_MODE_OPTION | XTC_AUTO_RELOAD_OPTION);

    XTmrCtr_SetResetValue(TmrCtrInstancePtr, TIMER_CNTR_0, RESET_VALUE);
    XTmrCtr_Start(TmrCtrInstancePtr, TIMER_CNTR_0);
}

int main(void)
{
    XGpio_Config *gpioConfigPtr;

    // Ініціалізація LED GPIO
    gpioConfigPtr = XGpio_LookupConfig(LED_BASEADDR);
    if (!gpioConfigPtr) return XST_FAILURE;
    XGpio_CfgInitialize(&ledsGpio, gpioConfigPtr, gpioConfigPtr->BaseAddress);

    gpioConfigPtr = XGpio_LookupConfig(BTN_BASEADDR);
    if (!gpioConfigPtr) return XST_FAILURE;
    XGpio_CfgInitialize(&btnGpio, gpioConfigPtr, gpioConfigPtr->BaseAddress);

    gpioConfigPtr = XGpio_LookupConfig(SW_BASEADDR);
    if (!gpioConfigPtr) return XST_FAILURE;
    XGpio_CfgInitialize(&swGpio, gpioConfigPtr, gpioConfigPtr->BaseAddress);

    XGpio_SetDataDirection(&ledsGpio, 1, 0x0); 
    XGpio_SetDataDirection(&btnGpio, 1, 0xFF); 
    XGpio_SetDataDirection(&swGpio, 1, 0xFF); 

    int Status = SetupTimer(&TimerCounterInst, XTMRCTR_BASEADDRESS);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }

    timerCounter = 0;

    while (1) {}

    return XST_SUCCESS;
}