#include "pulp.h"
#include "simple_butterfly_driver.h"
#include "simple_butterfly_regs.h"

void simple_butterfly_compute(int16_t left_r, int16_t left_i, 
                              int16_t right_r, int16_t right_i, 
                              uint16_t twiddle_idx, 
                              uint32_t* res_left, uint32_t* res_right) {
                       
    uint32_t volatile * twiddle_reg = (uint32_t*) (SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_TWIDDLE_REG_OFFSET);
    uint32_t volatile * op_left_reg = (uint32_t*) (SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_OP_LEFT_REG_OFFSET);
    uint32_t volatile * op_right_reg= (uint32_t*) (SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_OP_RIGHT_REG_OFFSET);
    uint32_t volatile * res_left_reg= (uint32_t*) (SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_RESULT_LEFT_REG_OFFSET);
    uint32_t volatile * res_right_reg=(uint32_t*) (SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_RESULT_RIGHT_REG_OFFSET);
    uint32_t volatile * status_reg  = (uint32_t*) (SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_STATUS_REG_OFFSET);

    // Pack the 12-bit values: Real in [23:12], Imag in [11:0]
    uint32_t packed_left  = (((uint32_t)left_r  & 0xFFF) << 12) | ((uint32_t)left_i  & 0xFFF);
    uint32_t packed_right = (((uint32_t)right_r & 0xFFF) << 12) | ((uint32_t)right_i & 0xFFF);

    *twiddle_reg  = twiddle_idx;
    *op_left_reg  = packed_left;
    *op_right_reg = packed_right; // HW Triggers here!

    //while (!(*status_reg & 1));
    // --- OPTIMIZATION 1: Blind Wait ---
    // Instead of waiting on an expensive AXI read, we force the CPU to wait 
    // 7 clock cycles, perfectly matching the hardware pipeline latency.
    asm volatile(
        "nop \n" "nop \n" "nop \n" "nop \n"
        "nop \n" "nop \n" "nop \n"
    );

    *res_left  = *res_left_reg;
    *res_right = *res_right_reg;
}
