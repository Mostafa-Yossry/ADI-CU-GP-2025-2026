#include <stdio.h>
#include <stdint.h>
#include "pmsis.h" 
#include "radix8_driver.h"

#define FFT_LEN 4096


static inline void hw_fft_radix8_4096_optimized(volatile interleaved_cplx_t *data);


PI_L2 volatile interleaved_cplx_t fft_data[FFT_LEN];

int main(void) {
    printf("==================================================\n");
    printf("   Radix-8 N=4096 Hardware FFT Test Bench         \n");
    printf("==================================================\n\n");

    /* ---------------------------------------------------------
     * 1. DATA INITIALIZATION (Discrete Impulse)
     * We load a massive impulse at index 0. The mathematical 
     * result of an unscaled FFT on an impulse is that every 
     * single output bin should exactly equal the input impulse.
     * --------------------------------------------------------- */
    printf("[INFO] Initializing 16KB Array in L1 Memory...\n");
    printf("[INFO] Initializing DC Signal (Constant Amplitude)...\n");
    for (int i = 0; i < FFT_LEN; i++) {
        fft_data[i].re = 5; 
        fft_data[i].im = 0;
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
     * 4. EXECUTE MAXIMUM-THROUGHPUT FFT
     * --------------------------------------------------------- */
    printf("[INFO] Triggering N=4096 Radix-8 FFT...\n");
    
    pi_perf_start();
    
    // Execute the fully unrolled, 4-stage algorithm
    hw_fft_radix8_4096_optimized(fft_data);
    
    pi_perf_stop();

    /* ---------------------------------------------------------
     * 5. READ METRICS
     * --------------------------------------------------------- */
    uint32_t active_cycles = pi_perf_read(PI_PERF_CYCLES);
    uint32_t instructions  = pi_perf_read(PI_PERF_INSTR);

    /* ---------------------------------------------------------
     * 6. VERIFY RESULTS
     * Printing 4096 lines will freeze the UART console, so we 
     * only print the first 4 and last 4 bins to prove it worked.
     * --------------------------------------------------------- */
    printf("[INFO] Hardware execution complete. Verifying...\n\n");
    
    int test_passed = 1;
    for (int i = 0; i < FFT_LEN; i++) {
        // Bin 0 gets all the energy (5 * 4096 = 20480). All others are 0.
        int expected_re = (i == 0) ? (5 * FFT_LEN) : 0;
        
        if (fft_data[i].re != expected_re || fft_data[i].im != 0) {
            test_passed = 0;
        }
    

        // Print head and tail of the array
        if (i < 4 || i >= FFT_LEN - 4) {
            printf("       Bin %04d: Re = %4d, Im = %4d\n", i, fft_data[i].re, fft_data[i].im);
        }
        if (i == 4) {
            printf("       ... [4088 bins omitted] ...\n");
        }
    }

    printf("\n=== PERFORMANCE METRICS ===\n");
    printf("Total Clock Cycles : %d\n", active_cycles);
    printf("Total Instructions : %d\n", instructions);
    // A CPI close to 1.0 here means we achieved perfect 1-cycle memory loads!
    printf("CPI (Cycles/Instr) : %.3f\n", (float)active_cycles / (float)instructions);
    printf("===========================\n");

    printf("\n==================================================\n");
    if (test_passed) {
        printf("   >> STATUS: 4096-POINT FFT PASSED! <<\n");
    } else {
        printf("   >> STATUS: TEST FAILED! <<\n");
    }
    printf("==================================================\n");

    return 0;
}

static inline void hw_fft_radix8_4096_optimized(volatile interleaved_cplx_t *data) {
    // Cast to uint32_t* to force 32-bit (word) memory instructions
    volatile uint32_t *data_u32 = (volatile uint32_t *)data;

    /* =====================================================================
     * STAGE 1: Stride = 512 (n1 = 4096) -> 2048 Bytes
     * Left as a C loop because the pointers must physically reset to 'j' 
     * after every iteration.
     * ===================================================================== */
    uint32_t stride1 = 2048; 
    for (uint32_t j = 0; j < 512; j++) {
        RADIX8_HW->TWIDDLE = j;
        volatile uint32_t *r_ptr = &data_u32[j];
        volatile uint32_t *w_ptr = &data_u32[j];

        __asm__ volatile(
            // --- PIPELINED GATHER ---
            "p.lw x28, %[s](%[ptr_r]!) \n\t" 
            "p.lw x29, %[s](%[ptr_r]!) \n\t" 
            "p.lw x30, %[s](%[ptr_r]!) \n\t" 
            "p.lw x31, %[s](%[ptr_r]!) \n\t" 
            "sw x28, 12(%[hw]) \n\t"
            "sw x29, 16(%[hw]) \n\t"
            "sw x30, 20(%[hw]) \n\t"
            "sw x31, 24(%[hw]) \n\t"
            
            "p.lw x28, %[s](%[ptr_r]!) \n\t" 
            "p.lw x29, %[s](%[ptr_r]!) \n\t" 
            "p.lw x30, %[s](%[ptr_r]!) \n\t" 
            "p.lw x31, %[s](%[ptr_r]!) \n\t" 
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
            "p.sw x28, %[s](%[ptr_w]!) \n\t"
            "p.sw x29, %[s](%[ptr_w]!) \n\t"
            "p.sw x30, %[s](%[ptr_w]!) \n\t"
            "p.sw x31, %[s](%[ptr_w]!) \n\t"
            
            "lw x28, 60(%[hw]) \n\t" 
            "lw x29, 64(%[hw]) \n\t" 
            "lw x30, 68(%[hw]) \n\t" 
            "lw x31, 72(%[hw]) \n\t" 
            "p.sw x28, %[s](%[ptr_w]!) \n\t"
            "p.sw x29, %[s](%[ptr_w]!) \n\t"
            "p.sw x30, %[s](%[ptr_w]!) \n\t"
            "p.sw x31, %[s](%[ptr_w]!) \n\t"
            : [ptr_r] "+r" (r_ptr), [ptr_w] "+r" (w_ptr)
            : [s] "r" (stride1), [hw] "r" (RADIX8_HW) 
            : "x28", "x29", "x30", "x31", "memory"
        );
    }

    /* =====================================================================
     * STAGE 2: Stride = 64 (n1 = 512) -> 256 Bytes
     * The compiler will auto-infer lp.setup for the inner 'iters' loop!
     * ===================================================================== */
    for (uint32_t j = 0; j < 64; j++) {
        uint16_t twiddle_idx = j * 8; 
        
        // Pointers declared OUTSIDE the loop for automatic chaining
        volatile uint32_t *r_ptr = &data_u32[j];
        volatile uint32_t *w_ptr = &data_u32[j];

        for (uint32_t iters = 0; iters < 8; iters++) {
            RADIX8_HW->TWIDDLE = twiddle_idx;
            __asm__ volatile(
                // --- PIPELINED GATHER ---
                "p.lw x28, 256(%[ptr_r]!) \n\t" 
                "p.lw x29, 256(%[ptr_r]!) \n\t" 
                "p.lw x30, 256(%[ptr_r]!) \n\t" 
                "p.lw x31, 256(%[ptr_r]!) \n\t" 
                "sw x28, 12(%[hw]) \n\t"
                "sw x29, 16(%[hw]) \n\t"
                "sw x30, 20(%[hw]) \n\t"
                "sw x31, 24(%[hw]) \n\t"
                
                "p.lw x28, 256(%[ptr_r]!) \n\t" 
                "p.lw x29, 256(%[ptr_r]!) \n\t" 
                "p.lw x30, 256(%[ptr_r]!) \n\t" 
                "p.lw x31, 256(%[ptr_r]!) \n\t" 
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
                "p.sw x28, 256(%[ptr_w]!) \n\t"
                "p.sw x29, 256(%[ptr_w]!) \n\t"
                "p.sw x30, 256(%[ptr_w]!) \n\t"
                "p.sw x31, 256(%[ptr_w]!) \n\t"
                
                "lw x28, 60(%[hw]) \n\t" 
                "lw x29, 64(%[hw]) \n\t" 
                "lw x30, 68(%[hw]) \n\t" 
                "lw x31, 72(%[hw]) \n\t" 
                "p.sw x28, 256(%[ptr_w]!) \n\t"
                "p.sw x29, 256(%[ptr_w]!) \n\t"
                "p.sw x30, 256(%[ptr_w]!) \n\t"
                "p.sw x31, 256(%[ptr_w]!) \n\t"
                : [ptr_r] "+r" (r_ptr), [ptr_w] "+r" (w_ptr)
                : [hw] "r" (RADIX8_HW) 
                : "x28", "x29", "x30", "x31", "memory"
            );
        }
    }

    /* =====================================================================
     * STAGE 3: Stride = 8 (n1 = 64) -> 32 Bytes
     * ===================================================================== */
    for (uint32_t j = 0; j < 8; j++) {
        uint16_t twiddle_idx = j * 64; 
        volatile uint32_t *r_ptr = &data_u32[j];
        volatile uint32_t *w_ptr = &data_u32[j];

        for (uint32_t iters = 0; iters < 64; iters++) {
            RADIX8_HW->TWIDDLE = twiddle_idx;
            __asm__ volatile(
                // --- PIPELINED GATHER ---
                "p.lw x28, 32(%[ptr_r]!) \n\t" 
                "p.lw x29, 32(%[ptr_r]!) \n\t" 
                "p.lw x30, 32(%[ptr_r]!) \n\t" 
                "p.lw x31, 32(%[ptr_r]!) \n\t" 
                "sw x28, 12(%[hw]) \n\t"
                "sw x29, 16(%[hw]) \n\t"
                "sw x30, 20(%[hw]) \n\t"
                "sw x31, 24(%[hw]) \n\t"
                
                "p.lw x28, 32(%[ptr_r]!) \n\t" 
                "p.lw x29, 32(%[ptr_r]!) \n\t" 
                "p.lw x30, 32(%[ptr_r]!) \n\t" 
                "p.lw x31, 32(%[ptr_r]!) \n\t" 
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
                "p.sw x28, 32(%[ptr_w]!) \n\t"
                "p.sw x29, 32(%[ptr_w]!) \n\t"
                "p.sw x30, 32(%[ptr_w]!) \n\t"
                "p.sw x31, 32(%[ptr_w]!) \n\t"
                
                "lw x28, 60(%[hw]) \n\t" 
                "lw x29, 64(%[hw]) \n\t" 
                "lw x30, 68(%[hw]) \n\t" 
                "lw x31, 72(%[hw]) \n\t" 
                "p.sw x28, 32(%[ptr_w]!) \n\t"
                "p.sw x29, 32(%[ptr_w]!) \n\t"
                "p.sw x30, 32(%[ptr_w]!) \n\t"
                "p.sw x31, 32(%[ptr_w]!) \n\t"
                : [ptr_r] "+r" (r_ptr), [ptr_w] "+r" (w_ptr)
                : [hw] "r" (RADIX8_HW) 
                : "x28", "x29", "x30", "x31", "memory"
            );
        }
    }

    /* =====================================================================
     * STAGE 4: Contiguous Memory (Stride = 1) -> 4 Bytes
     * Entire Stage collapses perfectly into 512 auto-inferred loop iterations
     * ===================================================================== */
    RADIX8_HW->TWIDDLE = 0; 
    volatile uint32_t *r_ptr4 = &data_u32[0];
    volatile uint32_t *w_ptr4 = &data_u32[0];

    for (uint32_t iters = 0; iters < 512; iters++) {
        __asm__ volatile(
            // --- PIPELINED GATHER ---
            "p.lw x28, 4(%[ptr_r]!) \n\t" 
            "p.lw x29, 4(%[ptr_r]!) \n\t" 
            "p.lw x30, 4(%[ptr_r]!) \n\t" 
            "p.lw x31, 4(%[ptr_r]!) \n\t" 
            "sw x28, 12(%[hw]) \n\t"
            "sw x29, 16(%[hw]) \n\t"
            "sw x30, 20(%[hw]) \n\t"
            "sw x31, 24(%[hw]) \n\t"
            
            "p.lw x28, 4(%[ptr_r]!) \n\t" 
            "p.lw x29, 4(%[ptr_r]!) \n\t" 
            "p.lw x30, 4(%[ptr_r]!) \n\t" 
            "p.lw x31, 4(%[ptr_r]!) \n\t" 
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
            "p.sw x28, 4(%[ptr_w]!) \n\t"
            "p.sw x29, 4(%[ptr_w]!) \n\t"
            "p.sw x30, 4(%[ptr_w]!) \n\t"
            "p.sw x31, 4(%[ptr_w]!) \n\t"
            
            "lw x28, 60(%[hw]) \n\t" 
            "lw x29, 64(%[hw]) \n\t" 
            "lw x30, 68(%[hw]) \n\t" 
            "lw x31, 72(%[hw]) \n\t" 
            "p.sw x28, 4(%[ptr_w]!) \n\t"
            "p.sw x29, 4(%[ptr_w]!) \n\t"
            "p.sw x30, 4(%[ptr_w]!) \n\t"
            "p.sw x31, 4(%[ptr_w]!) \n\t"
            : [ptr_r] "+r" (r_ptr4), [ptr_w] "+r" (w_ptr4)
            : [hw] "r" (RADIX8_HW) 
            : "x28", "x29", "x30", "x31", "memory"
        );
    }
}
