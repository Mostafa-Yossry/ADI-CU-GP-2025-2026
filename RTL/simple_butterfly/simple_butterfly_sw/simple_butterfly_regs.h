// Generated register defines for simple_butterfly

#ifndef _SIMPLE_BUTTERFLY_REG_DEFS_
#define _SIMPLE_BUTTERFLY_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define SIMPLE_BUTTERFLY_PARAM_REG_WIDTH 32

// Twiddle Index (11 bits).
#define SIMPLE_BUTTERFLY_TWIDDLE_REG_OFFSET 0x0
#define SIMPLE_BUTTERFLY_TWIDDLE_IDX_MASK 0x7ff
#define SIMPLE_BUTTERFLY_TWIDDLE_IDX_OFFSET 0
#define SIMPLE_BUTTERFLY_TWIDDLE_IDX_FIELD \
  ((bitfield_field32_t) { .mask = SIMPLE_BUTTERFLY_TWIDDLE_IDX_MASK, .index = SIMPLE_BUTTERFLY_TWIDDLE_IDX_OFFSET })

// Left operand (24 bits total).
#define SIMPLE_BUTTERFLY_OP_LEFT_REG_OFFSET 0x4
#define SIMPLE_BUTTERFLY_OP_LEFT_VAL_MASK 0xffffff
#define SIMPLE_BUTTERFLY_OP_LEFT_VAL_OFFSET 0
#define SIMPLE_BUTTERFLY_OP_LEFT_VAL_FIELD \
  ((bitfield_field32_t) { .mask = SIMPLE_BUTTERFLY_OP_LEFT_VAL_MASK, .index = SIMPLE_BUTTERFLY_OP_LEFT_VAL_OFFSET })

// Right operand (24 bits total). Writing to this register Auto-Triggers the
// pipeline.
#define SIMPLE_BUTTERFLY_OP_RIGHT_REG_OFFSET 0x8
#define SIMPLE_BUTTERFLY_OP_RIGHT_VAL_MASK 0xffffff
#define SIMPLE_BUTTERFLY_OP_RIGHT_VAL_OFFSET 0
#define SIMPLE_BUTTERFLY_OP_RIGHT_VAL_FIELD \
  ((bitfield_field32_t) { .mask = SIMPLE_BUTTERFLY_OP_RIGHT_VAL_MASK, .index = SIMPLE_BUTTERFLY_OP_RIGHT_VAL_OFFSET })

// Status register to check if computation is done.
#define SIMPLE_BUTTERFLY_STATUS_REG_OFFSET 0xc
#define SIMPLE_BUTTERFLY_STATUS_DONE_BIT 0

// Left output result (24 bits total).
#define SIMPLE_BUTTERFLY_RESULT_LEFT_REG_OFFSET 0x10
#define SIMPLE_BUTTERFLY_RESULT_LEFT_VAL_MASK 0xffffff
#define SIMPLE_BUTTERFLY_RESULT_LEFT_VAL_OFFSET 0
#define SIMPLE_BUTTERFLY_RESULT_LEFT_VAL_FIELD \
  ((bitfield_field32_t) { .mask = SIMPLE_BUTTERFLY_RESULT_LEFT_VAL_MASK, .index = SIMPLE_BUTTERFLY_RESULT_LEFT_VAL_OFFSET })

// Right output result (24 bits total).
#define SIMPLE_BUTTERFLY_RESULT_RIGHT_REG_OFFSET 0x14
#define SIMPLE_BUTTERFLY_RESULT_RIGHT_VAL_MASK 0xffffff
#define SIMPLE_BUTTERFLY_RESULT_RIGHT_VAL_OFFSET 0
#define SIMPLE_BUTTERFLY_RESULT_RIGHT_VAL_FIELD \
  ((bitfield_field32_t) { .mask = SIMPLE_BUTTERFLY_RESULT_RIGHT_VAL_MASK, .index = SIMPLE_BUTTERFLY_RESULT_RIGHT_VAL_OFFSET })

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _SIMPLE_BUTTERFLY_REG_DEFS_
// End generated register defines for simple_butterfly