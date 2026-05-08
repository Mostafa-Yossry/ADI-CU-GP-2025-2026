// =============================================================================
// input_widen.sv
// -----------------------------------------------------------------------------
// Input Widening : Q1.11 (12-bit)  →  Q1.15 (16-bit)
//
// PURPOSE:
//   The system I/O boundary uses 12-bit Q1.11 words.
//   Block 2 (Matched Filter) needs 16-bit Q1.15 inputs to achieve the SQNR
//   headroom (min=65.5 dB, mean=72.2 dB) shown in the modelling results.
//
// HOW IT WORKS:
//   Zero-extension on the LSB side.  We append (WL_OUT - WL_IN) zero bits
//   at the right, keeping the binary point in exactly the same position.
//
//   12-bit Q1.11 word:   S  I  .  f10 f9 f8 f7 f6 f5 f4 f3 f2 f1 f0
//   16-bit Q1.15 word:   S  I  .  f10 f9 f8 f7 f6 f5 f4 f3 f2 f1 f0  0  0  0  0
//                                                                       ^^^^^^^^^^^
//                                                                       4 zero LSBs appended
//
//   No rounding, no information loss — purely combinational wiring.
//   Zero logic cells consumed after synthesis.
//
// MODELLING NOTE [Note 1]:
//   "The 12-bit Q1.11 inputs are widened to 16-bit Q1.15 by appending 4 zero
//    LSBs.  This is a zero-extension on the LSB side, not rounding — no
//    information loss."
//
// PARAMETERS:
//   WL_IN   : input  word length  (default 12)
//   WL_OUT  : output word length  (default 16)
//
// PORTS:
//   in_word  : narrow input  [WL_IN-1:0]  signed
//   out_word : wide output   [WL_OUT-1:0] signed
// =============================================================================

module input_widen #(
    parameter WL_IN  = 12,
    parameter WL_OUT = 16
)(
    input  wire signed [WL_IN-1:0]  in_word,
    output wire signed [WL_OUT-1:0] out_word
);

localparam ZERO_PAD = WL_OUT - WL_IN;

// Concatenate: original bits at the MSB side, zeros at the LSB side.
// Pure wiring — no logic cells consumed.
assign out_word = { in_word, {ZERO_PAD{1'b0}} };

endmodule