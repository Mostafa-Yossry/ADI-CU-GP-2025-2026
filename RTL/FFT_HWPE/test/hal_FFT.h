/*
 * Copyright (C) 2020 ETH Zurich and University of Bologna
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Authors:  Francesco Conti <f.conti@unibo.it>
 */

#include <stdio.h>

#ifndef __HAL_FFT_H__
#define __HAL_FFT_H__

/* REGISTER MAP */

// global address map + event IDs
#define FFT_ADDR_BASE      0x00201000
#define CLUS_CTRL_ADDR_BASE      0x00200000
#define FFT_EVT0           12
#define FFT_EVT1           13

// commands
#define FFT_COMMIT_AND_TRIGGER 0x00
#define FFT_ACQUIRE            0x04
#define FFT_FINISHED           0x08
#define FFT_STATUS             0x0c
#define FFT_RUNNING_JOB        0x10
#define FFT_SOFT_CLEAR         0x14
#define FFT_SWSYNC             0x18
#define FFT_URISCY_IMEM        0x1c

// job configuration
#define FFT_REGISTER_OFFS         0x40
#define FFT_REGISTER_CXT0_OFFS    0x80
#define FFT_REGISTER_CXT1_OFFS    0x120
#define FFT_REG_IN_OUT_PTR        0x00
#define FFT_REG_TOT_LEN           0x04
#define FFT_REG_IN_OUT_D0_LEN     0x08
#define FFT_REG_IN_OUT_D0_STRIDE  0x0c

// cluster controller register offset and bits
#define CLUS_CTRL_FFT_OFFS              0x18
#define CLUS_CTRL_FFT_CG_EN_MASK        0x800
#define CLUS_CTRL_FFT_HCI_PRIO_MASK     0x100
#define CLUS_CTRL_FFT_HCI_MAXSTALL_MASK 0xff

// others
#define FFT_COMMIT_CMD  1
#define FFT_TRIGGER_CMD 0
#define FFT_SOFT_CLEAR_ALL   0
#define FFT_SOFT_CLEAR_STATE 1

/* LOW-LEVEL HAL */
// For all the following functions we use __builtin_pulp_OffsetedWrite and __builtin_pulp_OffsetedRead
// instead of classic load/store because otherwise the compiler is not able to correctly factorize
// the FFT base in case several accesses are done, ending up with twice more code
#if defined(__riscv__) && !defined(RV_ISA_RV32)
  #define FFT_WRITE_CMD(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(FFT_ADDR_BASE), offset)
  #define FFT_WRITE_CMD_BE(offset, value, be) *(char volatile *)(FFT_ADDR_BASE + offset + be) = value
  // #define FFT_READ_CMD(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(FFT_ADDR_BASE), offset))
  #define FFT_READ_CMD(ret, offset)           ret = (*(int volatile *)(FFT_ADDR_BASE + offset))

  #define FFT_WRITE_REG(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_OFFS), offset)
  #define FFT_WRITE_REG_BE(offset, value, be) *(char volatile *)(FFT_ADDR_BASE + FFT_REGISTER_OFFS + offset + be) = value
  // #define FFT_READ_REG(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_OFFS), offset))
  #define FFT_READ_REG(ret, offset)           ret = (*(int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_OFFS + offset))

  #define FFT_WRITE_REG_CXT0(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT0_OFFS), offset)
  #define FFT_WRITE_REG_CXT0_BE(offset, value, be) *(char volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT0_OFFS + offset + be) = value
  #define FFT_READ_REG_CXT0(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT0_OFFS), offset))

  #define FFT_WRITE_REG_CXT1(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT1_OFFS), offset)
  #define FFT_WRITE_REG_CXT1_BE(offset, value, be) *(char volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT1_OFFS + offset + be) = value
  #define FFT_READ_REG_CXT1(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT1_OFFS), offset))
#else
  #define FFT_WRITE_CMD(offset, value)        *(int volatile *)(FFT_ADDR_BASE + offset) = value
  #define FFT_WRITE_CMD_BE(offset, value, be) *(char volatile *)(FFT_ADDR_BASE + offset + be) = value
  #define FFT_READ_CMD(ret, offset)           ret = (*(int volatile *)(FFT_ADDR_BASE + offset))

  #define FFT_WRITE_REG(offset, value)        *(int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_OFFS + offset) = value
  #define FFT_WRITE_REG_BE(offset, value, be) *(char volatile *)(FFT_ADDR_BASE + FFT_REGISTER_OFFS + offset + be) = value
  #define FFT_READ_REG(ret, offset)           ret = (*(int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_OFFS + offset))

  #define FFT_WRITE_REG_CXT0(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT0_OFFS), offset)
  #define FFT_WRITE_REG_CXT0_BE(offset, value, be) *(char volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT0_OFFS + offset + be) = value
  #define FFT_READ_REG_CXT0(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT0_OFFS), offset))

  #define FFT_WRITE_REG_CXT1(offset, value)        __builtin_pulp_OffsetedWrite(value, (int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT1_OFFS), offset)
  #define FFT_WRITE_REG_CXT1_BE(offset, value, be) *(char volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT1_OFFS + offset + be) = value
  #define FFT_READ_REG_CXT1(offset)                (__builtin_pulp_OffsetedRead(*(int volatile *)(FFT_ADDR_BASE + FFT_REGISTER_CXT1_OFFS), offset))
#endif

#define FFT_CG_ENABLE()  *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_FFT_OFFS) |=  CLUS_CTRL_FFT_CG_EN_MASK
#define FFT_CG_DISABLE() *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_FFT_OFFS) &= ~CLUS_CTRL_FFT_CG_EN_MASK

#define FFT_SETPRIORITY_CORE() *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_FFT_OFFS) &= ~CLUS_CTRL_FFT_HCI_PRIO_MASK
#define FFT_SETPRIORITY_FFT() *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_FFT_OFFS) |=  CLUS_CTRL_FFT_HCI_PRIO_MASK

#define FFT_RESET_MAXSTALL()  *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_FFT_OFFS) &= ~CLUS_CTRL_FFT_HCI_MAXSTALL_MASK
#define FFT_SET_MAXSTALL(val) *(volatile int*) (CLUS_CTRL_ADDR_BASE + CLUS_CTRL_FFT_OFFS) |=  (val & CLUS_CTRL_FFT_HCI_MAXSTALL_MASK)

#define FFT_BARRIER_NOSTATUS()      eu_evt_maskWaitAndClr (1 << FFT_EVT0)
#define FFT_BARRIER()               do { eu_evt_maskWaitAndClr (1 << FFT_EVT0); } while((*(int volatile *)(FFT_ADDR_BASE + FFT_STATUS)) != 0)
#define FFT_BUSYWAIT()              do {                                         } while((*(int volatile *)(FFT_ADDR_BASE + FFT_STATUS)) != 0)
#define FFT_BARRIER_ACQUIRE(job_id) job_id = FFT_READ_CMD(job_id, FFT_ACQUIRE); \
                                     while(job_id < 0) { eu_evt_maskWaitAndClr (1 << FFT_EVT0); FFT_READ_CMD(job_id, FFT_ACQUIRE); };

/* UTILITY FUNCTIONS */
int FFT_compare_int(uint32_t *actual_y, uint32_t *golden_y, int len) {
  uint32_t actual_word = 0;
  uint32_t golden_word = 0;
  uint32_t actual = 0;
  uint32_t golden = 0;

  int errors = 0;
  int non_zero_values = 0;

  for (int i=0; i<len; i++) {
    actual_word = *(actual_y+i);
    golden_word = *(golden_y+i);

    int error = (int) (actual_word != golden_word);
    errors += (int) (actual_word != golden_word);
#ifndef NVERBOSE
    if(error) {
      if(errors==1) printf("  golden     <- actual     @ address    @ index\n");
      printf("  0x%08x <- 0x%08x @ 0x%08x @ 0x%08x\n", golden_word, actual_word, (actual_y+i), i*4);
    }
#endif /* NVERBOSE */
  }
  return errors;
}

#endif /* __HAL_FFT_H__ */
