#include <stdio.h>
#include <stdint.h>
#include "pulp.h"
#include "bench/bench.h" // Needed for performance counters
#include "TCDM_SLAVE_butterfly_driver.h" // Using the prefixed MMIO header

// ---------------------------------------------------------
// MACROS: 12-bit Real [23:12], 12-bit Imag [11:0]
// ---------------------------------------------------------
#define BF_PACK(real, imag) ((((uint32_t)(real) & 0xFFF) << 12) | ((uint32_t)(imag) & 0xFFF))

static inline int16_t bf_real(uint32_t x) {
    return (int16_t)(((int32_t)(x << 8)) >> 20);
}

static inline int16_t bf_imag(uint32_t x) {
    return (int16_t)(((int32_t)(x << 20)) >> 20);
}

// ---------------------------------------------------------
// TEST VECTORS
// ---------------------------------------------------------
typedef struct {
    int16_t lr; int16_t li;
    int16_t rr; int16_t ri;
    uint16_t tw;
} test_vec_t;

// ---------------------------------------------------------
// MAIN (Runs on Fabric Controller)
// ---------------------------------------------------------
int main() {
    printf("====================================================\n");
    printf("        MMIO TCDM Slave Butterfly Benchmark Test      \n");
    printf("====================================================\n");

    // Define the exact same test cases used in the DMA benchmark
    test_vec_t tests[] = {
        {10,  5,   2,  1,   0},   // Test 1: Our golden test (12+6i, 8+4i)
        {15,  0,   5,  0,   0},   // Test 2
        {20,  3,  -4,  1,   0},   // Test 3
        {100, 50,  40, 10,  1},   // Test 4
        {-80, 20,  30,-15,  2},   // Test 5
        {50,  0,   0,  0,   1024},// Test 6
        {30,  10,  5,  2,   2047} // Test 7
    };

    int num_tests = sizeof(tests) / sizeof(tests[0]);

    for(int t = 0; t < num_tests; t++) {
        // Pack the 12-bit inputs into 32-bit operands
        uint32_t packed_left = BF_PACK(tests[t].lr, tests[t].li);
        uint32_t packed_right = BF_PACK(tests[t].rr, tests[t].ri);
        
        uint32_t res_left = 0;
        uint32_t res_right = 0;

        printf("\n----------------------------------------------------\n");
        printf("TEST %d | Twiddle: %d\n", t + 1, tests[t].tw);
        printf("LEFT  INPUT   : %6d + j%6d\n", tests[t].lr, tests[t].li);
        printf("RIGHT INPUT   : %6d + j%6d\n", tests[t].rr, tests[t].ri);

        // ==========================================
        // LATENCY MEASUREMENT START
        // ==========================================
        perf_reset();
        perf_start();

        // CPU manually writes operands, triggers HW, and polls status
        int status = mmio_butterfly_compute(tests[t].tw, packed_left, packed_right, &res_left, &res_right);

        perf_stop();
        unsigned int latency = cpu_perf_get(0);
        // ==========================================
        // LATENCY MEASUREMENT END
        // ==========================================

        if (status == 0) {
            // Unpack 12-bit results
            int16_t out_lr = bf_real(res_left);
            int16_t out_li = bf_imag(res_left);
            int16_t out_rr = bf_real(res_right);
            int16_t out_ri = bf_imag(res_right);

            printf("LEFT  OUTPUT  : %6d + j%6d\n", out_lr, out_li);
            printf("RIGHT OUTPUT  : %6d + j%6d\n", out_rr, out_ri);
            printf("-> TOTAL CYCLE LATENCY : %u clock cycles\n", latency);
        } else {
            printf("ERROR: Test %d timed out or failed.\n", t + 1);
        }
    }

    printf("\n====================================================\n");
    printf(" MMIO Benchmark Finished\n");
    printf("====================================================\n");

    return 0;
}
