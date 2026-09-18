# AD936X Pure-PL FPGA Driver Project (Vivado 2021.1)

This project implements a fully hardware-driven, pure programmable logic (PL) initialization and data transceiver system for the **Analog Devices AD9361/AD9363/AD9364** RF Transceivers on a **Xilinx Zynq-7000 (XC7Z020)** FPGA. 

Unlike traditional designs that rely on a processor (Zynq PS ARM core, MicroBlaze) and the Analog Devices No-OS driver, this design runs entirely inside the FPGA fabric (PL) using Verilog HDL. This ensures ultra-low latency, deterministic timing, and a minimal footprint.

---

## 1. Project Architecture & Modules

The design is modularized into distinct blocks for SPI control, state-machine initialization, high-speed LVDS dual-channel data deserialization/serialization, and test-signal generation.

```
                  +----------------------------------------------+
                  |                 system_top                   |
                  |                                              |
 +----------+     |  +----------------+      +----------------+  |     +----------+
 |  System  |---->|  |   clk_wiz_0    |      | rst_gen_module |  |     |  AD936X  |
 |  Clock   |     |  +----------------+      +----------------+  |     |  Control |
 | (i_clk)  |     |          |                       |           |     |  Signals |
 +----------+     |          v                       v           |     | (enable, |
                  |  +----------------+      +----------------+  |     |  txnrx,  |
                  |  | CLK_DIV_module |----->|  AD936X_Init   |--|---->| chip_rst)|
                  |  +----------------+      +----------------+  |     +----------+
                  |                                  | (SPI Bus) |
                  |                                  v           |     +----------+
                  |                          +----------------+  |     |  AD936X  |
                  |                          |   spi_drive    |--|---->|  SPI Bus |
                  |                          +----------------+  |     +----------+
                  |                                              |
                  |  +----------------+      +----------------+  |     +----------+
                  |  |      DDS       |----->|  data_process  |--|---->|  AD936X  |
                  |  |  (Test Source) |      |   (SelectIO)   |<-|-----| High-Speed|
                  |  +----------------+      +----------------+  |     |   LVDS   |
                  |                                  |           |     |  (rx/tx) |
                  |                                  v           |     +----------+
                  |                          +----------------+  |
                  |                          |     ila_0      |  |
                  |                          | (Logic Analyzer|  |
                  |                          +----------------+  |
                  +----------------------------------------------+
```

### Module Breakdown
*   **`system_top.v` (Top-Level Wrapper):** Coordinates global system clocks, reset logic, resets the AD936x transceiver chip, manages operational state triggers, instantiates test signal generators (DDS), logic analyzers (ILA), and maps physical constraints to internal buses.
*   **`AD936X_Init.v` (FSM Initialization Controller):** Executes sequential initialization using an internal lookup table. It reads AD9361 configurations from `AD936X_lut.v` and writes them over SPI. It actively polls calibration and lock status registers, transitioning to an active state only when components like the BBPLL, Rx/Tx PLL, filter tuning, and DC offsets are fully calibrated.
*   **`AD936X_lut.v` (Configuration Lookup Table):** Contains a register configuration array auto-generated via *Analog Devices Customer Software (Version 2.1.3)*. The profile specifies a **Custom Profile** operating with a **40.000 MHz Reference Clock (REFCLK)**.
*   **`spi_drive.v` (SPI Controller):** Custom-built SPI Master engine supporting parameterized data widths (configured for 24-bit AD936x register transactions: 1-bit R/W, 2-bit bank/padding, 10-bit address, 8-bit data), operating with standard CPOL = 0, CPHA = 1 clock configuration.
*   **`data_process.v` (LVDS Interface / DDR Packing):** Interacts with the high-speed differential physical data pins of the AD936x using Xilinx's SelectIO IP (`selectio_wiz_0`). In 2R2T (2 Receive, 2 Transmit) mode, it deserializes/serializes 12-bit parallel I/Q data over the double-data-rate 6-bit LVDS buses, and extracts/generates correct `frame_in` and `frame_out` signals.
*   **`DDS.v` (Direct Digital Synthesizer):** A parameterizable DDS test-pattern generator. It reads a sine-wave table from a BRAM-based ROM (`blk_mem_gen_0`) and supplies deterministic sine waves (1.0 MHz and 2.0 MHz offset frequencies) to test physical TX transmission paths.
*   **`CLK_DIV_module.v` & `rst_gen_module.v` (Helpers):** Custom clock dividers and synchronous reset generators utilized to derive appropriate execution rates (e.g., 25 MHz `spi_clk` from the 100 MHz master domain) and clean initialization resets.
*   **`AD936X_Driver.v` (Alternative Logic):** An alternative, self-contained custom DDR deserialization/serialization driver utilizing native FPGA primitive registers (such as `IDDR`/`ODDR` and `IBUFDS`/`OBUFDS`) directly instead of the automated SelectIO IP Wizard. Useful for designs requiring highly custom, wizard-independent physical layer handling.

---

## 2. Timing, Clocks, & Physical Layer

### Clock Domains
1.  **System Reference (`i_clk`):** Assigned to Pin `N18` (LVCMOS25, Bank 34). It is stepped up/down through the `clk_wiz_0` IP core to output a stable 100.0 MHz `clk_100M` system logic domain.
2.  **SPI Bus Engine (`spi_clk`):** Derived by dividing `clk_100M` by 4 (giving **25.0 MHz**). Used to drive the initialization FSM and SPI transactions.
3.  **High-Speed Data Interface (`data_clk`):** Derived from the AD936x's differential receiver clock output `rx_clk_in_p/n` (Bank 35, constrained to 4.0 ns / **250 MHz** timing requirement). It is buffered using an `IBUFDS` and routed through a `BUFGCE` to serve as the high-speed DDR parallel interface clock (`data_clk`).
4.  **Baseband IQ Logic Sample Rate (`sample_clk`):** Derived inside `data_process.v` by dividing the high-speed `data_clk` by 4 (giving **62.5 MHz** logic clock). This serves as the system clock for all user logic, DDS engines, and logic analyzers.

### AD936X Timing Constraint Details
Timing constraints are defined in `AD936X.xdc`:
```xdc
# High-speed RX Interface timing
create_clock -period 4.000 -name rx_clk [get_ports rx_clk_in_p]

# Set specific dedicated routes & overrides
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_wiz_0_u/inst/clk_in1_clk_wiz_0]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
```

---

## 3. Re-creating & Compiling the Vivado Project

Since this repository contains pure Verilog HDL source files without pre-built Vivado project files (`.xpr`), you must re-create the project inside **Xilinx Vivado (version 2021.1 or compatible)**:

### Step 1: Project Creation
1.  Launch **Vivado 2021.1**.
2.  Select **Create Project** -> Name: `AD936X_only_PL`.
3.  Choose **RTL Project** and check *Do not specify sources at this time*.
4.  Select the target board/part: **`xc7z020clg400-2`** (corresponding to Zynq-7000 7020 boards).

### Step 2: Import Sources & Constraints
1.  Under **Sources**, add all `.v` files from this folder as design sources:
    *   `system_top.v`, `data_process.v`, `DDS.v`, `AD936X_Init.v`, `spi_drive.v`, `CLK_DIV_module.v`, `rst_gen_module.v` (and optionally `AD936X_Driver.v`).
2.  Add `AD936X.xdc` as the project constraint file.
3.  Ensure `AD936X_lut.v` is in the same folder as `AD936X_Init.v` so it can be resolved via the internal `` `include "AD936X_lut.v" `` directive.

### Step 3: IP Core Generation (Crucial)
You must generate the following Xilinx IP blocks with names exactly matching the instantiations:

1.  **Clock Wizard (`clk_wiz_0`):**
    *   Input Clock: Single-ended (from pin `N18`).
    *   Output Clock 1: **100.0 MHz** (Active High reset, `locked` pin enabled).
2.  **SelectIO Interface Wizard (`selectio_wiz_0`):**
    *   *Configuration:* Bus direction: **Bi-directional / Split RX & TX**, DDR (Double Data Rate) external interface.
    *   *Bus Width:* 7 bits (maps 6 bits of differential data + 1 bit of differential frame clock).
    *   *Clocking:* External clock `rx_clk_in_p/n` feeds the wizard, outputting single-ended `clk_out` (mapped to `data_clk`).
3.  **Block Memory Generator (`blk_mem_gen_0`):**
    *   Used for DDS ROM.
    *   *Configuration:* Single Port ROM, 12-bit width, 1024 or 4096 depth (depending on DDS ROM addr mapping).
    *   *Initialization:* Load a `.coe` file containing a normalized digital sine-wave lookup pattern.
4.  **Integrated Logic Analyzer (`ila_0`):**
    *   Create with 8 probes of width 12 bits to monitor RX/TX real-time samples (`rx0_i_data`, `rx0_q_data`, `rx1_i_data`, `rx1_q_data`, `tx0_i_data`, `tx0_q_data`, `tx1_i_data`, `tx1_q_data`).
    *   Trigger/Sample Clock: Connect to `sample_clk` (62.5 MHz).

### Step 4: Run Synthesis & Implementation
1.  Click **Run Synthesis**.
2.  Once completed, select **Run Implementation**.
3.  Review the timing reports. Ensure there are no setup or hold time violations on the 250 MHz high-speed interface clock (`rx_clk`).
4.  Click **Generate Bitstream** to create the `.bit` file.

---

## 4. Operational & Test Verification

When programmed to the target board:
1.  **Reset Phase:** On power-on, `clk_wiz_0` locks. The system generates a synchronous SPI-domain reset, holding the AD936x in reset state (`chip_rst_n` pulled low) for a short period before bringing it high.
2.  **Initialization Phase:** `AD936X_Init` starts stepping through the lookup table. It writes setup commands and polls internal calibration loops. The total initialization takes several milliseconds.
3.  **Active Mode:** Once initialization finishes successfully, `ad9361_config_init_done` goes HIGH.
    *   This automatically sets `txnrx` to `1` (configuring transceiver to active Tx/Rx mode).
    *   It enables high-speed data path processing inside `data_process.v`.
4.  **Signal Transmit (TX):** The DDS starts synthesizing digital sine-waves (1.0 MHz on channel 0, 2.0 MHz on channel 1). The signals are formatted, DDR encoded, and serialized onto the differential physical `tx_data_out` and `tx_frame_out` lines.
5.  **Signal Receive (RX) & Verification:** Received signals on the RF ports are digitized, deserialized, and unpacked. They can be monitored via the **ILA** in Vivado's hardware debugger.
    *   Open **Hardware Manager** in Vivado, program the Zynq PL, and load the ILA trigger.
    *   Inspect `rx0_i_data`, `rx0_q_data`, `rx1_i_data`, and `rx1_q_data` waveforms. Successful calibration yields clean sinusoidal inputs matching external RF signals.

---

## 5. Development & Coding Conventions

When modifying the codebase, adhere strictly to the existing architectural style:
*   **Clock Domain Isolation:** Never mix clocks. The logic is strictly segregated:
    *   Initialization & SPI operations $\to$ synchronous to `spi_clk`.
    *   SelectIO physical DDR packing/unpacking $\to$ synchronous to high-speed `data_clk`.
    *   Baseband user algorithms, filters, and DDS $\to$ synchronous to divided `sample_clk`.
    *   Use appropriate CDC synchronizers (such as double-flops or FIFO handshake logic) if transferring dynamic signals across boundaries.
*   **Active States:**
    *   System resets: Use active-high `reset` / `i_rst` within custom registers, except where interfacing with external active-low pins (such as physical `chip_rst_n`).
*   **DDS Updates:** If modifying lookup memory, ensure the BRAM `.coe` initialization file remains consistent and bounds checked.
