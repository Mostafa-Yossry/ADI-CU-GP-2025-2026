#include <stdio.h>
#include <stdint.h>
#include "pulp.h"
#include "bench/bench.h" 
#include "radix8_butterfly_driver.h"

// ---------------------------------------------------------
// MACROS: 16-bit Real [31:16], 16-bit Imag [15:0]
// ---------------------------------------------------------
#define BF_PACK_16(real, imag) ((((uint32_t)(real) & 0xFFFF) << 16) | ((uint32_t)(imag) & 0xFFFF))

static inline int16_t bf_real(uint32_t x) { return (int16_t)(x >> 16); }
static inline int16_t bf_imag(uint32_t x) { return (int16_t)(x & 0xFFFF); }

// ---------------------------------------------------------
// TEST VECTORS
// ---------------------------------------------------------
typedef struct {
    const char* name;
    uint16_t twiddle;
    int16_t real_in[8];
    int16_t imag_in[8];
} test_vec_t;

int main()
{
    printf("====================================================\n");
    printf("  Radix-8 MMIO Hardware Benchmark & Math Check\n");
    printf("====================================================\n");

    test_vec_t tests[] = {
        {
            .name = "TEST 5: Single Rotating Phasor (Bin 1) + 90-Deg Twiddle",
            .twiddle = 256,
            .real_in = { 100, 71,   0, -71, -100, -71,   0,  71 },
            .imag_in = {   0, 71, 100,  71,    0, -71, -100, -71 }
        },
        {
            .name = "TEST 6: Twin Tones (DC + Nyquist) + 45-Deg Twiddle",
            .twiddle = 512,
            .real_in = { 200, 0, 200, 0, 200, 0, 200, 0 },
            .imag_in = {   0, 0,   0, 0,   0, 0,   0, 0 }
        },
        {
            .name = "TEST 7: The 'All Bins' Multiplier Stress Test",
            .twiddle = 256,
            .real_in = { 100, 0, 0, 0, 0, 0, 0, 0 },
            .imag_in = {   0, 0, 0, 0, 0, 0, 0, 0 }
        }
    };

    int num_tests = sizeof(tests) / sizeof(tests[0]);

    for(int t = 0; t < num_tests; t++) {
        uint32_t packed_in[8];
        uint32_t packed_out[8];

        // Pack the 16-bit inputs into 32-bit operands
        for(int i=0; i<8; i++) {
            packed_in[i] = BF_PACK_16(tests[t].real_in[i], tests[t].imag_in[i]);
        }

        printf("\n----------------------------------------------------\n");
        printf("%s\n", tests[t].name);
        printf("Twiddle Base Index: %d\n", tests[t].twiddle);
        printf("----------------------------------------------------\n");

        // ==========================================
        // LATENCY MEASUREMENT START
        // ==========================================
        perf_reset();
        perf_start();

        // Calling the unrolled, inline function
        radix8_compute_inline(packed_in, tests[t].twiddle, packed_out);

        perf_stop();
        unsigned int latency = cpu_perf_get(0);
        // ==========================================
        // LATENCY MEASUREMENT END
        // ==========================================

        // Unpack and print results
        for(int m=0; m<8; m++) {
            int16_t out_r = bf_real(packed_out[m]);
            int16_t out_i = bf_imag(packed_out[m]);
            printf("Output [%d] : %6d + j%-6d\n", m, out_r, out_i);
        }

        printf("-> TOTAL CYCLE LATENCY : %u clock cycles\n", latency);
    }

    printf("\n====================================================\n");
    printf(" Benchmark Finished\n");
    printf("====================================================\n");

    return 0;
}
