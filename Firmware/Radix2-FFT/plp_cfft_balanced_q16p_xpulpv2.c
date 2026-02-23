/* =====================================================================
 * Project:      Radix-2 FFT
 * Title:        plp_cfft_radix2_q16s_xpulpv2.c 
 * ===================================================================== */
/* Author: Mostafa Yossry
 */


#include "plp_math.h"
#include "pmsis.h" 
#include <stdio.h>

#define MAX(x, y) (((x) > (y)) ? (x) : (y))
#define MIN(x, y) (((x) < (y)) ? (x) : (y))

// 1. THE ISOLATED BUTTERFLY FUNCTION
void single_radix2_butterfly(v2s *pSrcA, v2s *pSrcB, v2s CoSi) {
    v2s a = *pSrcA;
    v2s b = *pSrcB;

    a = __SRA2(a, ((v2s){ 1, 1 }));
    b = __SRA2(b, ((v2s){ 1, 1 }));

    v2s t = __SUB2(a, b);
    *pSrcA = __ADD2(a, b);

    int16_t testa = (int16_t)(__DOTP2(t, CoSi) >> 15U);
    int16_t testb = (int16_t)(__DOTP2(t, __PACK2(-CoSi[1], CoSi[0])) >> 15U);

    *pSrcB = __PACK2(testa, testb);
}


static void plp_radix2_butterfly_q16(int16_t *pSrc16, uint32_t fftLen, int16_t *pCoef16, uint32_t twidCoefModifier, uint32_t nPE) {
    int core_id = hal_core_id(); 
    uint32_t n1, n2, ic, i0, i1, j, k;
    uint32_t step;

    hal_team_barrier();

    n2 = fftLen;
    n1 = n2;
    n2 >>= 1U;

    for (k = fftLen; k > 2U; k >>= 1U) {
        hal_team_barrier();

        if (n2 % nPE == 0) step = n2 / nPE;
        else step = n2 / nPE + 1;

        uint32_t safe_core_idx = core_id % nPE;
        uint32_t start_j = safe_core_idx * step;
        uint32_t end_j = MIN(start_j + step, n2);

        for (j = start_j; j < end_j; j++) {
            ic = twidCoefModifier * j;

            int16_t tw_real = pCoef16[ic * 2U];
            int16_t tw_imag = pCoef16[ic * 2U + 1U];
            v2s CoSi = __PACK2(tw_real, tw_imag);

            for (i0 = j; i0 < fftLen; i0 += n1) {
                i1 = i0 + n2;

                // --- HARDWARE CYCLE PROFILER ---
                // We only profile the very first butterfly on Core 0 to avoid console spam
              /*  if (core_id == 0 && k == fftLen && i0 == 0) {
                    pi_perf_conf(1 << PI_PERF_CYCLES);
                    pi_perf_reset();
                    pi_perf_start();
                } */

                // Call the isolated math function
                single_radix2_butterfly((v2s *)&pSrc16[i0 * 2U], (v2s *)&pSrc16[i1 * 2U], CoSi);

        /*        // Stop profiler and print
                if (core_id == 0 && k == fftLen && i0 == 0) {
                    pi_perf_stop();
                    uint32_t b_cycles = pi_perf_read(PI_PERF_CYCLES);
                    printf("\n 1 Butterfly executed in: %d clock cycles\n\n", b_cycles);
                } */
             }
        } 
        
        twidCoefModifier <<= 1U;
        n1 = n2;
        n2 >>= 1U;
        
        hal_team_barrier();
    }

    // --- Final Stage (Size 2) ---
    uint32_t steps = fftLen / 2U;
    if (steps % nPE == 0) step = steps / nPE;
    else step = steps / nPE + 1;

    uint32_t safe_core_idx = core_id % nPE;
    uint32_t start_i0 = safe_core_idx * step * 2U;
    uint32_t end_i0 = MIN((safe_core_idx * step + step) * 2U, fftLen);

    for (i0 = start_i0; i0 < end_i0; i0 += 2U) {
        i1 = i0 + 1U;
        v2s a = *(v2s *)&pSrc16[i0 * 2U];
        v2s b = *(v2s *)&pSrc16[i1 * 2U];

        a = __SRA2(a, ((v2s){ 1, 1 }));
        b = __SRA2(b, ((v2s){ 1, 1 }));

        *((v2s *)&pSrc16[i0 * 2U]) = __ADD2(a, b);
        *((v2s *)&pSrc16[i1 * 2U]) = __SUB2(a, b);
    }
}

void plp_cfft_radix2_q16p_xpulpv2(void *args) {
    plp_cfft_instance_q16_parallel *a = (plp_cfft_instance_q16_parallel *) args;
    uint32_t L = a->S->fftLen;

    if (a->ifftFlag == 0) {
        plp_radix2_butterfly_q16(a->p1, L, (int16_t *)a->S->pTwiddle, 1, a->nPE);
    }
    hal_team_barrier();
    if (a->bitReverseFlag) {
        plp_bitreversal_16p_xpulpv2((uint16_t *)a->p1, a->S->bitRevLength, a->S->pBitRevTable, a->nPE);
    }
}
