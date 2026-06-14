#include "pulp.h"
#include "TCDM_SLAVE_butterfly_driver.h"
#include "DMA_butterfly_regs.h" 

#define TCDM_BUTTERFLY_BASE_ADDR 0x1C090000

// --- STUBS FOR COMPATIBILITY ---
// We keep these so your header file doesn't complain, but we won't use them in the fast path.
void mmio_bfly_clear(void) {} // Handled by hardware auto-clear
void mmio_bfly_trigger(void) {} // Handled by hardware auto-trigger
int mmio_bfly_poll_done(void) { return 0; } // Handled by cycle counting

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

void mmio_bfly_get_results(uint32_t* res_left, uint32_t* res_right) {
    uint32_t volatile * result_l_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_LEFT_REG_OFFSET);
    uint32_t volatile * result_r_reg = (uint32_t*) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_RIGHT_REG_OFFSET);
    *res_left = *result_l_reg;
    *res_right = *result_r_reg;
}

// --- THE ULTRA-LOW LATENCY WRAPPER ---
int mmio_butterfly_compute(uint32_t twiddle_idx, uint32_t op_left, uint32_t op_right, uint32_t* res_left, uint32_t* res_right) {
    
    // 1. Pre-calculate pointers to avoid math inside the critical path
    uint32_t volatile * hw_twiddle   = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_TWIDDLE_REG_OFFSET);
    uint32_t volatile * hw_op_left   = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_LEFT_REG_OFFSET);
    uint32_t volatile * hw_op_right  = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_RIGHT_REG_OFFSET);
    uint32_t volatile * hw_res_left  = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_LEFT_REG_OFFSET);
    uint32_t volatile * hw_res_right = (uint32_t volatile *) (TCDM_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_RIGHT_REG_OFFSET);

    // 2. Write parameters
    *hw_twiddle = twiddle_idx;
    *hw_op_left = op_left;

    // 3. Write final operand (Because of the .hjson 'hwqe' change, this auto-triggers the hardware!)
    *hw_op_right = op_right; 

    // 4. Blind Wait (Hardware takes exactly 2 clock cycles)
    asm volatile("nop \n nop \n");

    // 5. Read back the results directly
    *res_left = *hw_res_left;
    *res_right = *hw_res_right;

    return 0; // Success
}
