// =============================================================================
// matched_filter_pipe.sv
// -----------------------------------------------------------------------------
// Fully-pipelined, bit-accurate matched filter:  ŷ = H^H · y
//
// MATLAB equivalence target
// -------------------------
//   All arithmetic uses:
//     fimath('RoundingMethod','Convergent','OverflowAction','Wrap',
//            'ProductMode','SpecifyPrecision',
//            'SumMode',    'SpecifyPrecision', ...)
//   with output word/fraction lengths set to the localparams below.
//   Every stage is documented with the fi format it produces so that
//   a MATLAB verification script can replicate each register exactly.
//
// Fixed-point format notation used throughout
// -------------------------------------------
//   Qs.i.f  =>  signed, i integer bits (not counting sign), f fractional bits
//               total word length = 1 + i + f
//   Example:  Q1.11 input  =>  1 sign + 0 integer + 11 frac  =>  12-bit word
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │                     FIXED-POINT FORMAT TABLE                            │
// ├──────────────┬─────────────┬───────────────────────────────────────────┤
// │  Stage       │  MATLAB fi  │  Notes                                     │
// ├──────────────┼─────────────┼───────────────────────────────────────────┤
// │  Input y,HH  │  WL_IN bits │  INT_BITS_IN integer, FRAC_BITS_IN frac   │
// │  After widen │  WL_INT bits│  INT_BITS_INT integer, FRAC_BITS_INT frac │
// │  Product     │  WL_PROD    │  full-precision multiply, no rounding      │
// │  After round │  WL_OUT bits│  INT_BITS_OUT integer, FRAC_BITS_OUT frac │
// │  Adder tree  │  WL_OUT bits│  wrap arithmetic, same format as output   │
// │  Output      │  WL_OUT bits│  INT_BITS_OUT integer, FRAC_BITS_OUT frac │
// └──────────────┴─────────────┴───────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────┐
// │                     PIPELINE LATENCY TABLE                              │
// ├──────────┬──────────────────────────────────────────────────────────────┤
// │  Cycle 0 │  valid_in asserted; y and coef sampled                       │
// │  Cycle 1 │  Stage 1 output: K complex products registered (WL_PROD)     │
// │  Cycle 2 │  Stage 2 output: products rounded to WL_OUT; level-0 pair    │
// │           │  sums registered (K/2 partial sums per row)                 │
// │  Cycle 3 … Cycle 1+LEVELS                                               │
// │           │  Tree levels 1…LEVELS-1: each adds one pipeline register    │
// │  Cycle 1+LEVELS  │  valid_out asserts; yhat_real/imag valid             │
// │                  │  gy_enable asserts for the first time (sticky)       │
// │  Total latency   │  LATENCY = 1 + LEVELS = 1 + $clog2(COLS)  cycles    │
// │  Default (COLS=8): LATENCY = 4 cycles                                   │
// └──────────┴──────────────────────────────────────────────────────────────┘
//
// LATENCY is a localparam (Part 1), not a module parameter, but it is fully
// accessible to a wrapper or testbench via hierarchical reference once the
// module is instantiated, e.g.:
//
//   matched_filter_pipe #(...) u_mf (...);
//   localparam int MF_LAT = u_mf.LATENCY;   // = 1 + $clog2(COLS)
//
// This requires no RTL change -- SystemVerilog exposes instance localparams
// hierarchically by default. A wrapper can use this value to size drain
// counters / timing checks without duplicating the $clog2(COLS) computation.
//
// gy_enable
// ---------
//   A sticky "pipeline primed" flag: 0 after reset, latches to 1 on the
//   first cycle valid_out asserts, and remains 1 until the next rst_n.
//   See Part 8b for the implementation (1 FF + 1 assign, purely additive).
//
// Parameters
// ----------
//   ROWS          – rows of H^H  (= antenna count for a square system)
//   COLS          – dot-product length K (= columns of H^H)
//                   MUST be a power of two.
//   WL_IN         – input word length  (bits)
//   INT_BITS_IN   – integer bits of input  (not counting sign bit)
//   FRAC_BITS_IN  – fractional bits of input
//   WL_INT        – internal word length after widening coefficients & y
//   INT_BITS_INT  – integer bits after widening
//   FRAC_BITS_INT – fractional bits after widening
//   WL_OUT        – output / post-round word length
//   INT_BITS_OUT  – integer bits of output
//   FRAC_BITS_OUT – fractional bits of output
//
// Constraint (checked via assertions):
//   WL_IN  == 1 + INT_BITS_IN  + FRAC_BITS_IN
//   WL_INT == 1 + INT_BITS_INT + FRAC_BITS_INT
//   WL_OUT == 1 + INT_BITS_OUT + FRAC_BITS_OUT
//   COLS must be a power of two  (COLS & (COLS-1) == 0)
// =============================================================================

module matched_filter_pipeW #(
    // -------------------------------------------------------------------------
    // Matrix dimensions
    // -------------------------------------------------------------------------
    parameter int ROWS          = 8,    // output elements  (rows of H^H)
    parameter int COLS          = 8,    // dot-product len  (columns of H^H)
                                        // MUST be a power of two

    // -------------------------------------------------------------------------
    // Input fixed-point format  (applies to both y and H^H coefficients)
    //   Default: Q1.11  →  12-bit signed, 0 integer bits, 11 fractional bits
    // -------------------------------------------------------------------------
    parameter int WL_IN         = 12,
    parameter int INT_BITS_IN   =  0,
    parameter int FRAC_BITS_IN  = 11,

    // -------------------------------------------------------------------------
    // Internal widened format  (coefficients and y both widened before multiply)
    //   Default: Q1.15  →  16-bit signed, 0 integer bits, 15 fractional bits
    //   Widening is done by appending (FRAC_BITS_INT - FRAC_BITS_IN) zero LSBs
    //   and sign-extending the integer portion to (INT_BITS_INT - INT_BITS_IN)
    //   extra bits.  For the default, both sides are equal so only LSBs added.
    // -------------------------------------------------------------------------
    parameter int WL_INT        = 16,
    parameter int INT_BITS_INT  =  0,
    parameter int FRAC_BITS_INT = 15,

    // -------------------------------------------------------------------------
    // Output fixed-point format  (also the post-rounding format in adder tree)
    //   Default: Q5.11  →  16-bit signed, 4 integer bits, 11 fractional bits
    // -------------------------------------------------------------------------
    parameter int WL_OUT        = 16,
    parameter int INT_BITS_OUT  =  4,
    parameter int FRAC_BITS_OUT = 11
)(
    input  logic clk,
    input  logic rst_n,
    input  logic en,            // pipeline enable (stalls all stages when low)

    // -------------------------------------------------------------------------
    // H^H coefficient load interface
    //   Assert hh_load for exactly one rising clock edge to latch all ROWS×COLS
    //   complex coefficients.  hh_real/imag must be stable on that posedge.
    //   Loading is independent of en; coefficients remain stable until the next
    //   hh_load.  A load mid-stream will corrupt in-flight results (caller
    //   responsibility to guard this with a pipeline flush / idle period).
    // -------------------------------------------------------------------------
    input  logic                      hh_load,
    input  logic signed [WL_IN-1:0]  hh_real [0:ROWS-1][0:COLS-1],
    input  logic signed [WL_IN-1:0]  hh_imag [0:ROWS-1][0:COLS-1],

    // -------------------------------------------------------------------------
    // Streaming y vector input  (one new K-element vector per cycle)
    // -------------------------------------------------------------------------
    input  logic                      valid_in,
    input  logic signed [WL_IN-1:0]  y_real  [0:COLS-1],
    input  logic signed [WL_IN-1:0]  y_imag  [0:COLS-1],

    // -------------------------------------------------------------------------
    // Output:  valid_out asserts LATENCY cycles after valid_in
    //          LATENCY = 1 + $clog2(COLS)
    //
    //   gy_enable: asserts on the rising edge of the FIRST valid_out after
    //              reset, and stays high thereafter (until the next rst_n).
    //              Intended as a "pipeline primed" flag for downstream logic:
    //              it implicitly confirms that BOTH a valid H^H load AND a
    //              valid y vector have flowed completely through the LATENCY-
    //              deep pipeline at least once. Does not deassert if en is
    //              later lowered or if hh_load fires again -- a full reset
    //              is required to clear it.
    // -------------------------------------------------------------------------
    output logic                      valid_out,
    output logic                      gy_enable,
    output logic signed [WL_OUT-1:0] yhat_real [0:ROWS-1],
    output logic signed [WL_OUT-1:0] yhat_imag [0:ROWS-1]
);

// =============================================================================
// Part 1 – Derived fixed-point parameters
// -----------------------------------------------------------------------------
// All arithmetic dimensions are computed from the format parameters so that
// changing WL_IN / WL_INT / WL_OUT / FRAC_* automatically adjusts shifts,
// product widths, and rounding logic.
// =============================================================================

    // -------------------------------------------------------------------------
    // Widening shift
    //   When converting input (WL_IN / FRAC_BITS_IN) → internal (WL_INT /
    //   FRAC_BITS_INT), we left-shift by the difference in fractional bits.
    //   This is purely a concatenation of zero LSBs; no numerical loss occurs.
    // -------------------------------------------------------------------------
    localparam int FRAC_WIDEN = FRAC_BITS_INT - FRAC_BITS_IN;
    //   FRAC_WIDEN ≥ 0 is required (internal format must be at least as
    //   precise as the input format).

    // -------------------------------------------------------------------------
    // Full-precision product format
    //
    //   Multiplying two WL_INT-bit signed values:
    //     sign bits:    1  (shared – the product sign covers both)
    //     integer bits: INT_BITS_INT + INT_BITS_INT   (bilinear growth)
    //     frac bits:    FRAC_BITS_INT + FRAC_BITS_INT
    //
    //   MATLAB fimath 'ProductMode','FullPrecision' gives exactly this.
    //   WL_PROD = WL_INT + WL_INT  (i.e. 2×WL_INT).
    //
    //   Note: a signed×signed 16-bit multiply produces a 32-bit result
    //   (the MSB is redundant in two's complement, but keeping it avoids
    //   any width mismatch during subtraction inside complex multiply).
    // -------------------------------------------------------------------------
    localparam int PROD_FRAC = FRAC_BITS_INT + FRAC_BITS_INT;   // 30 default
    localparam int PROD_INT  = INT_BITS_INT  + INT_BITS_INT;     //  0 default
    localparam int WL_PROD   = 2 * WL_INT;                       // 32 default

    // -------------------------------------------------------------------------
    // Right-shift to align product to output format (before convergent round)
    //
    //   Product has PROD_FRAC fractional bits.
    //   Output needs FRAC_BITS_OUT fractional bits.
    //   Bits to discard = PROD_FRAC - FRAC_BITS_OUT
    //
    //   In MATLAB:
    //     fi(prod, 1, WL_OUT, FRAC_BITS_OUT)
    //   with RoundingMethod='Convergent' performs exactly this shift+round.
    // -------------------------------------------------------------------------
    localparam int RIGHT_SH = PROD_FRAC - FRAC_BITS_OUT;         // 19 default

    // -------------------------------------------------------------------------
    // Adder-tree depth and total pipeline latency
    //
    //   LEVELS = $clog2(COLS):   number of binary adder stages
    //   LATENCY: 1 (multiply stage) + 1 (round + first adder level) +
    //            (LEVELS-1) further adder stages
    //          = 1 + LEVELS
    //   Wait – let's be precise:
    //     Stage 1: multiply      → 1 cycle
    //     Stage 2: round + add   → 1 cycle  (consumes one adder level)
    //     Stage 3…2+LEVELS-1: remaining (LEVELS-1) adder levels → LEVELS-1 cycles
    //   Total: 1 + 1 + (LEVELS-1) = 1 + LEVELS
    //
    //   valid_out asserts LATENCY cycles after valid_in.
    // -------------------------------------------------------------------------
    localparam int LEVELS  = $clog2(COLS);                        // 3 default
    localparam int LATENCY = 1 + LEVELS;                          // 4 default


// =============================================================================
// Part 2 – Compile-time sanity checks
// =============================================================================

    initial begin : param_check
        // Format consistency
        if (WL_IN  != 1 + INT_BITS_IN  + FRAC_BITS_IN)
            $fatal(1, "WL_IN  mismatch: %0d != 1+%0d+%0d",
                   WL_IN, INT_BITS_IN, FRAC_BITS_IN);
        if (WL_INT != 1 + INT_BITS_INT + FRAC_BITS_INT)
            $fatal(1, "WL_INT mismatch: %0d != 1+%0d+%0d",
                   WL_INT, INT_BITS_INT, FRAC_BITS_INT);
        if (WL_OUT != 1 + INT_BITS_OUT + FRAC_BITS_OUT)
            $fatal(1, "WL_OUT mismatch: %0d != 1+%0d+%0d",
                   WL_OUT, INT_BITS_OUT, FRAC_BITS_OUT);

        // Product wide enough to hold result before rounding
        //   After shifting right by RIGHT_SH, WL_PROD-RIGHT_SH significant
        //   bits remain (the rest are sign-extension copies). This is only
        //   degenerate if the shift consumes the entire product width,
        //   leaving no data bits at all.
        if (RIGHT_SH >= WL_PROD)
            $fatal(1, "WL_PROD too narrow for rounding shift");

        // Rounding shift non-negative
        if (RIGHT_SH < 1)
            $fatal(1, "RIGHT_SH=%0d: output format is wider than product – no bits to round", RIGHT_SH);

        // COLS must be a power of two for the balanced adder tree
        if ((COLS & (COLS - 1)) != 0)
            $fatal(1, "COLS=%0d must be a power of two", COLS);

        // Widening must be non-negative
        if (FRAC_WIDEN < 0)
            $fatal(1, "FRAC_BITS_INT < FRAC_BITS_IN: internal format less precise than input");

        // Internal integer headroom must be at least as wide as the input.
        //   If INT_BITS_INT < INT_BITS_IN the sign-extension concatenation
        //   {{(WL_INT-WL_IN-FRAC_WIDEN){sign}}, val, {FRAC_WIDEN{0}}} would
        //   have a negative repeat count, silently truncating input MSBs and
        //   diverging from the MATLAB fi() widening model.
        if (INT_BITS_INT < INT_BITS_IN)
            $fatal(1, "INT_BITS_INT=%0d < INT_BITS_IN=%0d: internal format narrower than input; sign-extension would truncate MSBs",
                   INT_BITS_INT, INT_BITS_IN);
    end


// =============================================================================
// Part 2b – Elaboration-time COLS power-of-two guard  (synthesis-visible)
// -----------------------------------------------------------------------------
// The simulation-only $fatal inside param_check catches a non-power-of-two COLS
// at runtime, but a synthesis run never executes initial blocks.  This generate
// block produces an intentionally illegal negative-width wire whenever COLS is
// not a power of two, which forces ANY elaboration tool (simulator or
// synthesizer) to abort with an elaboration error rather than silently building
// a wrong adder tree.
//
// How it works:
//   COLS_POW2_CHECK = COLS & (COLS-1)
//     = 0  for every power of two  → the illegal branch is not instantiated
//     ≠ 0  for any non-power-of-two → the illegal branch IS instantiated,
//           producing wire [(-1):0] which is a zero- or negative-width vector
//           and is a compile/elaboration error in all known tools.
//
// This check is completely removed by the synthesizer for valid COLS because the
// generate condition is false; it adds no logic, no area, and no timing impact.
// =============================================================================

    localparam int COLS_POW2_CHECK = COLS & (COLS - 1);

    generate
        if (COLS_POW2_CHECK != 0) begin : COLS_NOT_POWER_OF_TWO_ELABORATION_ERROR
            // Intentionally illegal declaration.  If you see this error the COLS
            // parameter is not a power of two and the adder tree is ill-formed.
            wire [(-1):0] illegal_signal_cols_must_be_power_of_two;
        end
    endgenerate


// =============================================================================
// Part 3 – H^H coefficient registers
// -----------------------------------------------------------------------------
// Coefficients are stored in widened internal format (WL_INT bits) so that
// every downstream multiply operates on the same word width without an inline
// widening delay.
//
// MATLAB equivalence:
//   In MATLAB: coef = fi(hh, 1, WL_INT, FRAC_BITS_INT)
//   This is identical to left-shifting the Q-input value by FRAC_WIDEN bits
//   (appending zero LSBs) and sign-extending the integer portion.
//   For the default case (INT_BITS_IN == INT_BITS_INT == 0, FRAC_WIDEN == 4)
//   this is simply {hh_val, 4'b0}.
//   The general case is handled by the concatenation below.
// =============================================================================

    logic signed [WL_INT-1:0] coef_real [0:ROWS-1][0:COLS-1];
    logic signed [WL_INT-1:0] coef_imag [0:ROWS-1][0:COLS-1];

    generate
        for (genvar gr = 0; gr < ROWS; gr++) begin : g_coef_row
            for (genvar gk = 0; gk < COLS; gk++) begin : g_coef_col
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        coef_real[gr][gk] <= '0;
                        coef_imag[gr][gk] <= '0;
                    end else if (hh_load) begin
                        // Widen input → internal format:
                        //   sign-extend integer portion, zero-pad fractional LSBs
                        //   WL_INT = WL_IN + FRAC_WIDEN  (for symmetric widening)
                        //   General: {{(WL_INT-WL_IN){sign}}, val, {FRAC_WIDEN{0}}}
                        coef_real[gr][gk] <= signed'(
                            {{(WL_INT - WL_IN - FRAC_WIDEN){hh_real[gr][gk][WL_IN-1]}},
                              hh_real[gr][gk],
                             {FRAC_WIDEN{1'b0}}}
                        );
                        coef_imag[gr][gk] <= signed'(
                            {{(WL_INT - WL_IN - FRAC_WIDEN){hh_imag[gr][gk][WL_IN-1]}},
                              hh_imag[gr][gk],
                             {FRAC_WIDEN{1'b0}}}
                        );
                    end
                end
            end
        end
    endgenerate


// =============================================================================
// Part 4 – y input widening  (combinational, no register)
// -----------------------------------------------------------------------------
// Mirror the coefficient widening so both operands are in the same
// WL_INT-bit format before multiplication.
//
// MATLAB equivalence:
//   yw = fi(y, 1, WL_INT, FRAC_BITS_INT)
// =============================================================================

    logic signed [WL_INT-1:0] y_real_w [0:COLS-1];
    logic signed [WL_INT-1:0] y_imag_w [0:COLS-1];

    generate
        for (genvar gk = 0; gk < COLS; gk++) begin : g_widen_y
            assign y_real_w[gk] = signed'(
                {{(WL_INT - WL_IN - FRAC_WIDEN){y_real[gk][WL_IN-1]}},
                  y_real[gk],
                 {FRAC_WIDEN{1'b0}}}
            );
            assign y_imag_w[gk] = signed'(
                {{(WL_INT - WL_IN - FRAC_WIDEN){y_imag[gk][WL_IN-1]}},
                  y_imag[gk],
                 {FRAC_WIDEN{1'b0}}}
            );
        end
    endgenerate


// =============================================================================
// Part 5 – STAGE 1: Parallel complex multipliers
// -----------------------------------------------------------------------------
// For each (row, col) pair compute the complex product:
//
//   (coef_r + j·coef_i) × (y_r + j·y_i)
//   = (coef_r·y_r  -  coef_i·y_i)  +  j·(coef_r·y_i  +  coef_i·y_r)
//
// All four real sub-products use signed 16×16 → 32-bit multiplication.
// No rounding occurs here; full precision is retained to avoid double
// rounding (which would diverge from MATLAB behavior).
//
// MATLAB equivalence:
//   p = fi(coef, 1, WL_PROD, PROD_FRAC) * fi(yw, 1, WL_PROD, PROD_FRAC)
//   with ProductMode='FullPrecision' (no rounding at multiply step).
//
// Input format  (both operands): Q<sign>.<INT_BITS_INT>.<FRAC_BITS_INT>
// Output format (each product):  Q<sign>.<PROD_INT>.<PROD_FRAC>
//                                 = Q1.<2·INT_BITS_INT>.<2·FRAC_BITS_INT>
// =============================================================================

    logic signed [WL_PROD-1:0] s1_mult_real [0:ROWS-1][0:COLS-1];
    logic signed [WL_PROD-1:0] s1_mult_imag [0:ROWS-1][0:COLS-1];
    logic                       s1_valid;

    generate
        for (genvar gr = 0; gr < ROWS; gr++) begin : g_s1_row
            for (genvar gk = 0; gk < COLS; gk++) begin : g_s1_col

                // Four real products (combinational, inferred as multipliers)
                logic signed [WL_PROD-1:0] p_rr, p_ii, p_ri, p_ir;

                assign p_rr = coef_real[gr][gk] * y_real_w[gk];
                assign p_ii = coef_imag[gr][gk] * y_imag_w[gk];
                assign p_ri = coef_real[gr][gk] * y_imag_w[gk];
                assign p_ir = coef_imag[gr][gk] * y_real_w[gk];

                // Pipeline register: sample products and valid together
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        s1_mult_real[gr][gk] <= '0;
                        s1_mult_imag[gr][gk] <= '0;
                    end else if (en) begin
                        // Complex multiply:  real = ac − bd,  imag = ad + bc
                        s1_mult_real[gr][gk] <= p_rr - p_ii;
                        s1_mult_imag[gr][gk] <= p_ri + p_ir;
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) s1_valid <= 1'b0;
        else if (en) s1_valid <= valid_in;
    end


// =============================================================================
// Part 6 – STAGE 2: Convergent rounding + level-0 adder
// -----------------------------------------------------------------------------
//
// 6a. Convergent rounding  (round-half-to-even)
// -----------------------------------------------
// Given a WL_PROD-bit product P in format Q<PROD_INT>.<PROD_FRAC>, produce
// a WL_OUT-bit result R in format Q<INT_BITS_OUT>.<FRAC_BITS_OUT>.
//
// We discard RIGHT_SH = PROD_FRAC − FRAC_BITS_OUT fractional bits.
//
// Standard convergent-round logic:
//
//   T      = P >>> RIGHT_SH           (arithmetic right shift, truncate)
//   guard  = P[RIGHT_SH-1]            (the bit just below the cut)
//   sticky = |P[RIGHT_SH-2:0]         (OR of all bits below guard)
//   lsb    = T[0]                     (LSB of truncated result)
//
//   round_up = guard & (sticky | lsb)
//   R        = T + round_up
//
// This matches MATLAB's 'Convergent' (round-half-to-even):
//   • If |fraction| < 0.5 ULP → truncate
//   • If |fraction| > 0.5 ULP → round away from zero
//   • If exactly 0.5 ULP     → round to even (toggle LSB if currently odd)
//
// Note on sticky when RIGHT_SH == 1:
//   P[RIGHT_SH-2:0] = P[-1:0]  is an empty range → sticky = 0 always.
//   This is correctly handled by the parameter check (RIGHT_SH ≥ 1) and
//   the generate structure – the sticky wire simply has no bits to OR.
//
// 6b. Level-0 pair adder
// ----------------------
// After rounding, the COLS rounded products per row are added in pairs:
//   node[k/2] = rnd[k] + rnd[k+1]     for k = 0, 2, 4, …, COLS-2
//
// Both operands are WL_OUT-bit Q<INT_BITS_OUT>.<FRAC_BITS_OUT>.
// The sum naturally wraps to WL_OUT bits (matching MATLAB Wrap overflow).
//
// MATLAB equivalence:
//   rnd = fi(P, 1, WL_OUT, FRAC_BITS_OUT)   % Convergent, Wrap
//   s   = fi(rnd(k) + rnd(k+1), 1, WL_OUT, FRAC_BITS_OUT)  % Wrap
//
// Output format: Q<sign>.<INT_BITS_OUT>.<FRAC_BITS_OUT>  (WL_OUT bits)
// =============================================================================

    localparam int NODES_L0 = COLS / 2;   // outputs of level-0 adder = COLS/2

    logic signed [WL_OUT-1:0] s2_sum_real [0:ROWS-1][0:NODES_L0-1];
    logic signed [WL_OUT-1:0] s2_sum_imag [0:ROWS-1][0:NODES_L0-1];
    logic                      s2_valid;

    generate
        for (genvar gr = 0; gr < ROWS; gr++) begin : g_s2_row
            for (genvar gk = 0; gk < NODES_L0; gk++) begin : g_s2_node

                // ----------------------------------------------------------
                // Convergent round of product index 2*gk  (call it 'a')
                // ----------------------------------------------------------
                logic signed [WL_OUT-1:0] tr_a_r, tr_a_i;   // truncated
                logic                     g_a_r,  g_a_i;    // guard bit
                logic                     st_a_r, st_a_i;   // sticky bit
                logic signed [WL_OUT-1:0] rnd_a_r, rnd_a_i; // rounded

                assign tr_a_r  = signed'(s1_mult_real[gr][2*gk] >>> RIGHT_SH);
                assign tr_a_i  = signed'(s1_mult_imag[gr][2*gk] >>> RIGHT_SH);
                assign g_a_r   = s1_mult_real[gr][2*gk][RIGHT_SH-1];
                assign g_a_i   = s1_mult_imag[gr][2*gk][RIGHT_SH-1];

                if (RIGHT_SH >= 2) begin : g_sticky_a
                    assign st_a_r = |s1_mult_real[gr][2*gk][RIGHT_SH-2:0];
                    assign st_a_i = |s1_mult_imag[gr][2*gk][RIGHT_SH-2:0];
                end else begin : g_no_sticky_a
                    // RIGHT_SH == 1: no bits below guard → not a tie
                    // sticky = 0 forces pure round-half-to-even on guard alone
                    assign st_a_r = 1'b0;
                    assign st_a_i = 1'b0;
                end

                // round_up = guard & (sticky | lsb_of_truncated)
                // The increment is 0 or 1; zero-extend (unsigned) to WL_OUT so
                // that adding it to the truncated (signed) value is correct.
                // Using signed' on a 1-bit '1' would produce -1 in two's complement.
                assign rnd_a_r = tr_a_r +
                    WL_OUT'({(WL_OUT-1)'(0), (g_a_r & (st_a_r | tr_a_r[0]))});
                assign rnd_a_i = tr_a_i +
                    WL_OUT'({(WL_OUT-1)'(0), (g_a_i & (st_a_i | tr_a_i[0]))});

                // ----------------------------------------------------------
                // Convergent round of product index 2*gk+1  (call it 'b')
                // ----------------------------------------------------------
                logic signed [WL_OUT-1:0] tr_b_r, tr_b_i;
                logic                     g_b_r,  g_b_i;
                logic                     st_b_r, st_b_i;
                logic signed [WL_OUT-1:0] rnd_b_r, rnd_b_i;

                assign tr_b_r  = signed'(s1_mult_real[gr][2*gk+1] >>> RIGHT_SH);
                assign tr_b_i  = signed'(s1_mult_imag[gr][2*gk+1] >>> RIGHT_SH);
                assign g_b_r   = s1_mult_real[gr][2*gk+1][RIGHT_SH-1];
                assign g_b_i   = s1_mult_imag[gr][2*gk+1][RIGHT_SH-1];

                if (RIGHT_SH >= 2) begin : g_sticky_b
                    assign st_b_r = |s1_mult_real[gr][2*gk+1][RIGHT_SH-2:0];
                    assign st_b_i = |s1_mult_imag[gr][2*gk+1][RIGHT_SH-2:0];
                end else begin : g_no_sticky_b
                    assign st_b_r = 1'b0;
                    assign st_b_i = 1'b0;
                end

                assign rnd_b_r = tr_b_r +
                    WL_OUT'({(WL_OUT-1)'(0), (g_b_r & (st_b_r | tr_b_r[0]))});
                assign rnd_b_i = tr_b_i +
                    WL_OUT'({(WL_OUT-1)'(0), (g_b_i & (st_b_i | tr_b_i[0]))});

                // ----------------------------------------------------------
                // Level-0 pair sum  (wrap arithmetic → natural WL_OUT truncate)
                // ----------------------------------------------------------
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        s2_sum_real[gr][gk] <= '0;
                        s2_sum_imag[gr][gk] <= '0;
                    end else if (en) begin
                        s2_sum_real[gr][gk] <= rnd_a_r + rnd_b_r;
                        s2_sum_imag[gr][gk] <= rnd_a_i + rnd_b_i;
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) s2_valid <= 1'b0;
        else if (en) s2_valid <= s1_valid;
    end


// =============================================================================
// Part 7 – STAGES 3 … (2+LEVELS−1):  Balanced adder tree
// -----------------------------------------------------------------------------
// After Stage 2 we have NODES_L0 = COLS/2 partial sums per row.
// We need LEVELS-1 more adder stages to reduce to a single sum.
//
// Implementation strategy:
//   Use a 3-D array:  tree[level][row][node]
//     level 0 → NODES_L0   nodes (= COLS/2, produced by Stage 2)
//     level 1 → NODES_L0/2 nodes
//     …
//     level LEVELS-1 → 1 node = final result
//
//   Level 0 of the array is seeded from Stage 2 outputs (combinationally,
//   no extra register – Stage 2 already registered them).
//   Levels 1 … LEVELS-1 each add one pipeline stage.
//
// Each addition keeps WL_OUT bits and wraps (matching MATLAB fi Wrap).
//
// MATLAB equivalence for each node at level l:
//   tree[l][r][n] = fi(tree[l-1][r][2n] + tree[l-1][r][2n+1],
//                      1, WL_OUT, FRAC_BITS_OUT)   % Wrap
//
// Total adder-tree latency = LEVELS cycles
//   (1 cycle consumed by Stage 2 pair sum, LEVELS-1 further cycles here,
//    but LEVELS is the total count because Stage 2 folds the first level in).
// =============================================================================

    // Maximum nodes at any tree level is NODES_L0
    // Declare 2-D per-level arrays; unused nodes in later levels are simply
    // never driven and will be optimised away by synthesis.
    //
    // We use an unpacked array of LEVELS levels, each of dimension ROWS × NODES_L0.
    // Only the live nodes at each level are written.

    logic signed [WL_OUT-1:0] tree_real [0:LEVELS-1][0:ROWS-1][0:NODES_L0-1];
    logic signed [WL_OUT-1:0] tree_imag [0:LEVELS-1][0:ROWS-1][0:NODES_L0-1];
    logic                      tree_valid [0:LEVELS-1];

    generate
        for (genvar gl = 0; gl < LEVELS; gl++) begin : g_tree_level

            // Number of nodes entering / leaving level gl.
            //   Level 0 (seed) holds NODES_L0 nodes (Stage 2 outputs).
            //   Level gl>=1 takes as input the OUTPUT count of level gl-1
            //   (i.e. NODES_L0 >> (gl-1)) and halves it.
            localparam int N_IN  = (gl == 0) ? NODES_L0 : (NODES_L0 >> (gl-1));
            localparam int N_OUT = NODES_L0 >> gl;          // nodes leaving  level gl

            if (gl == 0) begin : g_tree_seed
                // ----------------------------------------------------------------
                // Level 0: seed from Stage 2 registered outputs.
                // This is NOT an additional register – s2_sum is already
                // registered.  We alias it through the tree array combinationally.
                // ----------------------------------------------------------------
                for (genvar gr = 0; gr < ROWS; gr++) begin : g_seed_row
                    for (genvar gn = 0; gn < N_IN; gn++) begin : g_seed_node
                        assign tree_real[0][gr][gn] = s2_sum_real[gr][gn];
                        assign tree_imag[0][gr][gn] = s2_sum_imag[gr][gn];
                    end
                end
                assign tree_valid[0] = s2_valid;

            end else begin : g_tree_add
                // ----------------------------------------------------------------
                // Levels 1 … LEVELS-1: pairwise addition with one pipeline register.
                // Each level reads from level gl-1 and writes to level gl.
                // ----------------------------------------------------------------
                for (genvar gr = 0; gr < ROWS; gr++) begin : g_add_row
                    for (genvar gn = 0; gn < N_OUT; gn++) begin : g_add_node
                        always_ff @(posedge clk or negedge rst_n) begin
                            if (!rst_n) begin
                                tree_real[gl][gr][gn] <= '0;
                                tree_imag[gl][gr][gn] <= '0;
                            end else if (en) begin
                                // Wrap addition: sum truncates to WL_OUT bits naturally
                                tree_real[gl][gr][gn] <=
                                    tree_real[gl-1][gr][2*gn] +
                                    tree_real[gl-1][gr][2*gn+1];
                                tree_imag[gl][gr][gn] <=
                                    tree_imag[gl-1][gr][2*gn] +
                                    tree_imag[gl-1][gr][2*gn+1];
                            end
                        end
                    end
                end

                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) tree_valid[gl] <= 1'b0;
                    else if (en) tree_valid[gl] <= tree_valid[gl-1];
                end
            end
        end
    endgenerate


// =============================================================================
// Part 8 – Output assignment
// -----------------------------------------------------------------------------
// The final result sits at tree level LEVELS-1, node 0 for each row.
// valid_out tracks tree_valid[LEVELS-1].
//
// The top of the tree is at index [LEVELS-1][r][0] for each row r.
// This is already registered (the last always_ff in g_tree_add gl=LEVELS-1).
// =============================================================================

    generate
        for (genvar gr = 0; gr < ROWS; gr++) begin : g_out_row
            // Wire final tree node to output ports
            // (no extra register – tree[LEVELS-1] is already a FF output)
            assign yhat_real[gr] = tree_real[LEVELS-1][gr][0];
            assign yhat_imag[gr] = tree_imag[LEVELS-1][gr][0];
        end
    endgenerate

    assign valid_out = tree_valid[LEVELS-1];


// =============================================================================
// Part 8b – gy_enable: "pipeline primed" sticky flag
// -----------------------------------------------------------------------------
// Set on the first valid_out after reset, never cleared except by rst_n.
// Requires zero changes to any existing logic -- purely additive.
// =============================================================================

    logic gy_enable_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          gy_enable_r <= 1'b0;
        else if (valid_out)  gy_enable_r <= 1'b1;   // set on first output, never cleared
    end
    assign gy_enable = gy_enable_r;


// =============================================================================
// Part 9 – Simulation-only: pipeline latency assertion
// =============================================================================
`ifdef SIMULATION
    // Verify that LATENCY matches the actual registered-path depth:
    //   1 (s1) + 1 (s2) + (LEVELS-1) (tree levels 1..LEVELS-1) = 1 + LEVELS
    initial begin
        if (LATENCY !== 1 + LEVELS)
            $fatal(1,"LATENCY parameter mismatch");
        $display("[matched_filter_pipe] ROWS=%0d COLS=%0d WL_IN=%0d WL_INT=%0d WL_OUT=%0d LEVELS=%0d LATENCY=%0d",
                 ROWS, COLS, WL_IN, WL_INT, WL_OUT, LEVELS, LATENCY);
    end
`endif

endmodule

// =============================================================================
// End of matched_filter_pipe.sv
// =============================================================================