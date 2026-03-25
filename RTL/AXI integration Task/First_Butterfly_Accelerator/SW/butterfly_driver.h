#ifndef __BUTTERFLY_DRIVER_H__
#define __BUTTERFLY_DRIVER_H__

#include <stdint.h>

// Matches the address we put in memory_map.h
#define BUTTERFLY_BASE_ADDR 0x1A401000

// Function prototypes
void butterfly_set_operands(uint64_t left, uint64_t right, uint64_t coef);
void butterfly_trigger(void);
void butterfly_poll_done(void);
void butterfly_get_results(uint64_t* res_left, uint64_t* res_right);

// All-in-one wrapper
void butterfly_compute(uint64_t left, uint64_t right, uint64_t coef, uint64_t* res_left, uint64_t* res_right);

#endif
