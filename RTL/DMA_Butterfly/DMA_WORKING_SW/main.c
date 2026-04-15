#include <stdio.h>
#include <stdint.h>
#include "pulp.h"
#include "bench/bench.h" // Needed for performance counters
#include "DMA_butterfly_driver.h"

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
// CLUSTER DMA TASK (Runs on Core 0)
// ---------------------------------------------------------
int cluster_dma_task(void) {
    // Only Core 0 runs this test. Cores 1-7 sleep.
    if (hal_core_id() != 0) {
        return 0; 
    }

    printf("[CLUSTER-PE0] Starting Multi-Test DMA Benchmark...\n");

    // 1. Allocate in Safe L1 Cluster Memory
    uint32_t* op_left_buf   = (uint32_t*) 0x10008000;
    uint32_t* op_right_buf  = (uint32_t*) 0x10008004;
    volatile uint32_t* res_left_buf  = (uint32_t*) 0x10008008;
    volatile uint32_t* res_right_buf = (uint32_t*) 0x1000800C;

    uint32_t transfer_size_bytes = 4;

    // 2. Define Test Cases (Added our golden test at the top)
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

    // 3. Loop through and benchmark each test
    for(int t = 0; t < num_tests; t++) {
        // Pack inputs and load them into the L1 memory buffers
        *op_left_buf = BF_PACK(tests[t].lr, tests[t].li);
        *op_right_buf = BF_PACK(tests[t].rr, tests[t].ri);
        
        // Clear old results
        *res_left_buf = 0xDEADBEEF;
        *res_right_buf = 0xDEADBEEF;

        printf("\n----------------------------------------------------\n");
        printf("TEST %d | Twiddle: %d\n", t + 1, tests[t].tw);
        printf("LEFT  INPUT   : %6d + j%6d\n", tests[t].lr, tests[t].li);
        printf("RIGHT INPUT   : %6d + j%6d\n", tests[t].rr, tests[t].ri);
        
        // ==========================================
        // LATENCY MEASUREMENT START
        // ==========================================
        perf_reset();
        perf_start();

        // The DMA driver handles the entire pipeline
        int status = butterfly_dma_compute(
            tests[t].tw, 
            op_left_buf, 
            op_right_buf, 
            (uint32_t*)res_left_buf, 
            (uint32_t*)res_right_buf, 
            transfer_size_bytes
        );

        perf_stop();
        unsigned int latency = cpu_perf_get(0);
        // ==========================================
        // LATENCY MEASUREMENT END
        // ==========================================

        if (status == 0) {
            // Unpack results
            int16_t out_lr = bf_real(*res_left_buf);
            int16_t out_li = bf_imag(*res_left_buf);
            int16_t out_rr = bf_real(*res_right_buf);
            int16_t out_ri = bf_imag(*res_right_buf);

            printf("LEFT  OUTPUT  : %6d + j%6d\n", out_lr, out_li);
            printf("RIGHT OUTPUT  : %6d + j%6d\n", out_rr, out_ri);
            printf("-> TOTAL CYCLE LATENCY : %u clock cycles\n", latency);
        } else {
            printf("[CLUSTER-PE0] ERROR: Test %d timed out.\n", t + 1);
        }
    }

    printf("\n====================================================\n");
    printf(" DMA Benchmark Finished\n");
    printf("====================================================\n");

    return 0;
}

// ---------------------------------------------------------
// MAIN (Runs on Fabric Controller)
// ---------------------------------------------------------
int main() {
    printf("====================================================\n");
    printf("        CLUSTER DMA Butterfly Benchmark Test        \n");
    printf("====================================================\n");

    // Boot Cluster 0
    cluster_start(0, cluster_dma_task);
    
    // Wait for tests to finish
    cluster_wait(0);

    return 0;
}
