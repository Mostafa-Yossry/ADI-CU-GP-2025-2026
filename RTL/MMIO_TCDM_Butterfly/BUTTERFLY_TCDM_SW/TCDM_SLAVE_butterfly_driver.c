#include "pulp.h"
#include "TCDM_SLAVE_butterfly_driver.h"
#include "DMA_butterfly_regs.h" // You can safely reuse the register map header

#define TCDM_BUTTERFLY_BASE_ADDR 0x1C090000

void mmio_bfly_clear(void) {
    uint32_t volatile * ctrl_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_CTRL_REG_OFFSET);
    *ctrl_reg = (1 << BUTTERFLY_CTRL_CLEAR_BIT);
}

void mmio_bfly_set_twiddle(uint32_t idx) {
    uint32_t volatile * twiddle_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_TWIDDLE_REG_OFFSET);
    *twiddle_reg = idx;
}

void mmio_bfly_set_operands(uint32_t left, uint32_t right) {
    uint32_t volatile * op_left_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_LEFT_REG_OFFSET);
    uint32_t volatile * op_right_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_RIGHT_REG_OFFSET);
    *op_left_reg = left;
    *op_right_reg = right;
}

void mmio_bfly_trigger(void) {
    uint32_t volatile * ctrl_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_CTRL_REG_OFFSET);
    *ctrl_reg = (1 << BUTTERFLY_CTRL_TRIGGER_BIT);
}

int mmio_bfly_poll_done(void) {
    uint32_t volatile * status_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_STATUS_REG_OFFSET);
    uint32_t current_status;
    do {
        current_status = (*status_reg >> BUTTERFLY_STATUS_DONE_BIT) & 0x1;
    } while (current_status == 0); 
    
    return 0; 
}

void mmio_bfly_get_results(uint32_t* res_left, uint32_t* res_right) {
    uint32_t volatile * result_l_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_LEFT_REG_OFFSET);
    uint32_t volatile * result_r_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_RIGHT_REG_OFFSET);
    
    *res_left = *result_l_reg;
    *res_right = *result_r_reg;
}

int mmio_butterfly_compute(uint32_t twiddle_idx, uint32_t op_left, uint32_t op_right, uint32_t* res_left, uint32_t* res_right) {
    mmio_bfly_clear();
    mmio_bfly_set_twiddle(twiddle_idx);
    mmio_bfly_set_operands(op_left, op_right);
    mmio_bfly_trigger();
    
    int status = mmio_bfly_poll_done();
    if (status == 0) {
        mmio_bfly_get_results(res_left, res_right);
    }
    return status;
}
