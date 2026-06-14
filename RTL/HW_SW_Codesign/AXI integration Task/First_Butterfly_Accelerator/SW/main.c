#include <stdio.h>
#include <stdint.h>
#include "pulp.h"
#include "butterfly_driver.h"

// --- Packing Helpers ---
uint64_t pack_19b(int32_t real, int32_t imag) {
    uint64_t r = (uint64_t)(real & 0x7FFFF);
    uint64_t i = (uint64_t)(imag & 0x7FFFF);
    return (r << 19) | i;
}

uint64_t pack_23b(int32_t real, int32_t imag) {
    uint64_t r = (uint64_t)(real & 0x7FFFFF);
    uint64_t i = (uint64_t)(imag & 0x7FFFFF);
    return (r << 23) | i;
}

// --- Unpacking Helpers ---
int32_t unpack_real_19b(uint64_t val) {
    int32_t r = (int32_t)((val >> 19) & 0x7FFFF);
    if (r & 0x40000) r |= 0xFFF80000; 
    return r;
}

int32_t unpack_imag_19b(uint64_t val) {
    int32_t i = (int32_t)(val & 0x7FFFF);
    if (i & 0x40000) i |= 0xFFF80000; 
    return i;
}

// --- Helper to Run and Print a Test ---
void run_butterfly_test(int test_num, const char* twiddle_name, int32_t left_r, int32_t left_i, int32_t right_r, int32_t right_i, int32_t coef_r, int32_t coef_i) {
    printf("--------------------------------------------------\n");
    printf("TEST CASE %d: Twiddle = %s\n", test_num, twiddle_name);
    printf("Inputs : Left = %ld + j%ld, Right = %ld + j%ld\n", left_r, left_i, right_r, right_i);
    
    uint64_t left_in  = pack_19b(left_r, left_i);
    uint64_t right_in = pack_19b(right_r, right_i);
    uint64_t coef_in  = pack_23b(coef_r, coef_i);

    uint64_t left_out = 0, right_out = 0;
    butterfly_compute(left_in, right_in, coef_in, &left_out, &right_out);

    int32_t res_left_r  = unpack_real_19b(left_out);
    int32_t res_left_i  = unpack_imag_19b(left_out);
    int32_t res_right_r = unpack_real_19b(right_out);
    int32_t res_right_i = unpack_imag_19b(right_out);

    printf("Outputs: Sum  = %ld + j%ld\n", res_left_r, res_left_i);
    printf("         Diff = %ld + j%ld\n", res_right_r, res_right_i);
    printf("--------------------------------------------------\n\n");
}

int main() {
    printf("Starting Advanced Butterfly Accelerator Tests...\n\n");

    int32_t left_r  = 100;
    int32_t left_i  = 50;
    int32_t right_r = 40;
    int32_t right_i = 10;

    // TEST 1: Twiddle = 1 + j0 (Scaled by 2^21)
    // Expected Diff: 60 + j40
    run_butterfly_test(1, "1 + j0", left_r, left_i, right_r, right_i, 2097152, 0);

    // TEST 2: Twiddle = 0 - j1 (Scaled by 2^21)
    // Math: (60 + j40) * (0 - j1) = 40 - j60
    // Expected Diff: 40 - j60
    run_butterfly_test(2, "0 - j1", left_r, left_i, right_r, right_i, 0, -2097152);

    // TEST 3: Twiddle = 0.707 - j0.707 (Scaled by 2^21 = 1482910)
    // Math: (60 + j40) * (0.707 - j0.707) = 70.7 - j14.1
    // Expected Diff: 71 - j14
    run_butterfly_test(3, "0.707 - j0.707", left_r, left_i, right_r, right_i, 1482910, -1482910);

    printf("All Tests Complete!\n");
    return 0;
}
