/* =====================================================================
 * Project:      Radix-2 FFT
 * Title:        plp_cfft_balanced_q16.c
 * Description:  16-bit fixed point Balanced Tree Fast Fourier Transform
 *
 * Target Processor: PULP cores
 * ===================================================================== */
/* Author: Mostafa Yossry
 */

#include "plp_math.h"

/**
 * @ingroup groupTransforms
 */

/**
 * @addtogroup fft
 * @{
 */

/**
 * @brief  Glue code for parallel quantized 16-bit Balanced CFFT
 *
 * @param[in]     S               points to an instance of the 16bit quantized CFFT structure
 * @param[in,out] p1              points to the complex data buffer of size <code>2*fftLen</code>.
 * Processing occurs in-place.
 * @param[in]     ifftFlag        flag that selects forward (ifftFlag=0) or inverse (ifftFlag=1) transform.
 * @param[in]     bitReverseFlag  flag that enables (1) or disables (0) bit reversal of output.
 * @param[in]     deciPoint       decimal point for right shift
 * @param[in]     nPE             Number of cores to use
 */
void plp_cfft_balanced_q16_parallel(const plp_cfft_instance_q16 *S,
                                    int16_t *p1,
                                    uint8_t ifftFlag,
                                    uint8_t bitReverseFlag,
                                    uint32_t deciPoint,
                                    uint32_t nPE) {

    if (hal_cluster_id() == ARCHI_FC_CID) {
        printf("parallel processing supported only for cluster side\n");
        return;
    } else { 
        plp_cfft_instance_q16_parallel args = {
            .S = S, .p1 = p1, .ifftFlag = ifftFlag, .bitReverseFlag = bitReverseFlag, .deciPoint = deciPoint, .nPE = nPE
        };

        hal_cl_team_fork(nPE, plp_cfft_radix2_q16p_xpulpv2, (void *)&args);
    }
}

/**
 * @} end of FFT group
 */
