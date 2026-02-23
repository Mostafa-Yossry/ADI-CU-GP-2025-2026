// -----------------------------------------------------------------------------
// Module: butterfly
// Purpose:
//   Implements a Radix-2 Decimation-in-Frequency (DIF) butterfly.
//
// Mathematical Operation:
//   Given two complex inputs:
//
//      L = x[n]
//      R = x[n + N/2]
//
//   The radix-2 DIF butterfly computes:
//
//      L' = L + R
//           → Sum Path (no rotation)
//
//      R' = (L - R) × C
//           → Difference Path (rotated by twiddle factor)
//
//   Where:
//
//      C = W_N^k  (complex twiddle factor)
//
// Architectural Role:
//   This module is the fundamental arithmetic engine used in each FFT stage.
//   It performs:
//
//      • Complex addition
//      • Complex subtraction
//      • Complex multiplication
//      • Optional scaling
//
// Timing Characteristics:
//   The module is internally pipelined to:
//
//      • Meet high clock frequency targets
//      • Limit combinational multiplier depth
//      • Maintain streaming throughput
//
//   Latency is automatically derived from operand widths.
//
// Control Signal Alignment:
//   The 'aux' signal propagates alongside data through an equivalent delay line,
//   ensuring:
//
//      • Sync/valid exits aligned with results
//      • No data/control skew across pipeline
// -----------------------------------------------------------------------------

module butterfly #(
    // -------------------------------------------------------------------------
    // Data Width Configuration
    // -------------------------------------------------------------------------
    parameter IWIDTH = 16,  // Input width per component (real/imag)
    parameter CWIDTH = 20,  // Twiddle factor precision
    parameter OWIDTH = 17,  // Output width per component

    // -------------------------------------------------------------------------
    // Static Scaling Control
    // -------------------------------------------------------------------------
    parameter SHIFT = 0,
    // SHIFT implements optional normalization:
    //
    //   Output = Result >> SHIFT
    //
    // Typical usage:
    //   SHIFT = 1 → divide by 2 to prevent overflow
    //   SHIFT = 0 → preserve full precision

    // -------------------------------------------------------------------------
    // Clocking Optimization
    // -------------------------------------------------------------------------
    parameter CKPCE = 1,
    // Clocks Per Clock Enable
    //
    // Used when arithmetic hardware is time-multiplexed.
    // CKPCE = 1 → full-rate pipeline (no reuse)

    // -------------------------------------------------------------------------
    // Latency Estimation Parameters
    // -------------------------------------------------------------------------

    // MAXMPYBITS:
    //   Determines multiplier complexity by selecting the smaller operand width.
    //
    // Rationale:
    //   Multiplier delay scales roughly with:
    //
    //      O(min(A_width, B_width))
    //
    //   Choosing smaller dimension provides conservative pipeline estimate.
    //
    localparam MAXMPYBITS =
    ((IWIDTH+2) > (CWIDTH+1)) ? (CWIDTH+1) : (IWIDTH+2),

    // LCLDELAY:
    //   Heuristic estimate of multiplier pipeline depth.
    //
    // Approximation:
    //
    //   Delay ≈ (MultiplierWidth / 2) + overhead
    //
    // Justification:
    //   Soft logic multipliers grow in logic depth with bit width.
    //   Pipelining inserted approximately every 2 bits of width.
    //
    localparam LCLDELAY = ((MAXMPYBITS+1)/2) + 2,

    // LGDELAY:
    //   Log2 representation of latency.
    //
    // Used for:
    //   • Counter sizing
    //   • Delay line width
    //
    localparam LGDELAY =
    (LCLDELAY > 64) ? 7
    : (LCLDELAY > 32) ? 6
    : (LCLDELAY > 16) ? 5
    : (LCLDELAY >  8) ? 4
    : (LCLDELAY >  4) ? 3
    : 2,

    // BFLYLATENCY:
    //   Total module latency.
    //
    // Components:
    //   • Multiplier pipeline (LCLDELAY)
    //   • Input register stage
    //   • Add/Sub pipeline stage
    //   • Output register stage
    //
    localparam BFLYLATENCY = (LCLDELAY + 3)
  )(
    // --- Ports ---
    input   wire                        i_clk, i_reset, i_clk_enable,
    input   wire    [(2*CWIDTH-1):0]    i_coef,         // Twiddle (Real+Imag)
    input   wire    [(2*IWIDTH-1):0]    i_left, i_right,// Inputs (Real+Imag)

    // i_aux: The Input Sync Signal.
    // You pulse this high when the first data sample enters.
    input   wire                        i_aux,

    output  wire    [(2*OWIDTH-1):0]    o_left, o_right,// Outputs (Real+Imag)

    // o_aux: The Output Sync Signal.
    // This will pulse high exactly 'BFLYLATENCY' cycles after i_aux,
    // signaling that o_left/o_right are valid.
    output  reg                         o_aux
  );
  // ========================================================================
  // 1. SIGNAL DECLARATIONS
  // ========================================================================
  // --- Input Registration ---
  // These registers capture the inputs on the first clock cycle.
  reg     [(2*IWIDTH-1):0]    r_left, r_right;
  reg     [(2*CWIDTH-1):0]    r_coef;         // Twiddle Factor (Stage 1)
  reg     [(2*CWIDTH-1):0]    r_coef_2;       // Twiddle Factor (Stage 2 - Pipelined),aligns coefficient with multiplier pipeline
  // --- Unpacked Components ---
  // Signed wires to handle arithmetic easily.
  wire    signed  [(IWIDTH-1):0]  r_left_r, r_left_i;   // Left Real/Imag
  wire    signed  [(IWIDTH-1):0]  r_right_r, r_right_i; // Right Real/Imag
  // --- Butterfly Adder Results ---
  // Note: These are (IWIDTH+1) bits to handle the 1-bit growth from A+B.
  reg     signed  [(IWIDTH):0]    r_sum_r, r_sum_i;     // Sum (L+R)
  reg     signed  [(IWIDTH):0]    r_dif_r, r_dif_i;     // Diff (L-R)

  // ========================================================================
  // 2. DELAY FIFO (Latency Matching for Sum Path)
  // ========================================================================
  //
  // Problem:
  //   The butterfly produces two results:
  //
  //      SUM  = L + R
  //      DIFF = (L - R) × C
  //
  //   The SUM path is "short":
  //      • Only adders
  //
  //   The DIFF path is "long":
  //      • Subtractor
  //      • Complex multiplier
  //      • Rounding/scaling
  //
  //   The multiplier requires LCLDELAY cycles.
  //
  // Solution:
  //   Insert a FIFO on the SUM path to delay SUM results so they exit
  //   aligned with DIFF results.
  //
  // Result:
  //   SUM and DIFF outputs emerge synchronously.
  //

  reg  [(LGDELAY-1):0] fifo_addr;
  // FIFO write pointer
  // Advances once per valid input sample

  wire [(LGDELAY-1):0] fifo_read_addr;
  // FIFO read pointer
  // Offset from fifo_addr by pipeline depth

  // FIFO storage array
  //
  // Stores SUM results:
  //
  //   Width = 2 × (IWIDTH + 1)
  //         = 2*IWIDTH + 2
  //
  // Why IWIDTH+1?
  //   SUM may generate carry bit
  //
  reg [(2*IWIDTH+1):0] fifo_left [0:((1<<LGDELAY)-1)];

  reg [(2*IWIDTH+1):0] fifo_read;
  // Registered FIFO output (delayed SUM)

  // Unpacked delayed SUM components
  //
  // Extended width used to match multiplier output precision
  //
  wire signed [(IWIDTH+CWIDTH):0] fifo_r;
  wire signed [(IWIDTH+CWIDTH):0] fifo_i;

  // ========================================================================
  // 3. MULTIPLIER SIGNALS
  // ========================================================================
  //
  // Implements complex multiplication:
  //
  //   (a + jb) × (c + jd)
  //
  // Using 3-multiply optimization:
  //
  //   k1 = a × c
  //   k2 = b × d
  //   k3 = (a + b) × (c + d)
  //
  // Then:
  //
  //   Real = k1 − k2
  //   Imag = k3 − k1 − k2
  //

  wire signed [(CWIDTH-1):0] ir_coef_r;
  wire signed [(CWIDTH-1):0] ir_coef_i;
  // Twiddle real/imag components

  wire signed [((IWIDTH+2)+(CWIDTH+1)-1):0] p_one;
  wire signed [((IWIDTH+2)+(CWIDTH+1)-1):0] p_two;
  wire signed [((IWIDTH+2)+(CWIDTH+1)-1):0] p_three;
  // Partial multiplication products

  // Final multiplier outputs (pre-rounding)
  reg signed [(CWIDTH+IWIDTH+3-1):0] mpy_r;
  reg signed [(CWIDTH+IWIDTH+3-1):0] mpy_i;

// ========================================================================
  // 4. ROUNDING & WIDTH ADJUSTMENT
  // ========================================================================
  //
  // Convert extended precision results → OWIDTH
  //

  wire signed [(OWIDTH-1):0] rnd_left_r;
  wire signed [(OWIDTH-1):0] rnd_left_i;

  wire signed [(OWIDTH-1):0] rnd_right_r;
  wire signed [(OWIDTH-1):0] rnd_right_i;

  // Sign-extended SUM results
  // Matches multiplier output width
  //
  wire signed [(CWIDTH+IWIDTH+3-1):0] left_sr;
  wire signed [(CWIDTH+IWIDTH+3-1):0] left_si;
  // ========================================================================
  // 5. AUXILIARY PIPELINE (Sync / Valid Alignment)
  // ========================================================================
  //
  // Ensures control signal exits aligned with arithmetic results
  //

  reg [(BFLYLATENCY-1):0] aux_pipeline;

  // ========================================================================
  // 6. DATA UNPACKING ASSIGNMENTS
  // ========================================================================
  //
  // Purpose:
  //   Convert packed complex vectors into signed arithmetic operands.
  //
  // Packed format convention:
  //
  //   [MSBs] = Real
  //   [LSBs] = Imaginary
  //

  assign r_left_r  = r_left[(2*IWIDTH-1):(IWIDTH)];
  assign r_left_i  = r_left[(IWIDTH-1):0];

  assign r_right_r = r_right[(2*IWIDTH-1):(IWIDTH)];
  assign r_right_i = r_right[(IWIDTH-1):0];

	assign	ir_coef_r = r_coef_2[(2*CWIDTH-1):CWIDTH];
	assign	ir_coef_i = r_coef_2[(CWIDTH-1):0];
	 // ========================================================================
  // 7. FIFO READ POINTER GENERATION
  // ========================================================================
  //
  // Implements circular buffer addressing without modulus (%).
  //
  // Key idea:
  //
  //   fifo_addr increments continuously
  //   Natural overflow → wrap-around
  //
  // Read pointer:
  //
  //   fifo_read_addr = fifo_addr − LCLDELAY
  //
  // Effect:
  //
  //   Read position always trails write pointer by LCLDELAY cycles
  //   Aligns delayed SUM with multiplier output
  assign fifo_read_addr =
         fifo_addr - LCLDELAY[(LGDELAY-1):0];
  // ========================================================================
  // 8. INPUT REGISTRATION & BUTTERFLY ARITHMETIC
  // ========================================================================
  //
  // Pipeline Stage 1:
  //   Register external inputs
  //
  // Pipeline Stage 2:
  //   Compute SUM and DIFF
  //
  // Both steps performed inside one sequential block for clarity
  //

  always @(posedge i_clk)
    if (i_clk_enable)
    begin
      // --------------------------------------------------------------------
      // Pipeline Stage 1: Input Latching
      // --------------------------------------------------------------------
      //
      // Registers isolate internal arithmetic from:
      //   • Routing delays
      //   • Upstream combinational logic
      //
      r_left  <= i_left;
      r_right <= i_right;
      r_coef  <= i_coef;
      // --------------------------------------------------------------------
      // Pipeline Stage 2: Butterfly Arithmetic
      // --------------------------------------------------------------------
      //
      // Radix-2 DIF equations:
      //
      //   SUM  = L + R
      //   DIFF = L − R
      //
      // Width = IWIDTH + 1
      //   Prevent overflow due to carry/borrow
      //

      r_sum_r <= r_left_r  + r_right_r;
      r_sum_i <= r_left_i  + r_right_i;

      r_dif_r <= r_left_r  - r_right_r;
      r_dif_i <= r_left_i  - r_right_i;
      // --------------------------------------------------------------------
      // Coefficient Pipeline Alignment
      // --------------------------------------------------------------------
      //
      // Twiddle factor delayed to align with DIFF path pipeline
      //
      r_coef_2 <= r_coef;
    end
// ========================================================================
  // 9. FIFO WRITE CONTROL (Latency Alignment Mechanism)
  // ========================================================================
  //
  // Objective:
  //   Delay SUM path to match DIFF × Twiddle multiplier latency.
  //
  // fifo_addr:
  //   Acts as circular FIFO write pointer.
  //
  // Behavior:
  //   • Reset → pointer cleared
  //   • Enabled → increments once per valid sample
  //
  // Important:
  //   Natural binary overflow implements circular wrap-around.
  //

  always @(posedge i_clk)
    if (i_reset)
      fifo_addr <= 0;
    else if (i_clk_enable)
      fifo_addr <= fifo_addr + 1;
  // ========================================================================
  // 10. FIFO WRITE OPERATION
  // ========================================================================
  //
  // Stores SUM results into delay FIFO.
  //
  // Stored data:
  //   { r_sum_r, r_sum_i }
  //
  // Width:
  //   2 × (IWIDTH + 1)
  //
  // Rationale:
  //   SUM path contains 1-bit growth from addition.
  //

  always @(posedge i_clk)
    if (i_clk_enable)
      fifo_left[fifo_addr] <= { r_sum_r, r_sum_i };
  // ========================================================================
  // Multiplier Precision Philosophy
  // ========================================================================
  //
  // Fact:
  //   Multiplier output width = sum of operand widths.
  //
  // Implication:
  //   Intermediate products grow wider than final OWIDTH.
  //
  // Design Strategy:
  //   • Preserve full precision internally
  //   • Truncate/round only at output stage
  //
  // Prevents:
  //   • Accumulated quantization noise
  //   • Spectral distortion
  //
  // ========================================================================
  // Karatsuba (3-Multiply) Complex Multiplication
  // ========================================================================
  //
  // Goal:
  //   Compute:
  //
  //      (a + jb) × (c + jd)
  //
  // Using only 3 real multiplications instead of 4.
  //
  // Intermediate Products:
  //
  //      P1 = a × c
  //      P2 = b × d
  //      P3 = (a + b) × (c + d)
  //
  // Reconstruction:
  //
  //      Real = P1 − P2
  //      Imag = P3 − P1 − P2
  //
  // Benefits:
  //   • Saves one multiplier
  //   • Reduces area/power
  //   • Maintains exact arithmetic equivalence
  // ========================================================================
  // 8. KARATSUBA MULTIPLICATION LOGIC
  // ========================================================================
  //
  // Pre-adder stage required for P3 computation.
  //
  // P3 requires:
  //
  //      (a + b) × (c + d)
  //
  // Therefore compute operand sums first.
  //

  wire [(CWIDTH):0]   p3c_in;
  // Sum of coefficient components (Real + Imag)
  // Width = CWIDTH + 1 (possible carry)

  wire [(IWIDTH+1):0] p3d_in;
  // Sum of data components (Real + Imag)
  // Width = IWIDTH + 2 (adder growth)

  assign p3c_in = ir_coef_i + ir_coef_r;
  assign p3d_in = r_dif_r   + r_dif_i;

  // --------------------------------------------------------------------
  // KARATSUBA MULTIPLIER 1: Real × Real (P1)
  // --------------------------------------------------------------------
  //
  // Mathematical Role:
  //
  //   P1 = a × c
  //
  // Where:
  //   a = r_dif_r     (Difference Real)
  //   c = ir_coef_r   (Twiddle Real)
  //
  // Padding Rationale:
  //
  //   P3 uses (a+b) and (c+d), which are naturally wider by +1 bit.
  //
  //   To ensure:
  //      • Identical pipeline latency
  //      • Identical output width
  //
  //   Inputs to P1 are manually sign-extended.
  //
  // Sign-extension technique:
  //      { sign_bit, value }
  //

  longbimpy #(
              .IAW(CWIDTH+1),   // Padded coefficient width
              .IBW(IWIDTH+2)    // Padded data width
            ) p1 (
              .i_clk(i_clk),
              .i_clk_enable(i_clk_enable),

              // Sign-extended Twiddle Real
              .i_a_unsorted({ir_coef_r[CWIDTH-1], ir_coef_r}),

              // Sign-extended Data Real
              .i_b_unsorted({r_dif_r[IWIDTH], r_dif_r}),

              .o_r(p_one)
            );
  // --------------------------------------------------------------------
  // KARATSUBA MULTIPLIER 2: Imag × Imag (P2)
  // --------------------------------------------------------------------
  //
  // Mathematical Role:
  //
  //   P2 = b × d
  //
  // Where:
  //   b = r_dif_i     (Difference Imag)
  //   d = ir_coef_i   (Twiddle Imag)
  //
  // Padding strategy identical to P1.
  //

  longbimpy #(
              .IAW(CWIDTH+1),
              .IBW(IWIDTH+2)
            ) p2 (
              .i_clk(i_clk),
              .i_clk_enable(i_clk_enable),

              .i_a_unsorted({ir_coef_i[CWIDTH-1], ir_coef_i}),
              .i_b_unsorted({r_dif_i[IWIDTH], r_dif_i}),

              .o_r(p_two)
            );
  // --------------------------------------------------------------------
  // KARATSUBA MULTIPLIER 3: Sum Product (P3)
  // --------------------------------------------------------------------
  //
  // Mathematical Role:
  //
  //   P3 = (a + b) × (c + d)
  //
  // Inputs:
  //   p3d_in → (a + b)
  //   p3c_in → (c + d)
  //
  // No manual padding required:
  //   Already widened by addition
  //

  longbimpy #(
              .IAW(CWIDTH+1),
              .IBW(IWIDTH+2)
            ) p3 (
              .i_clk(i_clk),
              .i_clk_enable(i_clk_enable),

              .i_a_unsorted(p3c_in),
              .i_b_unsorted(p3d_in),

              .o_r(p_three)
            );
  // ========================================================================
  // FIFO OUTPUT RECOVERY (Sum Path Alignment)
  // ========================================================================
  //
  // Context:
  //   SUM path was delayed via FIFO.
  //   Multiplier path produced extended precision results.
  //
  // Problem:
  //   SUM width << Multiplier width
  //
  // Solution:
  //   Scale SUM to multiplier precision domain.
  //
  // Method:
  //   Append (CWIDTH−2) zeros → equivalent to left-shift
  //
  // Purpose:
  //      Align numeric magnitude for later rounding/truncation
  //
  assign fifo_r = {
           {2{fifo_read[2*(IWIDTH+1)-1]}},              // Sign extension (guard bits)
           fifo_read[(2*(IWIDTH+1)-1):(IWIDTH+1)],      // Real(SUM)
           {(CWIDTH-2){1'b0}}                           // Scaling via zero padding
         };
  assign fifo_i = {
           {2{fifo_read[(IWIDTH+1)-1]}},                // Sign extension
           fifo_read[((IWIDTH+1)-1):0],                 // Imag(SUM)
           {(CWIDTH-2){1'b0}}                           // Scaling
         };

  // ========================================================================
  // 9. ROUNDING AND TRUNCATION LOGIC
  // ========================================================================
  //
  // Context:
  //   Internal datapath width has grown due to:
  //
  //      • Butterfly addition/subtraction (+1 bit)
  //      • Multiplier expansion (IWIDTH + CWIDTH)
  //      • Guard bits for overflow protection
  //      • Scaling alignment shifts
  //
  // Objective:
  //   Reduce extended precision → OWIDTH
  //
  // Requirements:
  //      • Preserve numerical accuracy
  //      • Avoid DC bias
  //      • Minimize quantization noise
  //
  // ------------------------------------------------------------------------
  // A. FIFO Path Width Normalization
  // ------------------------------------------------------------------------
  //
  // Problem:
  //   FIFO (SUM path) width < Multiplier (DIFF path) width
  //
  // Solution:
  //   Extend FIFO data to multiplier precision domain
  //
  // Method:
  //      1) Sign extension (preserve signed value)
  //      2) Guard bits for rounding safety, Two guard bits added
  // Protects rounding correctness
  // Prevents overflow during truncatio
  //

  assign left_sr = { {(2){fifo_r[(IWIDTH+CWIDTH)]}}, fifo_r };
  assign left_si = { {(2){fifo_i[(IWIDTH+CWIDTH)]}}, fifo_i };
  // ------------------------------------------------------------------------
  // B. Convergent Rounding (Round-to-Nearest-Even)
  // ------------------------------------------------------------------------
  //
  // Rounding Strategy:
  //   "Round to nearest even"
  //
  // Benefits:
  //      • Eliminates systematic bias
  //      • Improves SQNR
  //      • Preferred for FFT/datapath DSP
  //
  // SHIFT+4 explanation:
  //
  //   SHIFT → Optional scaling factor
  //
  //   +4 bits removed due to:
  //      • Internal arithmetic guard bits
  //      • Scaling alignment padding
  //

  convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
            do_rnd_left_r(i_clk, i_clk_enable, left_sr, rnd_left_r);

  convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
            do_rnd_left_i(i_clk, i_clk_enable, left_si, rnd_left_i);

  convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
            do_rnd_right_r(i_clk, i_clk_enable, mpy_r, rnd_right_r);

  convround #(CWIDTH+IWIDTH+3, OWIDTH, SHIFT+4)
            do_rnd_right_i(i_clk, i_clk_enable, mpy_i, rnd_right_i);
  // ========================================================================
  // 10. KARATSUBA RECONSTRUCTION & FIFO READ
  // ========================================================================
  //
  // Two parallel recovery paths:
  //
  //   Path A → Delayed SUM from FIFO
  //   Path B → Reconstructed multiplier result
  //

  always @(posedge i_clk)
    if (i_clk_enable)
    begin
      // Recover SUM delayed by LCLDELAY cycles
      fifo_read <= fifo_left[fifo_read_addr];

      // Karatsuba recombination:
      //
      //   Real = P1 − P2
      //   Imag = P3 − P1 − P2
      //
      mpy_r <= p_one   - p_two;
      mpy_i <= p_three - p_one - p_two;
    end
  // ========================================================================
  // 11. AUXILIARY SIGNAL SYNCHRONIZATION
  // ========================================================================
  //
  // Problem:
  //   Control/sync must match datapath latency exactly
  //
  // Solution:
  //   Shift register delay line
  //

  always @(posedge i_clk)
    if (i_reset)
      aux_pipeline <= 0;
    else if (i_clk_enable)
      aux_pipeline <= { aux_pipeline[(BFLYLATENCY-2):0], i_aux };
  // Output delayed sync aligned with data
  always @(posedge i_clk)
    if (i_reset)
      o_aux <= 1'b0;
    else if (i_clk_enable)
      o_aux <= aux_pipeline[BFLYLATENCY-1];
  // ========================================================================
  // 12. FINAL OUTPUT ASSIGNMENT
  // ========================================================================
  //
  // Pack rounded results:
  //
  //   [MSBs] = Real
  //   [LSBs] = Imag
  //

  assign o_left  = { rnd_left_r,  rnd_left_i };
  assign o_right = { rnd_right_r, rnd_right_i };
endmodule
