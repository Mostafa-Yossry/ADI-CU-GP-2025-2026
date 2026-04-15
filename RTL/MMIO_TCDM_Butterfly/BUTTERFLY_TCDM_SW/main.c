#include <stdio.h>
#include "pulp.h"
#include "DMA_butterfly_driver.h" // Using your prefixed header

int main() {
    printf("Hello World!\n"); 
    
    // Set test operands
    uint32_t op_left = 0x000A0005;  // Example complex number
    uint32_t op_right = 0x00020001; // Example complex number
    uint32_t twiddle_idx = 0;
    
    uint32_t res_left = 0;
    uint32_t res_right = 0;

    printf("Starting DMA_Butterfly computation...\n");

    // Execute hardware-accelerated computation
    int status = butterfly_compute(twiddle_idx, op_left, op_right, &res_left, &res_right);

    // Output result to UART
    if (status == 0) {
        printf("Computation Successful!\n");
        printf("Result Left:  0x%08X\n", res_left);
        printf("Result Right: 0x%08X\n", res_right);
    } else {
        printf("Computation Failed with status: %d\n", status);
    }

    return 0; 
}
