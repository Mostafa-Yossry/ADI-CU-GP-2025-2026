#include <stdio.h>
#include <stdint.h>
#include "pulp.h"
#include "bench/bench.h"
#include "simple_butterfly_regs.h"

#define SIMPLE_BUTTERFLY_BASE_ADDR 0x1A401000

// PACKING MACRO: Real in [23:12], Imag in [11:0]
#define BF_PACK(real, imag) ((((uint32_t)(real) & 0xFFF) << 12) | ((uint32_t)(imag) & 0xFFF))

// Extract Real [23:12] with Sign Extension
static inline int16_t bf_real(uint32_t x) {
    return (int16_t)(((int32_t)(x << 8)) >> 20);
}

// Extract Imag [11:0] with Sign Extension
static inline int16_t bf_imag(uint32_t x) {
    return (int16_t)(((int32_t)(x << 20)) >> 20);
}

typedef struct {
    int16_t lr; int16_t li;
    int16_t rr; int16_t ri;
    uint16_t tw;
} test_vec_t;

// --- TARGET 3: INLINE DRIVER ---
// static inline eliminates the 'jal' and 'ret' instruction overhead
static inline void inline_butterfly_compute(uint32_t packed_left, uint32_t packed_right, uint16_t twiddle_idx, 
                                            uint32_t* res_left, uint32_t* res_right) 
{
    // Write directly to the known memory addresses
    *((volatile uint32_t*)(SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_TWIDDLE_REG_OFFSET)) = twiddle_idx;
    *((volatile uint32_t*)(SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_OP_LEFT_REG_OFFSET)) = packed_left;
    *((volatile uint32_t*)(SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_OP_RIGHT_REG_OFFSET)) = packed_right; // Triggers HW

    // 7-cycle blind wait
    asm volatile(
        "nop \n" "nop \n" "nop \n" "nop \n"
        "nop \n" "nop \n" "nop \n"
    );

    *res_left  = *((volatile uint32_t*)(SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_RESULT_LEFT_REG_OFFSET));
    *res_right = *((volatile uint32_t*)(SIMPLE_BUTTERFLY_BASE_ADDR + SIMPLE_BUTTERFLY_RESULT_RIGHT_REG_OFFSET));
}

int main()
{
    printf("\n====================================================\n");
    printf("        Simple Butterfly AXI Hardware Test\n");
    printf("====================================================\n");

    test_vec_t tests[] = {
        {15, 0,   5, 0,   0},
        {20, 3,  -4, 1,   0},
        {100, 50, 40, 10, 1},
        {-80, 20, 30,-15, 2},
        {50, 0,   0, 0, 1024},
        {30,10,   5, 2, 2047},
        {40, 0,   0, 0, 512},
        {0,  0,   0, 0, 300},
        {2047,2047,2047,2047,100},
        {-2048,-2048,-2048,-2048,200}
    };

    int num_tests = sizeof(tests) / sizeof(tests[0]);

    for(int t = 0; t < num_tests; t++)
    {
        uint32_t res_left = 0;
        uint32_t res_right = 0;

        int16_t lr = tests[t].lr; int16_t li = tests[t].li;
        int16_t rr = tests[t].rr; int16_t ri = tests[t].ri;
        uint16_t tw = tests[t].tw;

        // --- TARGET 2: PACK OUTSIDE OF PERF REGION ---
        uint32_t packed_left = BF_PACK(lr, li);
        uint32_t packed_right = BF_PACK(rr, ri);

        printf("\n----------------------------------------------------\n");
        printf("TEST %d\n", t + 1);
        printf("Twiddle Index : %d\n", tw);
        printf("LEFT  INPUT   : %6d + j%6d\n", lr, li);
        printf("RIGHT INPUT   : %6d + j%6d\n", rr, ri);
        printf("----------------------------------------------------\n");

        // --- LATENCY MEASUREMENT START ---
        perf_reset();
        perf_start();

        // Call the highly optimized inline function
        inline_butterfly_compute(packed_left, packed_right, tw, &res_left, &res_right);

        perf_stop();
        unsigned int latency = cpu_perf_get(0);
        // --- LATENCY MEASUREMENT END ---

        int16_t out_lr = bf_real(res_left);
        int16_t out_li = bf_imag(res_left);
        int16_t out_rr = bf_real(res_right);
        int16_t out_ri = bf_imag(res_right);

        printf("\nRESULT %d\n", t + 1);
        printf("LEFT  OUTPUT  : %6d + j%6d\n", out_lr, out_li);
        printf("RIGHT OUTPUT  : %6d + j%6d\n", out_rr, out_ri);

        printf("\n-> CYCLE LATENCY : %u clock cycles\n", latency);
        printf("====================================================\n");
    }

    printf("\nSimulation Finished\n");
    return 0;
}
