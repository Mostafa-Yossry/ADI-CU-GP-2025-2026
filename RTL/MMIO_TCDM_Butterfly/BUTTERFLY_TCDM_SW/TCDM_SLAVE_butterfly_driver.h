#ifndef TCDM_SLAVE_BUTTERFLY_DRIVER_H
#define TCDM_SLAVE_BUTTERFLY_DRIVER_H

#include <stdint.h>

void mmio_bfly_clear(void);
void mmio_bfly_set_twiddle(uint32_t idx);
void mmio_bfly_set_operands(uint32_t left, uint32_t right);
void mmio_bfly_trigger(void);
int mmio_bfly_poll_done(void);
void mmio_bfly_get_results(uint32_t* res_left, uint32_t* res_right);

// Main wrapper function
int mmio_butterfly_compute(uint32_t twiddle_idx, uint32_t op_left, uint32_t op_right, uint32_t* res_left, uint32_t* res_right);

#endif
