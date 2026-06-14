// Generated register defines for radix8_butterfly

#ifndef _RADIX8_BUTTERFLY_REG_DEFS_
#define _RADIX8_BUTTERFLY_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define RADIX8_BUTTERFLY_PARAM_REG_WIDTH 32

// Control register
#define RADIX8_BUTTERFLY_CTRL_REG_OFFSET 0x0
#define RADIX8_BUTTERFLY_CTRL_TRIGGER_BIT 0
#define RADIX8_BUTTERFLY_CTRL_CLEAR_BIT 1
#define RADIX8_BUTTERFLY_CTRL_CLK_EN_BIT 2

// Status register
#define RADIX8_BUTTERFLY_STATUS_REG_OFFSET 0x4
#define RADIX8_BUTTERFLY_STATUS_DONE_BIT 0

// Twiddle factor index
#define RADIX8_BUTTERFLY_TWIDDLE_REG_OFFSET 0x8
#define RADIX8_BUTTERFLY_TWIDDLE_IDX_MASK 0x1ff
#define RADIX8_BUTTERFLY_TWIDDLE_IDX_OFFSET 0
#define RADIX8_BUTTERFLY_TWIDDLE_IDX_FIELD \
  ((bitfield_field32_t) { .mask = RADIX8_BUTTERFLY_TWIDDLE_IDX_MASK, .index = RADIX8_BUTTERFLY_TWIDDLE_IDX_OFFSET })

// Input data 0 (i_data0)
#define RADIX8_BUTTERFLY_DATA0_REG_OFFSET 0xc

// Input data 1 (i_data1)
#define RADIX8_BUTTERFLY_DATA1_REG_OFFSET 0x10

// Input data 2 (i_data2)
#define RADIX8_BUTTERFLY_DATA2_REG_OFFSET 0x14

// Input data 3 (i_data3)
#define RADIX8_BUTTERFLY_DATA3_REG_OFFSET 0x18

// Input data 4 (i_data4)
#define RADIX8_BUTTERFLY_DATA4_REG_OFFSET 0x1c

// Input data 5 (i_data5)
#define RADIX8_BUTTERFLY_DATA5_REG_OFFSET 0x20

// Input data 6 (i_data6)
#define RADIX8_BUTTERFLY_DATA6_REG_OFFSET 0x24

// Input data 7 (i_data7) - Write triggers hardware execution
#define RADIX8_BUTTERFLY_DATA7_REG_OFFSET 0x28

// Output data 0 (o_data0)
#define RADIX8_BUTTERFLY_OUT0_REG_OFFSET 0x2c

// Output data 1 (o_data1)
#define RADIX8_BUTTERFLY_OUT1_REG_OFFSET 0x30

// Output data 2 (o_data2)
#define RADIX8_BUTTERFLY_OUT2_REG_OFFSET 0x34

// Output data 3 (o_data3)
#define RADIX8_BUTTERFLY_OUT3_REG_OFFSET 0x38

// Output data 4 (o_data4)
#define RADIX8_BUTTERFLY_OUT4_REG_OFFSET 0x3c

// Output data 5 (o_data5)
#define RADIX8_BUTTERFLY_OUT5_REG_OFFSET 0x40

// Output data 6 (o_data6)
#define RADIX8_BUTTERFLY_OUT6_REG_OFFSET 0x44

// Output data 7 (o_data7)
#define RADIX8_BUTTERFLY_OUT7_REG_OFFSET 0x48

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _RADIX8_BUTTERFLY_REG_DEFS_
// End generated register defines for radix8_butterfly