#include <stdio.h>
#include "pulp.h"
#include "DMA_butterfly_driver.h"

// 1. Changed return type to 'int' to satisfy the compiler
int cluster_dma_task(void) {
    // 2. Used the correct bare-metal HAL function
    if (hal_core_id() != 0) {
        return 0; // Cores 1-7 immediately return and go back to sleep
    }

    printf("[CLUSTER-PE0] Execution successfully moved to Cluster Core Master!\n");

    uint32_t op_left_buf[1]   = { 0x000A0005 }; // 10 + 5i
    uint32_t op_right_buf[1]  = { 0x00020001 }; // 2 + 1i
    volatile uint32_t res_left_buf[1]  = { 0xDEADBEEF }; 
    volatile uint32_t res_right_buf[1] = { 0xDEADBEEF }; 

    uint32_t twiddle_idx = 0;
    uint32_t transfer_size_bytes = 4; 

    printf("[CLUSTER-PE0] DMA Source Addr (Left):  0x%08X\n", (uint32_t)op_left_buf);

    int status = butterfly_dma_compute(
        twiddle_idx, 
        op_left_buf, 
        op_right_buf, 
        (uint32_t*)res_left_buf, 
        (uint32_t*)res_right_buf, 
        transfer_size_bytes
    );

    if (status == 0) {
        printf("\n========================================\n");
        printf(" DMA Computation Successful!\n");
        printf(" Result Left Array:  0x%08X\n", res_left_buf[0]);
        printf(" Result Right Array: 0x%08X\n", res_right_buf[0]);
        printf("========================================\n");
    } else {
        printf("[CLUSTER-PE0] ERROR: Computation Failed.\n");
    }

    return 0; // Master core finishes and returns
}

int main() {
    printf("========================================\n");
    printf(" Starting CLUSTER DMA Butterfly Test\n");
    printf("========================================\n");

    printf("[MAIN] Powering on and dispatching task to Cluster 0...\n");
    
    cluster_start(0, cluster_dma_task);
    cluster_wait(0);

    printf("[MAIN] Task complete. Cluster powered down.\n");

    return 0;
}
