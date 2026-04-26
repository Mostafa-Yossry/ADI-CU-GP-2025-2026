#ifndef RADIX8_BUTTERFLY_DRIVER_H
#define RADIX8_BUTTERFLY_DRIVER_H

#include <stdint.h>
#include "radix8_butterfly_regs.h" 

#define RADIX8_BUTTERFLY_BASE_ADDR 0x1C091000

// ---------------------------------------------------------
// ZERO-LATENCY INLINE COMPUTE FUNCTION
// ---------------------------------------------------------
static inline void radix8_compute_inline(const uint32_t* data_in, uint16_t twiddle_idx, uint32_t* data_out) {
    uint32_t volatile * ctrl_reg    = (uint32_t*) (RADIX8_BUTTERFLY_BASE_ADDR + RADIX8_BUTTERFLY_CTRL_REG_OFFSET);
    uint32_t volatile * twiddle_reg = (uint32_t*) (RADIX8_BUTTERFLY_BASE_ADDR + RADIX8_BUTTERFLY_TWIDDLE_REG_OFFSET);
    uint32_t volatile * data_reg    = (uint32_t*) (RADIX8_BUTTERFLY_BASE_ADDR + RADIX8_BUTTERFLY_DATA0_REG_OFFSET);
    uint32_t volatile * out_reg     = (uint32_t*) (RADIX8_BUTTERFLY_BASE_ADDR + RADIX8_BUTTERFLY_OUT0_REG_OFFSET);
    uint32_t volatile * status_reg  = (uint32_t*) (RADIX8_BUTTERFLY_BASE_ADDR + RADIX8_BUTTERFLY_STATUS_REG_OFFSET);

    // 1. Clear flag & Enable Clock 
    *ctrl_reg = (1 << RADIX8_BUTTERFLY_CTRL_CLEAR_BIT);
    *ctrl_reg = (1 << RADIX8_BUTTERFLY_CTRL_CLK_EN_BIT); 

    // 2. Set Twiddle
    *twiddle_reg = twiddle_idx;

    // 3. Unrolled Write Operands (Eliminates RISC-V loop branching overhead)
    data_reg[0] = data_in[0];
    data_reg[1] = data_in[1];
    data_reg[2] = data_in[2];
    data_reg[3] = data_in[3];
    data_reg[4] = data_in[4];
    data_reg[5] = data_in[5];
    data_reg[6] = data_in[6];
    data_reg[7] = data_in[7]; // Hardware automatically triggers on this write!

    // 4. Poll Status
    while (((*status_reg) & (1 << RADIX8_BUTTERFLY_STATUS_DONE_BIT)) == 0) {
        // Spin-wait
    }

    // 5. Unrolled Read Results (Eliminates RISC-V loop branching overhead)
    data_out[0] = out_reg[0];
    data_out[1] = out_reg[1];
    data_out[2] = out_reg[2];
    data_out[3] = out_reg[3];
    data_out[4] = out_reg[4];
    data_out[5] = out_reg[5];
    data_out[6] = out_reg[6];
    data_out[7] = out_reg[7];
}

#endif // RADIX8_BUTTERFLY_DRIVER_H
