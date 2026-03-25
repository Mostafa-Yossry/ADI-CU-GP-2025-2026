#include "pulp.h"
#include "butterfly_driver.h"
#include "butterfly_regs.h"

void butterfly_set_operands(uint64_t left, uint64_t right, uint64_t coef) {
    // Write Left Operand (Split 64-bit into two 32-bit chunks)
    *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_LEFT_0_REG_OFFSET) = (uint32_t)(left & 0xFFFFFFFF);
    *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_LEFT_1_REG_OFFSET) = (uint32_t)(left >> 32);

    // Write Right Operand
    *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_RIGHT_0_REG_OFFSET) = (uint32_t)(right & 0xFFFFFFFF);
    *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_RIGHT_1_REG_OFFSET) = (uint32_t)(right >> 32);

    // Write Coefficient (Twiddle factor)
    *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_COEF_0_REG_OFFSET) = (uint32_t)(coef & 0xFFFFFFFF);
    *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_COEF_1_REG_OFFSET) = (uint32_t)(coef >> 32);
}

void butterfly_trigger(void) {
    // 1. Write 2 (binary 10) to turn on ENABLE first
    *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_CTRL_REG_OFFSET) = 2;
    
    // 2. Write 3 (binary 11) to keep ENABLE on and pulse the TRIGGER
    *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_CTRL_REG_OFFSET) = 3;
}

void butterfly_poll_done(void) {
    volatile uint32_t* status_reg = (volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_STATUS_REG_OFFSET);
    int timeout = 10000; // Timeout counter
    
    // Wait for DONE bit (bit 0) OR timeout
    while ((*status_reg & 0x1) == 0 && timeout > 0) {
        timeout--;
    }
    
    if (timeout == 0) {
        printf("[SW DEBUG] TIMEOUT: o_aux never went high!\n");
    } else {
        printf("[SW DEBUG] SUCCESS: o_aux pulsed high!\n");
    }
}
void butterfly_get_results(uint64_t* res_left, uint64_t* res_right) {
    // Read Left Result
    uint32_t left_0 = *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_RESULT_LEFT_0_REG_OFFSET);
    uint32_t left_1 = *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_RESULT_LEFT_1_REG_OFFSET);
    *res_left = ((uint64_t)left_1 << 32) | left_0;

    // Read Right Result
    uint32_t right_0 = *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_RESULT_RIGHT_0_REG_OFFSET);
    uint32_t right_1 = *(volatile uint32_t*)(BUTTERFLY_BASE_ADDR + BUTTERFLY_RESULT_RIGHT_1_REG_OFFSET);
    *res_right = ((uint64_t)right_1 << 32) | right_0;
}

void butterfly_compute(uint64_t left, uint64_t right, uint64_t coef, uint64_t* res_left, uint64_t* res_right) {
    butterfly_set_operands(left, right, coef);
    butterfly_trigger();
    butterfly_poll_done();
    butterfly_get_results(res_left, res_right);
}
