#ifndef DMA_BUTTERFLY_DRIVER_H
#define DMA_BUTTERFLY_DRIVER_H

#include <stdint.h>

void bfly_clear(void);
void bfly_set_twiddle(uint32_t idx);

// UPGRADED: Now accepts pointers and a size for DMA transfers
void bfly_dma_send_operands(uint32_t* left_buffer, uint32_t* right_buffer, uint32_t size_in_bytes);
void bfly_trigger(void);
int bfly_poll_done(void);

// UPGRADED: Now accepts pointers to dump the hardware results directly into memory
void bfly_dma_get_results(uint32_t* res_left_buffer, uint32_t* res_right_buffer, uint32_t size_in_bytes);

// UPGRADED: Main wrapper
int butterfly_dma_compute(uint32_t twiddle_idx, uint32_t* left_buf, uint32_t* right_buf, uint32_t* res_l_buf, uint32_t* res_r_buf, uint32_t bytes);

#endif
