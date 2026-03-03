// Generated register defines for butterfly

#ifndef _BUTTERFLY_REG_DEFS_
#define _BUTTERFLY_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define BUTTERFLY_PARAM_REG_WIDTH 32

// Twiddle factor (46 bits total). COEF_0 holds [31:0], COEF_1 holds [45:32].
// (common parameters)
#define BUTTERFLY_COEF_COEF_FIELD_WIDTH 32
#define BUTTERFLY_COEF_COEF_FIELDS_PER_REG 1
#define BUTTERFLY_COEF_MULTIREG_COUNT 2

// Twiddle factor (46 bits total). COEF_0 holds [31:0], COEF_1 holds [45:32].
#define BUTTERFLY_COEF_0_REG_OFFSET 0x0

// Twiddle factor (46 bits total). COEF_0 holds [31:0], COEF_1 holds [45:32].
#define BUTTERFLY_COEF_1_REG_OFFSET 0x4

// Left operand (38 bits total). OP_LEFT_0 holds [31:0], OP_LEFT_1 holds
// [37:32]. (common parameters)
#define BUTTERFLY_OP_LEFT_OP_LEFT_FIELD_WIDTH 32
#define BUTTERFLY_OP_LEFT_OP_LEFT_FIELDS_PER_REG 1
#define BUTTERFLY_OP_LEFT_MULTIREG_COUNT 2

// Left operand (38 bits total). OP_LEFT_0 holds [31:0], OP_LEFT_1 holds
// [37:32].
#define BUTTERFLY_OP_LEFT_0_REG_OFFSET 0x8

// Left operand (38 bits total). OP_LEFT_0 holds [31:0], OP_LEFT_1 holds
// [37:32].
#define BUTTERFLY_OP_LEFT_1_REG_OFFSET 0xc

// Right operand (38 bits total). OP_RIGHT_0 holds [31:0], OP_RIGHT_1 holds
// [37:32]. (common parameters)
#define BUTTERFLY_OP_RIGHT_OP_RIGHT_FIELD_WIDTH 32
#define BUTTERFLY_OP_RIGHT_OP_RIGHT_FIELDS_PER_REG 1
#define BUTTERFLY_OP_RIGHT_MULTIREG_COUNT 2

// Right operand (38 bits total). OP_RIGHT_0 holds [31:0], OP_RIGHT_1 holds
// [37:32].
#define BUTTERFLY_OP_RIGHT_0_REG_OFFSET 0x10

// Right operand (38 bits total). OP_RIGHT_0 holds [31:0], OP_RIGHT_1 holds
// [37:32].
#define BUTTERFLY_OP_RIGHT_1_REG_OFFSET 0x14

// Control register for triggering the pipeline and clock enable.
#define BUTTERFLY_CTRL_REG_OFFSET 0x18
#define BUTTERFLY_CTRL_TRIGGER_BIT 0
#define BUTTERFLY_CTRL_ENABLE_BIT 1

// Status register to check if computation is done (o_aux).
#define BUTTERFLY_STATUS_REG_OFFSET 0x1c
#define BUTTERFLY_STATUS_DONE_BIT 0

// Left output result (38 bits total). (common parameters)
#define BUTTERFLY_RESULT_LEFT_RESULT_LEFT_FIELD_WIDTH 32
#define BUTTERFLY_RESULT_LEFT_RESULT_LEFT_FIELDS_PER_REG 1
#define BUTTERFLY_RESULT_LEFT_MULTIREG_COUNT 2

// Left output result (38 bits total).
#define BUTTERFLY_RESULT_LEFT_0_REG_OFFSET 0x20

// Left output result (38 bits total).
#define BUTTERFLY_RESULT_LEFT_1_REG_OFFSET 0x24

// Right output result (38 bits total). (common parameters)
#define BUTTERFLY_RESULT_RIGHT_RESULT_RIGHT_FIELD_WIDTH 32
#define BUTTERFLY_RESULT_RIGHT_RESULT_RIGHT_FIELDS_PER_REG 1
#define BUTTERFLY_RESULT_RIGHT_MULTIREG_COUNT 2

// Right output result (38 bits total).
#define BUTTERFLY_RESULT_RIGHT_0_REG_OFFSET 0x28

// Right output result (38 bits total).
#define BUTTERFLY_RESULT_RIGHT_1_REG_OFFSET 0x2c

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _BUTTERFLY_REG_DEFS_
// End generated register defines for butterfly