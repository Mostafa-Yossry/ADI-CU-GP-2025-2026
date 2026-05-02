#include <stdio.h>
#include <stdint.h>
#include "pmsis.h" 
#include "radix8_driver.h"

#define FFT_LEN 2048

static inline void hw_fft_mixed_radix_2048_optimized(volatile interleaved_cplx_t *data);

// Allocate the 8KB array in L2 memory
PI_L2 volatile interleaved_cplx_t fft_data[FFT_LEN];

int main(void) {
    printf("==================================================\n");
    printf("   Mixed-Radix N=2048 (R8+R4) FFT Test Bench      \n");
    printf("==================================================\n\n");

    /* ---------------------------------------------------------
     * 1. DATA INITIALIZATION (Discrete Impulse)
     * An impulse at index 0 generates equal energy in all bins.
     * Expected Output: Every single bin should be exactly 1000 + j0.
     * --------------------------------------------------------- */
    printf("[INFO] Initializing 8KB Array in L1 Memory...\n");
    for (int i = 0; i < FFT_LEN; i++) {
        if (i == 0) {
            fft_data[i].re = 1000; 
            fft_data[i].im = 0;
        } else {
            fft_data[i].re = 0;
            fft_data[i].im = 0;
        }
    }

    /* ---------------------------------------------------------
     * 2. HARDWARE INITIALIZATION
     * --------------------------------------------------------- */
    printf("[INFO] Resetting Radix-8 Hardware IP...\n");
    radix8_butterfly_init();

    /* ---------------------------------------------------------
     * 3. CONFIGURE PERFORMANCE COUNTERS
     * --------------------------------------------------------- */
    pi_perf_conf((1 << PI_PERF_CYCLES) | (1 << PI_PERF_INSTR));
    pi_perf_reset();

    /* ---------------------------------------------------------
     * 4. EXECUTE MIXED-RADIX FFT
     * --------------------------------------------------------- */
    printf("[INFO] Triggering N=2048 Mixed-Radix FFT...\n");
    
    pi_perf_start();
    
    // Execute the 3 Hardware Stages + 1 Software Stage
    hw_fft_mixed_radix_2048_optimized(fft_data);
    
    pi_perf_stop();

    /* ---------------------------------------------------------
     * 5. READ METRICS
     * --------------------------------------------------------- */
    uint32_t active_cycles = pi_perf_read(PI_PERF_CYCLES);
    uint32_t instructions  = pi_perf_read(PI_PERF_INSTR);

    /* ---------------------------------------------------------
     * 6. VERIFY RESULTS
     * --------------------------------------------------------- */
    printf("[INFO] Execution complete. Verifying...\n\n");
    
    int test_passed = 1;
    for (int i = 0; i < FFT_LEN; i++) {
        // Validate math (Tolerance of +/- 1 due to minor fixed-point rounding)
        if (fft_data[i].re < 999 || fft_data[i].re > 1001 || 
            fft_data[i].im < -1 || fft_data[i].im > 1) {
            test_passed = 0;
        }

        // Print head and tail of the array to prove it worked
        if (i < 4 || i >= FFT_LEN - 4) {
            printf("       Bin %04d: Re = %4d, Im = %4d\n", i, fft_data[i].re, fft_data[i].im);
        }
        if (i == 4) {
            printf("       ... [2040 bins omitted] ...\n");
        }
    }

    printf("\n=== PERFORMANCE METRICS ===\n");
    printf("Total Clock Cycles : %d\n", active_cycles);
    printf("Total Instructions : %d\n", instructions);
    printf("CPI (Cycles/Instr) : %.3f\n", (float)active_cycles / (float)instructions);
    printf("===========================\n");

    printf("\n==================================================\n");
    if (test_passed) {
        printf("   >> STATUS: 2048-POINT FFT PASSED! <<\n");
    } else {
        printf("   >> STATUS: TEST FAILED! <<\n");
    }
    printf("==================================================\n");

    return 0;
}

static inline void hw_fft_mixed_radix_2048_optimized(volatile interleaved_cplx_t *data) {
    // Cast to uint32_t* to force 32-bit (word) memory instructions
    volatile uint32_t *data_u32 = (volatile uint32_t *)data;

    /* =====================================================================
     * STAGE 1: RADIX-8 (Stride = 256) -> 1024 Bytes
     * 1024 Bytes fits perfectly inside the RISC-V 12-bit immediate field!
     * 256 iterations, Twiddle steps by 1.
     * ===================================================================== */
    for (uint32_t j = 0; j < 256; j++) {
        RADIX8_HW->TWIDDLE = j;
        volatile uint32_t *r_ptr = &data_u32[j];
        volatile uint32_t *w_ptr = &data_u32[j];

        __asm__ volatile(
            // --- PIPELINED GATHER ---
            "p.lw x28, 1024(%[ptr_r]!) \n\t" 
            "p.lw x29, 1024(%[ptr_r]!) \n\t" 
            "p.lw x30, 1024(%[ptr_r]!) \n\t" 
            "p.lw x31, 1024(%[ptr_r]!) \n\t" 
            "sw x28, 12(%[hw]) \n\t"
            "sw x29, 16(%[hw]) \n\t"
            "sw x30, 20(%[hw]) \n\t"
            "sw x31, 24(%[hw]) \n\t"
            
            "p.lw x28, 1024(%[ptr_r]!) \n\t" 
            "p.lw x29, 1024(%[ptr_r]!) \n\t" 
            "p.lw x30, 1024(%[ptr_r]!) \n\t" 
            "p.lw x31, 1024(%[ptr_r]!) \n\t" 
            "sw x28, 28(%[hw]) \n\t"
            "sw x29, 32(%[hw]) \n\t"
            "sw x30, 36(%[hw]) \n\t"
            "sw x31, 40(%[hw]) \n\t"

            // --- HARDWARE WAIT ---
            "nop \n\t nop \n\t nop \n\t"
            
            // --- PIPELINED SCATTER ---
            "lw x28, 44(%[hw]) \n\t" 
            "lw x29, 48(%[hw]) \n\t" 
            "lw x30, 52(%[hw]) \n\t" 
            "lw x31, 56(%[hw]) \n\t" 
            "p.sw x28, 1024(%[ptr_w]!) \n\t"
            "p.sw x29, 1024(%[ptr_w]!) \n\t"
            "p.sw x30, 1024(%[ptr_w]!) \n\t"
            "p.sw x31, 1024(%[ptr_w]!) \n\t"
            
            "lw x28, 60(%[hw]) \n\t" 
            "lw x29, 64(%[hw]) \n\t" 
            "lw x30, 68(%[hw]) \n\t" 
            "lw x31, 72(%[hw]) \n\t" 
            "p.sw x28, 1024(%[ptr_w]!) \n\t"
            "p.sw x29, 1024(%[ptr_w]!) \n\t"
            "p.sw x30, 1024(%[ptr_w]!) \n\t"
            "p.sw x31, 1024(%[ptr_w]!) \n\t"
            : [ptr_r] "+r" (r_ptr), [ptr_w] "+r" (w_ptr)
            : [hw] "r" (RADIX8_HW) 
            : "x28", "x29", "x30", "x31", "memory"
        );
    }

    /* =====================================================================
     * STAGE 2: RADIX-8 (Stride = 32) -> 128 Bytes
     * 32 outer loops, 8 inner chained iterations. Twiddle steps by 8.
     * ===================================================================== */
    for (uint32_t j = 0; j < 32; j++) {
        uint16_t twiddle_idx = j * 8; 
        volatile uint32_t *r_ptr = &data_u32[j];
        volatile uint32_t *w_ptr = &data_u32[j];

        for (uint32_t iters = 0; iters < 8; iters++) {
            RADIX8_HW->TWIDDLE = twiddle_idx;
            __asm__ volatile(
                "p.lw x28, 128(%[ptr_r]!) \n\t" "p.lw x29, 128(%[ptr_r]!) \n\t" 
                "p.lw x30, 128(%[ptr_r]!) \n\t" "p.lw x31, 128(%[ptr_r]!) \n\t" 
                "sw x28, 12(%[hw]) \n\t" "sw x29, 16(%[hw]) \n\t"
                "sw x30, 20(%[hw]) \n\t" "sw x31, 24(%[hw]) \n\t"
                
                "p.lw x28, 128(%[ptr_r]!) \n\t" "p.lw x29, 128(%[ptr_r]!) \n\t" 
                "p.lw x30, 128(%[ptr_r]!) \n\t" "p.lw x31, 128(%[ptr_r]!) \n\t" 
                "sw x28, 28(%[hw]) \n\t" "sw x29, 32(%[hw]) \n\t"
                "sw x30, 36(%[hw]) \n\t" "sw x31, 40(%[hw]) \n\t"

                "nop \n\t nop \n\t nop \n\t"
                
                "lw x28, 44(%[hw]) \n\t" "lw x29, 48(%[hw]) \n\t" 
                "lw x30, 52(%[hw]) \n\t" "lw x31, 56(%[hw]) \n\t" 
                "p.sw x28, 128(%[ptr_w]!) \n\t" "p.sw x29, 128(%[ptr_w]!) \n\t"
                "p.sw x30, 128(%[ptr_w]!) \n\t" "p.sw x31, 128(%[ptr_w]!) \n\t"
                
                "lw x28, 60(%[hw]) \n\t" "lw x29, 64(%[hw]) \n\t" 
                "lw x30, 68(%[hw]) \n\t" "lw x31, 72(%[hw]) \n\t" 
                "p.sw x28, 128(%[ptr_w]!) \n\t" "p.sw x29, 128(%[ptr_w]!) \n\t"
                "p.sw x30, 128(%[ptr_w]!) \n\t" "p.sw x31, 128(%[ptr_w]!) \n\t"
                : [ptr_r] "+r" (r_ptr), [ptr_w] "+r" (w_ptr)
                : [hw] "r" (RADIX8_HW) 
                : "x28", "x29", "x30", "x31", "memory"
            );
        }
    }

    /* =====================================================================
     * STAGE 3: RADIX-8 (Stride = 4) -> 16 Bytes
     * 4 outer loops, 64 inner chained iterations. Twiddle steps by 64.
     * ===================================================================== */
    for (uint32_t j = 0; j < 4; j++) {
        uint16_t twiddle_idx = j * 64; 
        volatile uint32_t *r_ptr = &data_u32[j];
        volatile uint32_t *w_ptr = &data_u32[j];

        for (uint32_t iters = 0; iters < 64; iters++) {
            RADIX8_HW->TWIDDLE = twiddle_idx;
            __asm__ volatile(
                "p.lw x28, 16(%[ptr_r]!) \n\t" "p.lw x29, 16(%[ptr_r]!) \n\t" 
                "p.lw x30, 16(%[ptr_r]!) \n\t" "p.lw x31, 16(%[ptr_r]!) \n\t" 
                "sw x28, 12(%[hw]) \n\t" "sw x29, 16(%[hw]) \n\t"
                "sw x30, 20(%[hw]) \n\t" "sw x31, 24(%[hw]) \n\t"
                
                "p.lw x28, 16(%[ptr_r]!) \n\t" "p.lw x29, 16(%[ptr_r]!) \n\t" 
                "p.lw x30, 16(%[ptr_r]!) \n\t" "p.lw x31, 16(%[ptr_r]!) \n\t" 
                "sw x28, 28(%[hw]) \n\t" "sw x29, 32(%[hw]) \n\t"
                "sw x30, 36(%[hw]) \n\t" "sw x31, 40(%[hw]) \n\t"

                "nop \n\t nop \n\t nop \n\t"
                
                "lw x28, 44(%[hw]) \n\t" "lw x29, 48(%[hw]) \n\t" 
                "lw x30, 52(%[hw]) \n\t" "lw x31, 56(%[hw]) \n\t" 
                "p.sw x28, 16(%[ptr_w]!) \n\t" "p.sw x29, 16(%[ptr_w]!) \n\t"
                "p.sw x30, 16(%[ptr_w]!) \n\t" "p.sw x31, 16(%[ptr_w]!) \n\t"
                
                "lw x28, 60(%[hw]) \n\t" "lw x29, 64(%[hw]) \n\t" 
                "lw x30, 68(%[hw]) \n\t" "lw x31, 72(%[hw]) \n\t" 
                "p.sw x28, 16(%[ptr_w]!) \n\t" "p.sw x29, 16(%[ptr_w]!) \n\t"
                "p.sw x30, 16(%[ptr_w]!) \n\t" "p.sw x31, 16(%[ptr_w]!) \n\t"
                : [ptr_r] "+r" (r_ptr), [ptr_w] "+r" (w_ptr)
                : [hw] "r" (RADIX8_HW) 
                : "x28", "x29", "x30", "x31", "memory"
            );
        }
    }
/* =====================================================================
     * STAGE 4: UNIFIED SIMD RADIX-4 DC BUTTERFLY (Stride = 1) -> 4 Bytes
     * All math, including cross-terms, is forced into a single assembly 
     * block. This guarantees GCC will auto-infer the hardware loop and 
     * prevents any registers from spilling to the stack.
     * ===================================================================== */
    volatile uint32_t *r_ptr4 = &data_u32[0];
    volatile uint32_t *w_ptr4 = &data_u32[0];
    
    // Hardcoded mask to extract the upper 16 bits
    uint32_t mask = 0xFFFF0000;

    for (uint32_t iters = 0; iters < 512; iters++) {
        uint32_t x0, x1, x2, x3;
        uint32_t A, B, C, D;
        uint32_t y0, y1, y2, y3;
        uint32_t T_add, T_sub, D_sw;
        uint32_t t1, t2;

        __asm__ volatile(
            // 1. Gather (Post-Increment)
            "p.lw %[x0], 4(%[ptr_r]!) \n\t"
            "p.lw %[x1], 4(%[ptr_r]!) \n\t"
            "p.lw %[x2], 4(%[ptr_r]!) \n\t"
            "p.lw %[x3], 4(%[ptr_r]!) \n\t"

            // 2. SIMD Parallel Math
            "pv.add.h %[A], %[x0], %[x2] \n\t" 
            "pv.sub.h %[B], %[x0], %[x2] \n\t" 
            "pv.add.h %[C], %[x1], %[x3] \n\t" 
            "pv.sub.h %[D], %[x1], %[x3] \n\t" 

            // y0 and y2 are standard additions/subtractions
            "pv.add.h %[y0], %[A], %[C] \n\t"   
            "pv.sub.h %[y2], %[A], %[C] \n\t"   

            // ---------------------------------------------------------
            // 3. CROSS-TERM SIMD MAGIC (y1 & y3)
            // ---------------------------------------------------------
            // Swap the Real and Imaginary halves of D (D_swapped)
            "srli %[t1], %[D], 16 \n\t"
            "slli %[t2], %[D], 16 \n\t"
            "or %[D_sw], %[t1], %[t2] \n\t"

            // Compute all parallel cross combinations simultaneously
            "pv.add.h %[T_add], %[B], %[D_sw] \n\t"
            "pv.sub.h %[T_sub], %[B], %[D_sw] \n\t"

            // Extract and Pack y1
            // y1.im is the top half of T_sub | y1.re is the bottom half of T_add
            "and %[t1], %[T_sub], %[mask] \n\t"       
            "slli %[t2], %[T_add], 16 \n\t"
            "srli %[t2], %[t2], 16 \n\t"              
            "or %[y1], %[t1], %[t2] \n\t"

            // Extract and Pack y3
            // y3.im is the top half of T_add | y3.re is the bottom half of T_sub
            "and %[t1], %[T_add], %[mask] \n\t"       
            "slli %[t2], %[T_sub], 16 \n\t"
            "srli %[t2], %[t2], 16 \n\t"              
            "or %[y3], %[t1], %[t2] \n\t"

            // 4. Scatter (Post-Increment)
            "p.sw %[y0], 4(%[ptr_w]!) \n\t"
            "p.sw %[y1], 4(%[ptr_w]!) \n\t"
            "p.sw %[y2], 4(%[ptr_w]!) \n\t"
            "p.sw %[y3], 4(%[ptr_w]!) \n\t"

            // Use early-clobber (=&r) to ensure GCC provides unique physical registers
            : [x0] "=&r" (x0), [x1] "=&r" (x1), [x2] "=&r" (x2), [x3] "=&r" (x3),
              [A] "=&r" (A), [B] "=&r" (B), [C] "=&r" (C), [D] "=&r" (D),
              [y0] "=&r" (y0), [y1] "=&r" (y1), [y2] "=&r" (y2), [y3] "=&r" (y3),
              [T_add] "=&r" (T_add), [T_sub] "=&r" (T_sub), [D_sw] "=&r" (D_sw),
              [t1] "=&r" (t1), [t2] "=&r" (t2),
              [ptr_r] "+r" (r_ptr4), [ptr_w] "+r" (w_ptr4)
            : [mask] "r" (mask)
            : "memory"
        );
    }
}
