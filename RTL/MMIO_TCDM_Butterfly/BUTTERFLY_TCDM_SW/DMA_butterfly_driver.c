
#include "pulp.h"
#include "DMA_butterfly_driver.h"
#include "DMA_butterfly_regs.h"
#include <stdio.h> // Needed for printf

#ifndef DMA_BUTTERFLY_BASE_ADDR
#define DMA_BUTTERFLY_BASE_ADDR 0x1C090000
#endif


void bfly_clear(void) {
    uint32_t volatile * ctrl_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_CTRL_REG_OFFSET);
    printf("[DRV] Sending CLEAR command to 0x%08X...\n", (uint32_t)ctrl_reg);
    *ctrl_reg = (1 << BUTTERFLY_CTRL_CLEAR_BIT);
}

void bfly_set_twiddle(uint32_t idx) {
    uint32_t volatile * twiddle_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_TWIDDLE_REG_OFFSET);
    printf("[DRV] Writing Twiddle %d to 0x%08X...\n", idx, (uint32_t)twiddle_reg);
    *twiddle_reg = idx;
    
    // READBACK TEST: Verify the bus is actually saving our writes
    uint32_t readback = *twiddle_reg;
    printf("[DRV] Readback Twiddle: %d\n", readback);
}

void bfly_set_operands(uint32_t left, uint32_t right) {
    uint32_t volatile * op_left_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_LEFT_REG_OFFSET);
    uint32_t volatile * op_right_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_RIGHT_REG_OFFSET);
    printf("[DRV] Writing Operands Left: 0x%08X, Right: 0x%08X...\n", left, right);
    *op_left_reg = left;
    *op_right_reg = right;
}

void bfly_trigger(void) {
    uint32_t volatile * ctrl_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_CTRL_REG_OFFSET);
    printf("[DRV] Sending TRIGGER command...\n");
    *ctrl_reg = (1 << BUTTERFLY_CTRL_TRIGGER_BIT);
}

int bfly_poll_done(void) {
    uint32_t volatile * status_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_STATUS_REG_OFFSET);
    uint32_t current_status;
    int timeout = 0;
    
    printf("[DRV] Polling STATUS at 0x%08X...\n", (uint32_t)status_reg);
    do {
        uint32_t raw_status = *status_reg;
        current_status = (raw_status >> BUTTERFLY_STATUS_DONE_BIT) & 0x1;
        
        printf("[DRV] Poll %d: Raw Register = 0x%08X | Done Bit = %d\n", timeout, raw_status, current_status);
        
        timeout++;
        if (timeout > 10) {
            printf("[DRV] TIMEOUT ERROR! Hardware did not assert the DONE bit.\n");
            return -1; // Force exit to prevent a system hang
        }
    } while (current_status == 0); 
    
    return 0; 
}

void bfly_get_results(uint32_t* res_left, uint32_t* res_right) {
    uint32_t volatile * result_l_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_LEFT_REG_OFFSET);
    uint32_t volatile * result_r_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_RIGHT_REG_OFFSET);
    
    *res_left = *result_l_reg;
    *res_right = *result_r_reg;
    printf("[DRV] Results fetched: Left=0x%08X, Right=0x%08X\n", *res_left, *res_right);
}

int butterfly_compute(uint32_t twiddle_idx, uint32_t op_left, uint32_t op_right, uint32_t* res_left, uint32_t* res_right) {
    bfly_clear();
    bfly_set_twiddle(twiddle_idx);
    bfly_set_operands(op_left, op_right);
    bfly_trigger();
    
    int status = bfly_poll_done();
    if (status == 0) {
        bfly_get_results(res_left, res_right);
    }
    return status;
}
