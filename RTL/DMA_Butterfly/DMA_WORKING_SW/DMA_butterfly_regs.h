// Generated register defines for butterfly

#ifndef _BUTTERFLY_REG_DEFS_
#define _BUTTERFLY_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define BUTTERFLY_PARAM_REG_WIDTH 32

// Control register
#define BUTTERFLY_CTRL_REG_OFFSET 0x0
#define BUTTERFLY_CTRL_TRIGGER_BIT 0
#define BUTTERFLY_CTRL_CLEAR_BIT 1

// Status register
#define BUTTERFLY_STATUS_REG_OFFSET 0x4
#define BUTTERFLY_STATUS_DONE_BIT 0

// Twiddle factor index
#define BUTTERFLY_TWIDDLE_REG_OFFSET 0x8
#define BUTTERFLY_TWIDDLE_IDX_MASK 0x7ff
#define BUTTERFLY_TWIDDLE_IDX_OFFSET 0
#define BUTTERFLY_TWIDDLE_IDX_FIELD \
  ((bitfield_field32_t) { .mask = BUTTERFLY_TWIDDLE_IDX_MASK, .index = BUTTERFLY_TWIDDLE_IDX_OFFSET })

// Left operand
#define BUTTERFLY_OP_LEFT_REG_OFFSET 0xc
#define BUTTERFLY_OP_LEFT_DATA_MASK 0xffffff
#define BUTTERFLY_OP_LEFT_DATA_OFFSET 0
#define BUTTERFLY_OP_LEFT_DATA_FIELD \
  ((bitfield_field32_t) { .mask = BUTTERFLY_OP_LEFT_DATA_MASK, .index = BUTTERFLY_OP_LEFT_DATA_OFFSET })

// Right operand
#define BUTTERFLY_OP_RIGHT_REG_OFFSET 0x10
#define BUTTERFLY_OP_RIGHT_DATA_MASK 0xffffff
#define BUTTERFLY_OP_RIGHT_DATA_OFFSET 0
#define BUTTERFLY_OP_RIGHT_DATA_FIELD \
  ((bitfield_field32_t) { .mask = BUTTERFLY_OP_RIGHT_DATA_MASK, .index = BUTTERFLY_OP_RIGHT_DATA_OFFSET })

// Left result
#define BUTTERFLY_RES_LEFT_REG_OFFSET 0x14
#define BUTTERFLY_RES_LEFT_DATA_MASK 0xffffff
#define BUTTERFLY_RES_LEFT_DATA_OFFSET 0
#define BUTTERFLY_RES_LEFT_DATA_FIELD \
  ((bitfield_field32_t) { .mask = BUTTERFLY_RES_LEFT_DATA_MASK, .index = BUTTERFLY_RES_LEFT_DATA_OFFSET })

// Right result
#define BUTTERFLY_RES_RIGHT_REG_OFFSET 0x18
#define BUTTERFLY_RES_RIGHT_DATA_MASK 0xffffff
#define BUTTERFLY_RES_RIGHT_DATA_OFFSET 0
#define BUTTERFLY_RES_RIGHT_DATA_FIELD \
  ((bitfield_field32_t) { .mask = BUTTERFLY_RES_RIGHT_DATA_MASK, .index = BUTTERFLY_RES_RIGHT_DATA_OFFSET })

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _BUTTERFLY_REG_DEFS_
// End generated register defines for butterfly