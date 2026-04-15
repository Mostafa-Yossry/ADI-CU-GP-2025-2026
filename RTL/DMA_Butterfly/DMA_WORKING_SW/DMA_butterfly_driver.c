
#include "pulp.h"
#include "DMA_butterfly_driver.h"
#include "DMA_butterfly_regs.h"
#include <stdio.h>

#ifndef DMA_BUTTERFLY_BASE_ADDR
#define DMA_BUTTERFLY_BASE_ADDR 0x1C090000
#endif

void bfly_clear(void) {
    uint32_t volatile * ctrl_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_CTRL_REG_OFFSET);
    *ctrl_reg = (1 << BUTTERFLY_CTRL_CLEAR_BIT);
}

void bfly_set_twiddle(uint32_t idx) {
    uint32_t volatile * twiddle_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_TWIDDLE_REG_OFFSET);
    *twiddle_reg = idx;
}

void bfly_dma_send_operands(uint32_t* left_buffer, uint32_t* right_buffer, uint32_t size_in_bytes) {
    uint32_t op_left_addr = DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_LEFT_REG_OFFSET;
    uint32_t op_right_addr = DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_OP_RIGHT_REG_OFFSET;

    printf("[DRV] Sending %d bytes to IP...\n", size_in_bytes);

    int cmd_id_left = plp_dma_memcpy(op_left_addr, (uint32_t)left_buffer, size_in_bytes, 0);
    int cmd_id_right = plp_dma_memcpy(op_right_addr, (uint32_t)right_buffer, size_in_bytes, 0);

    plp_dma_wait(cmd_id_left);
    plp_dma_wait(cmd_id_right);

    // VERIFICATION: Read the IP directly using MMIO to see if the DMA actually wrote to it!
    uint32_t volatile * left_check = (uint32_t*) op_left_addr;
    printf("[DRV] VERIFY SEND: Hardware Left Operand now holds: 0x%08X\n", *left_check);
}

void bfly_dma_get_results(uint32_t* res_left_buffer, uint32_t* res_right_buffer, uint32_t size_in_bytes) {
    uint32_t result_l_addr = DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_LEFT_REG_OFFSET;
    uint32_t result_r_addr = DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_RES_RIGHT_REG_OFFSET;

    // VERIFICATION: Check what the hardware is trying to send back
    uint32_t volatile * result_check = (uint32_t*) result_l_addr;
    printf("[DRV] VERIFY BEFORE GET: Hardware Left Result currently holds: 0x%08X\n", *result_check);

    int cmd_id_l = plp_dma_memcpy(result_l_addr, (uint32_t)res_left_buffer, size_in_bytes, 1);
    int cmd_id_r = plp_dma_memcpy(result_r_addr, (uint32_t)res_right_buffer, size_in_bytes, 1);

    plp_dma_wait(cmd_id_l);
    plp_dma_wait(cmd_id_r);
}
void bfly_trigger(void) {
    uint32_t volatile * ctrl_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_CTRL_REG_OFFSET);
    *ctrl_reg = (1 << BUTTERFLY_CTRL_TRIGGER_BIT);
}

int bfly_poll_done(void) {
    uint32_t volatile * status_reg = (uint32_t*) (DMA_BUTTERFLY_BASE_ADDR + BUTTERFLY_STATUS_REG_OFFSET);
    uint32_t current_status;
    do {
        current_status = (*status_reg >> BUTTERFLY_STATUS_DONE_BIT) & 0x1;
    } while (current_status == 0); 
    
    return 0; 
}



int butterfly_dma_compute(uint32_t twiddle_idx, uint32_t* left_buf, uint32_t* right_buf, uint32_t* res_l_buf, uint32_t* res_r_buf, uint32_t bytes) {
    bfly_clear();
    bfly_set_twiddle(twiddle_idx);
    
    // DMA moving data in
    bfly_dma_send_operands(left_buf, right_buf, bytes);
    
    bfly_trigger();
    
    int status = bfly_poll_done();
    if (status == 0) {
        // DMA moving data out
        bfly_dma_get_results(res_l_buf, res_r_buf, bytes);
    }
    return status;
}
