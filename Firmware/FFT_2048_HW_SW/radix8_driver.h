#ifndef RADIX8_DRIVER_H
#define RADIX8_DRIVER_H

#include <stdint.h>
#include "radix8_butterfly_regs.h"

/* ---------------------------------------------------------
 * 1. HARDWARE MEMORY MAP STRUCT
 * By defining the registers linearly as a volatile struct, 
 * we force the RISC-V compiler to use built-in 12-bit offsets.
 * --------------------------------------------------------- */
typedef struct {
    volatile uint32_t CTRL;      // 0x00
    volatile uint32_t STATUS;    // 0x04
    volatile uint32_t TWIDDLE;   // 0x08
    volatile uint32_t DATA0;     // 0x0C
    volatile uint32_t DATA1;     // 0x10
    volatile uint32_t DATA2;     // 0x14
    volatile uint32_t DATA3;     // 0x18
    volatile uint32_t DATA4;     // 0x1C
    volatile uint32_t DATA5;     // 0x20
    volatile uint32_t DATA6;     // 0x24
    volatile uint32_t DATA7;     // 0x28
    volatile uint32_t OUT0;      // 0x2C
    volatile uint32_t OUT1;      // 0x30
    volatile uint32_t OUT2;      // 0x34
    volatile uint32_t OUT3;      // 0x38
    volatile uint32_t OUT4;      // 0x3C
    volatile uint32_t OUT5;      // 0x40
    volatile uint32_t OUT6;      // 0x44
    volatile uint32_t OUT7;      // 0x48
} radix8_hw_t;

// 2. Cast the Base Address directly to the hardware struct pointer
#define RADIX8_IP_BASE_ADDR 0x1C091000 
#define RADIX8_HW ((radix8_hw_t *)RADIX8_IP_BASE_ADDR)

/* ---------------------------------------------------------
 * 3. INTERLEAVED DATA TYPE
 * --------------------------------------------------------- */
typedef union {
    struct {
        int16_t re;
        int16_t im;
    };
    uint32_t word;
} interleaved_cplx_t;

/**
 * @brief Initializes the Radix-8 Butterfly accelerator
 */
static inline void radix8_butterfly_init(void) {
    // Assert the clear bit to reset internal state
    RADIX8_HW->CTRL = (1 << RADIX8_BUTTERFLY_CTRL_CLEAR_BIT);
    
    // De-assert clear and enable the clock
    RADIX8_HW->CTRL = (1 << RADIX8_BUTTERFLY_CTRL_CLK_EN_BIT);
}

/**
 * @brief Executes a contiguous Radix-8 butterfly computation in-place.
 * @param chunk        Direct pointer to the start of the 8-point interleaved data chunk
 * @param twiddle_idx  The index for the twiddle factor ROM/RAM (Must be pre-bounded!)
 */
static inline void radix8_butterfly_compute(volatile interleaved_cplx_t *chunk, uint16_t twiddle_idx) {
    
    // 1. Set the Twiddle factor index 
    RADIX8_HW->TWIDDLE = twiddle_idx;

    // 2. Load inputs 0 through 6 
    // This will now perfectly compile to: lw x13, 0(x2) -> sw x13, 12(x15)
    RADIX8_HW->DATA0 = chunk[0].word;
    RADIX8_HW->DATA1 = chunk[1].word;
    RADIX8_HW->DATA2 = chunk[2].word;
    RADIX8_HW->DATA3 = chunk[3].word;
    RADIX8_HW->DATA4 = chunk[4].word;
    RADIX8_HW->DATA5 = chunk[5].word;
    RADIX8_HW->DATA6 = chunk[6].word;

    // 3. Load input 7 - This write triggers the hardware execution
    RADIX8_HW->DATA7 = chunk[7].word;

    // 4. Deterministic hardware wait (2 cycles)
    __asm__ volatile(
        "nop \n\t"
	"nop \n\t"
        "nop"

    );

    // 5. Read back the results contiguously (in-place)
    // This will now perfectly compile to: lw x13, 44(x15) -> sw x13, 0(x2)
    chunk[0].word = RADIX8_HW->OUT0;
    chunk[1].word = RADIX8_HW->OUT1;
    chunk[2].word = RADIX8_HW->OUT2;
    chunk[3].word = RADIX8_HW->OUT3;
    chunk[4].word = RADIX8_HW->OUT4;
    chunk[5].word = RADIX8_HW->OUT5;
    chunk[6].word = RADIX8_HW->OUT6;
    chunk[7].word = RADIX8_HW->OUT7;

}

#endif // RADIX8_DRIVER_H
