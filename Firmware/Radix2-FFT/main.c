#include <stdio.h>
#include "pmsis.h"
#include "plp_math.h"
#include "plp_const_structs.h"

#define N_FFT 4096

// Input in L2
PI_L2 int16_t Input_L2[2*N_FFT];

void cluster_main(void *arg)
{
    int16_t *l2_buffer = (int16_t *)arg;
    uint32_t size = 2 * N_FFT * sizeof(int16_t);
    
    // 1. Allocate L1 Memory on the Cluster
    int16_t *l1_buffer = (int16_t *)pmsis_l1_malloc(size);
    if (l1_buffer == NULL) {
        printf("[ERROR] L1 Malloc failed!\n");
        return;
    }

    // 2. DMA Copy: L2 -> L1
    pi_cl_dma_cmd_t cmd;
    pi_cl_dma_cmd((uint32_t)l2_buffer, (uint32_t)l1_buffer, size, PI_CL_DMA_DIR_EXT2LOC, &cmd);
    pi_cl_dma_cmd_wait(&cmd);

    // --- START TIMER ---
    pi_perf_conf(1 << PI_PERF_CYCLES);
    pi_perf_reset();
    pi_perf_start();

    // --- RUN PARALLEL Q16 FFT ---

plp_cfft_balanced_q16_parallel(&plp_cfft_sR_q16_len4096, l1_buffer, 0, 1, 0, 8);

    // --- STOP TIMER ---
    pi_perf_stop();
    uint32_t cycles = pi_perf_read(PI_PERF_CYCLES);
    printf("[PAR] 8-Core Cycles: %d\n", cycles);

    // 3. DMA Copy: L1 -> L2 (Send Results back to Main RAM)
    pi_cl_dma_cmd((uint32_t)l2_buffer, (uint32_t)l1_buffer, size, PI_CL_DMA_DIR_LOC2EXT, &cmd);
    pi_cl_dma_cmd_wait(&cmd);

    // 4. Free L1 Memory
    pmsis_l1_malloc_free(l1_buffer, size);
}

int main()
{
    // Initialize Data 
    // We use a single impulse

    for (int i=0; i<2*N_FFT; i++) {
        Input_L2[i] = 0;
    }
    Input_L2[0] = 32767;; 

    struct pi_device cluster_dev;
    struct pi_cluster_conf conf;
    pi_cluster_conf_init(&conf);
    pi_open_from_conf(&cluster_dev, &conf);
    
    if (pi_cluster_open(&cluster_dev)) return -1;

    struct pi_cluster_task task;
    pi_cluster_task(&task, cluster_main, (void *)Input_L2);
    task.stack_size = 1000; 
    printf("[FC] Offloading Parallel Q16 FFT N=%d...\n", N_FFT);
    pi_cluster_send_task_to_cl(&cluster_dev, &task);
    pi_cluster_close(&cluster_dev);

    // --- PRINT RESULTS ---
    printf("\n[FC] Results (First 10 Bins):\n");
    printf("Bin |    Real    |    Imag    \n");
    printf("----|------------|------------\n");
    
    for (int i = 0; i < 10; i++) {
        printf("%3d | %10d | %10d\n", i, Input_L2[2*i], Input_L2[2*i+1]);
    }
    

    int16_t expected_val = 7;
    
    if (Input_L2[0] == expected_val) {
        printf("\n[SUCCESS] DC Component matches expected scaled value (%d).\n", expected_val);
    } else {
        printf("\n[CHECK] DC Component %d (Expected %d)\n", Input_L2[0], expected_val);
    }

    return 0;
}
