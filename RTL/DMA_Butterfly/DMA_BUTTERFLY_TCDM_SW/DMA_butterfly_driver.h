#ifndef DMA_BUTTERFLY_DRIVER_H
#define DMA_BUTTERFLY_DRIVER_H

#include <stdint.h>

void bfly_clear(void);
void bfly_set_twiddle(uint32_t idx);
void bfly_set_operands(uint32_t left, uint32_t right);
void bfly_trigger(void);
int bfly_poll_done(void);
void bfly_get_results(uint32_t* res_left, uint32_t* res_right);
int butterfly_compute(uint32_t twiddle_idx, uint32_t op_left, uint32_t op_right, uint32_t* res_left, uint32_t* res_right);

#endif
