// ============================================================================
// Module: bimpy
// ============================================================================
// Purpose:
//   Implements a highly optimized 2×N-bit multiplier.
//
// Design Motivation:
//   Modern FPGA LUTs (especially Xilinx 6-input LUTs) allow efficient mapping
//   of small multipliers. A full generic multiplier would:
//
//      • Consume more LUTs
//      • Increase combinational delay
//      • Require larger carry propagation
//
//   Instead, this design:
//
//      • Fixes operand A width = 2 bits
//      • Decomposes addition into XOR + AND logic
//      • Uses carry-chain only for final accumulation
//
// Result:
//   Low-area, high-speed portable multiplier.
//
// Mathematical Operation:
//
//      o_r = i_a × i_b
//
//   Since i_a is 2 bits:
//
//      i_a ∈ {0, 1, 2, 3}
//
//      i_a × i_b = (i_a[1] × i_b << 1) + (i_a[0] × i_b)
// ============================================================================

`default_nettype none

module bimpy #(
    // ------------------------------------------------------------------------
    // Parameterization
    // ------------------------------------------------------------------------
    parameter  BW   = 18, // Width of multiplicand (Input B)
    localparam LUTB = 2   // Width of multiplier (Input A) — fixed at 2 bits
)(
    // ------------------------------------------------------------------------
    // Ports
    // ------------------------------------------------------------------------
    input  wire                 i_clk,
    input  wire                 i_reset,
    input  wire                 i_clk_enable,

    input  wire [(LUTB-1):0]    i_a, // 2-bit multiplier
    input  wire [(BW-1):0]      i_b, // N-bit multiplicand

    output reg  [(BW+LUTB-1):0] o_r  // Product output (BW + 2 bits)
);

    // ========================================================================
    // 1. COMBINATORIAL LOGIC (Partial Sum & Carry Generation)
    // ========================================================================
    //
    // We compute:
    //
    //      (i_a[1] × i_b << 1) + (i_a[0] × i_b)
    //
    // Instead of a full adder:
    //
    //      Sum   → XOR
    //      Carry → AND
    //
    // This minimizes LUT depth and improves timing.
    //

    // ------------------------------------------------------------------------
    // Partial Sum (XOR Logic)
    // ------------------------------------------------------------------------
    //
    // w_r represents the preliminary addition result WITHOUT carry propagation.
    //
    // Term 1:
    //      If i_a[1] == 1 → i_b shifted left by 1
    //
    // Term 2:
    //      If i_a[0] == 1 → i_b (no shift)
    //

    wire [(BW+LUTB-2):0] w_r;

    assign w_r =
          { ((i_a[1]) ? i_b : {(BW){1'b0}}), 1'b0 }   // (i_a[1] × i_b) << 1
        ^ { 1'b0, ((i_a[0]) ? i_b : {(BW){1'b0}}) };  // (i_a[0] × i_b)

    // ------------------------------------------------------------------------
    // Carry Generation (AND Logic)
    // ------------------------------------------------------------------------
    //
    // Carry bits occur where BOTH terms contain a '1'.
    //
    // Carry = Term1 AND Term2
    //
    // Index alignment ensures overlapping bit positions are checked.
    //

    wire [(BW+LUTB-3):1] c;

    assign c =
          { ((i_a[1]) ? i_b[(BW-2):0] : {(BW-1){1'b0}}) }
        & { ((i_a[0]) ? i_b[(BW-1):1] : {(BW-1){1'b0}}) };

    // ========================================================================
    // 2. REGISTERED OUTPUT (Final Accumulation)
    // ========================================================================
    //
    // Final addition performed using FPGA carry chains:
    //
    //      o_r = w_r + shifted(c)
    //
    // Why shift carries by 2 bits?
    //
    //      Carry from bit N contributes to bit N+1
    //      LUTB=2 grouping → requires 2-bit alignment
    //

    always @(posedge i_clk)
        if (i_reset)
            o_r <= 0;
        else if (i_clk_enable)
            o_r <= w_r + { c, 2'b0 };

endmodule
