#ifndef __SIMPLE_BUTTERFLY_DRIVER_H__
#define __SIMPLE_BUTTERFLY_DRIVER_H__

#include <stdint.h>

#define SIMPLE_BUTTERFLY_BASE_ADDR 0x1A401000

void simple_butterfly_compute(int16_t left_r, int16_t left_i, 
                              int16_t right_r, int16_t right_i, 
                              uint16_t twiddle_idx, 
                              uint32_t* res_left, uint32_t* res_right);

#endif
