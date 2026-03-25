// Purpose:
//   Implements a portable pipelined multiplier using a shift-and-add method,
//   optimized for LUT + carry-chain architectures.
//
// Design Philosophy:
//
//   Instead of relying on DSP blocks, this multiplier:
//
//      • Uses logic fabric (LUTs)
//      • Exploits carry chains for fast accumulation
//      • Processes partial products in small chunks
//
// Key Optimization:
//
//   To minimize latency and hardware:
//
//      Ensure smaller operand → i_a
//      Ensure larger operand  → i_b
//
//   Because pipeline depth depends on width of first operand.
//
module longbimpy #(

    // ====================================================================
    // 1. CONFIGURATION & SIZING
    // ====================================================================

    parameter IAW = 8,   // Input width A
    parameter IBW = 12,  // Input width B
    // --------------------------------------------------------------------
    // Operand Reordering Optimization
    // --------------------------------------------------------------------
    //
    // Multiplication is commutative:
    //
    //      A × B = B × A
    //
    // However:
    //
    //      Pipeline depth ∝ width of first operand
    //
    // Therefore:
    //
    //      AW = min(IAW, IBW)
    //      BW = max(IAW, IBW)
    //

    localparam AW = (IAW < IBW) ? IAW : IBW,
    localparam BW = (IAW < IBW) ? IBW : IAW,
    // --------------------------------------------------------------------
    // Internal Width Adjustment (IW)
    // --------------------------------------------------------------------
    //
    // Multiplier processes 2 bits per stage (Radix-4 style grouping).
    //
    // Requirement:
    //      Operand width must be EVEN
    //
    // Operation:
    //      IW = round_up_to_even(AW)
    //
    // Logic:
    //      (AW + 1) & (-2)
    //

    localparam IW = (AW + 1) & (-2),
    // Bits processed per stage
    localparam LUTB = 2,
    // --------------------------------------------------------------------
    // Pipeline Stage Count (TLEN)
    // --------------------------------------------------------------------
    //
    // Each stage consumes LUTB (=2) bits of operand A.
    //
    // Total stages:
    //
    //      TLEN = ceil(AW / LUTB)
    //

    localparam TLEN = (AW + (LUTB - 1)) / LUTB
)(
    // ====================================================================
    // 2. PORTS
    // ====================================================================

    input  wire i_clk,
    input  wire i_clk_enable,

    // Unsorted inputs (external ordering)
    input  wire [(IAW-1):0] i_a_unsorted,
    input  wire [(IBW-1):0] i_b_unsorted,

    // Product output
    output reg [(AW+BW-1):0] o_r
);
    // ====================================================================
    // 3. INPUT SWAPPING (ROUTING OPTIMIZATION)
    // ====================================================================
    //
    // Ensures:
    //      i_a → smaller operand
    //      i_b → larger operand
    //
    // Benefits:
    //      • Minimal pipeline depth
    //      • Reduced hardware
    //

    wire [AW-1:0] i_a;
    wire [BW-1:0] i_b;
    generate
    begin : PARAM_CHECK

        if (IAW <= IBW)
        begin : NO_PARAM_CHANGE_I

            assign i_a = i_a_unsorted;
            assign i_b = i_b_unsorted;

        end else begin : SWAP_PARAMETERS_I

            assign i_a = i_b_unsorted;
            assign i_b = i_a_unsorted;

        end
    end
    endgenerate
    // ====================================================================
    // 4. INTERNAL REGISTERS
    // ====================================================================
    //
    // u_a, u_b:
    //   Unsigned (absolute value) versions of inputs
    //
    // sgn:
    //   Stores final result sign
    //

    reg [(IW-1):0] u_a;
    // Unsigned, width-normalized version of operand A
    // IW may be larger than AW if padding required

    reg [(BW-1):0] u_b;
    // Unsigned version of operand B (no padding required)

    reg sgn;
    // Final sign of product:
    //   sign(A) XOR sign(B)
    // --------------------------------------------------------------------
    // Pipeline Arrays ("Waterfall Architecture")
    // --------------------------------------------------------------------
    //
    // These arrays implement progressive partial-product accumulation.
    //
    // r_a:
    //   Carries remaining bits of operand A
    //
    // r_b:
    //   Carries operand B through pipeline
    //
    // r_s:
    //   Carries sign bit through pipeline
    //
    // acc:
    //   Accumulates partial sums at each stage
    //

    reg [(IW-1-2*(LUTB)):0] r_a[0:(TLEN-3)];
    reg [(BW-1):0]          r_b[0:(TLEN-3)];
    reg [(TLEN-1):0]        r_s;
    reg [(IW+BW-1):0]       acc[0:(TLEN-2)];
    genvar k;

    wire [(BW+LUTB-1):0] pr_a, pr_b;
    // Partial product helper signals

    wire [(IW+BW-1):0] w_r;
    // Accumulation result helper
    // ====================================================================
    // 5. SIGN CONVERSION (Stage 0 Setup)
    // ====================================================================
    //
    // Signed multiplication via shift-and-add is complex.
    //
    // Simplification Strategy:
    //
    //   1. Convert operands → Absolute values (unsigned)
    //   2. Perform unsigned multiplication
    //   3. Restore correct sign at output
    //
    generate begin : ABS
    if (IW > AW)
    begin : ABS_AND_ADD_BIT_TO_A
        // Case: Padding Needed (AW was odd).
        // We calculate the absolute value and pad the top bit with 0 
        // to make the total width even (IW).
        always @(posedge i_clk)
        if (i_clk_enable)
            // Ternary Op: If MSB is 1 (negative), negate i_a. Else keep i_a.
            u_a <= { 1'b0, (i_a[AW-1])?(-i_a):(i_a) };
            
    end else begin : ABS_A
        // Case: No Padding Needed (AW was even).
        always @(posedge i_clk)
        if (i_clk_enable)
            u_a <= (i_a[AW-1])?(-i_a):(i_a);
            
    end end endgenerate
// ====================================================================
    // 5. ABSOLUTE VALUE OF B & SIGN CALCULATION
    // ====================================================================
    // We convert input B to unsigned (absolute value) to simplify math.
    // We also calculate the final sign bit (A_sign XOR B_sign).
    
    always @(posedge i_clk)
    if (i_clk_enable)
    begin : ABS_B
        // Ternary Op: If B is negative (MSB=1), negate it. Else keep B.
        u_b <= (i_b[BW-1])?(-i_b):(i_b);
        
        // Sign Calculation: 
        // 0 ^ 0 = 0 (Pos * Pos = Pos)
        // 1 ^ 1 = 0 (Neg * Neg = Pos)
        // 1 ^ 0 = 1 (Neg * Pos = Neg)
        sgn <= i_a[AW-1] ^ i_b[BW-1];
    end
    // ====================================================================
    // 6. STAGE 1: PROCESSING THE FIRST 4 BITS OF OPERAND A
    // ====================================================================
    //
    // Key Optimization:
    //
    //   Normally:
    //      Each stage consumes LUTB (=2) bits of u_a
    //
    //   Special Case (First Stage):
    //
    //      No previous partial sum exists yet
    //
    //   Therefore:
    //
    //      Two 2-bit chunks can be processed in parallel
    //
    // Chunk Definitions:
    //
    //      Chunk 0 → u_a[1:0]
    //      Chunk 1 → u_a[3:2]
    //
    // Benefit:
    //
    //      • Reduces pipeline depth by one stage
    //      • Improves latency
    //      • Increases early parallelism
    // --------------------------------------------------------------------
    // Chunk 0 Multiplier (Least Significant Bits)
    // --------------------------------------------------------------------
    //
    // Computes:
    //
    //      PartialProduct_0 = u_b × u_a[1:0]
    //
    // bimpy:
    //      Specialized 2-bit × N-bit multiplier
    //

    bimpy #(
        .BW(BW)
    ) lmpy_0 (
        .i_clk(i_clk),
        .i_reset(1'b0),
        .i_clk_enable(i_clk_enable),

        .i_a(u_a[(LUTB-1):0]),   // u_a[1:0]
        .i_b(u_b),

        .o_r(pr_a)
    );
    // --------------------------------------------------------------------
    // Chunk 1 Multiplier (Next 2 Bits)
    // --------------------------------------------------------------------
    //
    // Computes:
    //
    //      PartialProduct_1 = u_b × u_a[3:2]
    //

    bimpy #(
        .BW(BW)
    ) lmpy_1 (
        .i_clk(i_clk),
        .i_reset(1'b0),
        .i_clk_enable(i_clk_enable),

        .i_a(u_a[(2*LUTB-1):LUTB]),  // u_a[3:2]
        .i_b(u_b),

        .o_r(pr_b)
    );
    // ====================================================================
    // 7. PIPELINE MANAGEMENT (Waterfall Propagation)
    // ====================================================================
    //
    // Purpose:
    //   Carry remaining operands and sign through pipeline stages
    //
    always @(posedge i_clk)
    if (i_clk_enable)
    begin
        // Remove consumed bits:
        //
        //   Bits [3:0] already processed
        //
        // Pass remaining bits downward
        //
        r_a[0] <= u_a[(IW-1):(2*LUTB)];
        // Operand B required at every stage
        //
        r_b[0] <= u_b;
        // Propagate sign through TLEN-stage shift register
        //
        r_s <= { r_s[(TLEN-2):0], sgn };
    end
    // ====================================================================
    // 8. ACCUMULATOR 0 (Initial Partial Sum Formation)
    // ====================================================================
    //
    // Timing Relationship:
    //
    //   pr_a, pr_b become valid AFTER bimpy pipeline latency
    //
    //   acc[0] computed one clock cycle later
    //
    // Mathematical Operation:
    //
    //   acc[0] = (u_b × u_a[1:0])
    //          + (u_b × u_a[3:2]) << LUTB
    //
    // Why shift pr_b?
    //
    //   pr_b corresponds to higher significance bits (u_a[3:2])
    //
    //   Must be left-shifted by LUTB (=2) bits

    // ====================================================================
    // 8. ACCUMULATOR 0 (Combining the first two products)
    // ====================================================================
    // This runs one clock cycle AFTER the multipliers (lmpy_0/1) finish.
    // It adds the two partial products together, shifting the second one
    // by 2 bits (LUTB) because it corresponds to u_a[3:2].
    
    always @(posedge i_clk) // One clk after p[0],p[1] become valid
    if (i_clk_enable)
        acc[0] <= { {(IW-LUTB){1'b0}}, pr_a }          // Product A (No shift)
                + { {(IW-(2*LUTB)){1'b0}}, pr_b, {(LUTB){1'b0}} }; // Product B (Shift left 2)

// ====================================================================
    // 9. PIPELINE DATA PROPAGATION (The "Waterfall")
    // ====================================================================
    // As we move down the pipeline, we need to carry the operands with us.
    // r_b: The multiplicand (stays the same, just copied down).
    // r_a: The multiplier (gets shifted/consumed as we go).

    generate begin : COPY
    if (TLEN > 3) begin : FOR
        // Loop through the remaining stages of the pipeline
        for(k=0; k<TLEN-3; k=k+1)
        begin : GENCOPIES

            initial r_a[k+1] = 0;
            initial r_b[k+1] = 0;
            
            always @(posedge i_clk)
            if (i_clk_enable)
            begin
                // Shift r_a right by 2 bits (LUTB) to expose the next chunk
                // for the next stage.
                r_a[k+1] <= { {(LUTB){1'b0}}, 
                              r_a[k][(IW-1-(2*LUTB)):LUTB] };
                              
                // Just copy r_b down to the next stage.
                r_b[k+1] <= r_b[k];
            end
        end 
    end end endgenerate


    // ====================================================================
    // 10. MULTIPLY & ACCUMULATE STAGES
    // ====================================================================
    // This is the core "Shift-and-Add" loop.
    // Each iteration 'k' creates one hardware stage (one clock cycle of latency).
    
    generate begin : STAGES
    if (TLEN > 2) begin : FOR
        for(k=0; k<TLEN-2; k=k+1)
        begin : GENSTAGES
            wire    [(BW+LUTB-1):0] genp; // Partial Product for this stage

            // --- Step A: Calculate Partial Product ---
            // Multiply the current 2 bits of A (r_a[k]) by B (r_b[k]).
            // Result 'genp' can be 0, B, 2B, or 3B.
            bimpy #(
                .BW(BW)
            ) genmpy(
                .i_clk(i_clk), .i_reset(1'b0), .i_clk_enable(i_clk_enable),
                .i_a(r_a[k][(LUTB-1):0]), // The bottom 2 bits of current A
                .i_b(r_b[k]),             // Current B
                .o_r(genp)
            );

            // --- Step B: Accumulate ---
            // Add the new partial product to the running total.
            // We must SHIFT 'genp' to the left because it represents higher significance bits.
            //
            // Shift Calculation:
            // Stage -1 (Initial): Processed bits [3:0].
            // Stage k=0: Processes bits [5:4]. Needs shift of 4 (LUTB * 2).
            // Formula: shift = LUTB * (k + 2)
            always @(posedge i_clk)
            if (i_clk_enable)
                acc[k+1] <= acc[k] + { {(IW-LUTB*(k+3)){1'b0}}, // Zero padding top
                                       genp,                    // The value
                                       {(LUTB*(k+2)){1'b0}} };  // The Left Shift
        end 
    end end endgenerate
    // ====================================================================
    // 11. FINAL OUTPUT LOGIC
    // ====================================================================
    //
    // At this point:
    //
    //   • acc[TLEN-2] contains the full unsigned product magnitude
    //   • r_s[TLEN-1] contains the delayed sign bit
    //
    // Objective:
    //
    //   Restore correct signed result
    //
    // --------------------------------------------------------------------
    // Sign Restoration
    // --------------------------------------------------------------------
    //
    // Because multiplication was performed on absolute values:
    //
    //      product = |A| × |B|
    //
    // We now reapply the sign:
    //
    //      If sign == 1 → negate
    //      Else          → pass through
    //
    // r_s[TLEN-1]:
    //      Final delayed sign bit
    //
    // acc[TLEN-2]:
    //      Final accumulated magnitude
    //

    assign w_r =
        (r_s[TLEN-1]) ? (-acc[TLEN-2]) : acc[TLEN-2];
    // --------------------------------------------------------------------
    // Output Register
    // --------------------------------------------------------------------
    //
    // Registers final result for:
    //
    //      • Timing closure
    //      • Stable downstream interface
    //      • Clean pipeline boundary
    //
    // Width truncated to requested precision:
    //
    //      AW + BW bits
    //

    always @(posedge i_clk)
    if (i_clk_enable)
        o_r <= w_r[(AW+BW-1):0];
    // ====================================================================
    // 12. UNUSED SIGNAL HANDLING
    // ====================================================================
    //
    // Condition:
    //
    //      IW > AW
    //
    // Meaning:
    //
    //      Operand A padded to even width
    //
    // Consequence:
    //
    //      w_r may contain extra MSBs
    //
    // Strategy:
    //
    //      Explicitly consume unused bits
    //
    // Prevents:
    //
    //      • Linter warnings
    //      • "Unconnected net" alerts
    generate begin : GUNUSED
    if (IW > AW)
    begin : VUNUSED
        wire    unused;
        // OR-reduce the unused upper bits to show they are connected but ignored.
        assign  unused = &{ 1'b0, w_r[(IW+BW-1):(AW+BW)] };
    end end endgenerate
endmodule