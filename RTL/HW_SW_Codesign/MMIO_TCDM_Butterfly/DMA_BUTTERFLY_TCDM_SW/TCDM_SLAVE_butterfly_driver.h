
#ifndef TCDM_SLAVE_BUTTERFLY_DRIVER_H
#define TCDM_SLAVE_BUTTERFLY_DRIVER_H

#include <stdint.h>
#include "DMA_butterfly_regs.h"

#define TCDM_BUTTERFLY_BASE_ADDR 0x1C090000

// --- STUBS ---
void mmio_bfly_clear(void);
void mmio_bfly_set_twiddle(uint32_t idx);
void mmio_bfly_set_operands(uint32_t left, uint32_t right);
void mmio_bfly_trigger(void);
int mmio_bfly_poll_done(void);
void mmio_bfly_get_results(uint32_t* res_left, uint32_t* res_right);
int mmio_butterfly_compute(uint32_t twiddle_idx, uint32_t op_left, uint32_t op_right, uint32_t* res_left, uint32_t* res_right);

// --- ULTRA-OPTIMIZED INLINE DRIVER ---
// The compiler will weave this directly into main(), eliminating all function call overhead.
static inline __attribute__((always_inline)) int mmio_butterfly_compute_inline(
    uint32_t twiddle_idx, uint32_t op_left, uint32_t op_right, 
    uint32_t* res_left, uint32_t* res_right) 
{
    uint32_t volatile * hw_twiddle   = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_TWIDDLE_REG_OFFSET);
    uint32_t volatile * hw_op_left   = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_LEFT_REG_OFFSET);
    uint32_t volatile * hw_op_right  = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_RIGHT_REG_OFFSET);
    uint32_t volatile * hw_res_left  = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_LEFT_REG_OFFSET);
    uint32_t volatile * hw_res_right = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_RIGHT_REG_OFFSET);

    // 1. Write Data
    *hw_twiddle = twiddle_idx;
    *hw_op_left = op_left;
    *hw_op_right = op_right; // Triggers HW

    // 2. Hardware Synchronization (Fixed!)
    // 2 cycles for math + 1 cycle to latch into Verilog flip-flops. 
    // We wait exactly 3 clock cycles so the CPU reads the correct data.
    asm volatile("nop \n nop \n nop \n");
 
    // 3. Read Results
    *res_left = *hw_res_left;
    *res_right = *hw_res_right;

    return 0;
}

#endif
