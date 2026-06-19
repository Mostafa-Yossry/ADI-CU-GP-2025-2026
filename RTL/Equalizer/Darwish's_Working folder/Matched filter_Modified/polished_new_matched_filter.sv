// ============================================================
// Module      : matched_filter_pipe
// Description : Pipelined Matched Filter for MIMO Equalization
// Date        : June 2026
// ------------------------------------------------------------
// Synthesizable SystemVerilog module computing a matched filter 
// dot-product across a pipelined balanced adder tree.
// ============================================================

module matched_filter_pipe #(
           
           // Matrix Dimensions
           // --------------------------------------------------------------------------
           // MF_COLS MUST be a power of two for the balanced adder tree.
           // ==========================================================================
           parameter int                      MF_ROWS               = 8       , // Output elements (rows of H^H)
           parameter int                      MF_COLS               = 8       , // Dot-product length (columns of H^H)
           
           // Input Fixed-Point Format (applies to both y and H^H)
           // --------------------------------------------------------------------------
           // Default: Q1.11 -> 12-bit signed, 0 integer bits, 11 fractional bits
           // ==========================================================================
           parameter int                      MF_WL_IN              = 12      , // Total bit-width for input
           parameter int                      MF_INT_BITS_IN        = 0       , // Integer bits for input
           parameter int                      MF_FRAC_BITS_IN       = 11      , // Fractional bits for input

           // Internal Widened Format (Widened before multiply)
           // --------------------------------------------------------------------------
           // Default: Q1.15 -> 16-bit signed, 0 integer bits, 15 fractional bits
           // Widening appends zero LSBs and sign-extends the integer portion.
           // ==========================================================================
           parameter int                      MF_INTERNAL_WL        = 16      , // Total internal bit-width
           parameter int                      MF_INTERNAL_INT_BITS  = 0       , // Internal integer bits
           parameter int                      MF_INTERNAL_FRAC_BITS = 15      , // Internal fractional bits

           // Output Fixed-Point Format (Post-rounding format in adder tree)
           // --------------------------------------------------------------------------
           // Default: Q5.11 -> 16-bit signed, 4 integer bits, 11 fractional bits
           // ==========================================================================
           parameter int                      MF_WL_OUT             = 16      , // Total output bit-width
           parameter int                      MF_INT_BITS_OUT       = 4       , // Output integer bits
           parameter int                      MF_FRAC_BITS_OUT      = 11        // Output fractional bits

)(
    // Clock and Control
    input  logic                                clk                       , // System clock
    input  logic                                rst_n                     , // Active-low asynchronous reset
    input  logic                                en                        , // Pipeline enable (stalls all stages when low)

    // H^H Coefficient Load Interface
    // -------------------------------------------------------------------------
    // Assert hh_load for exactly one rising clock edge to latch all ROWSxCOLS
    // complex coefficients. hh_real/imag must be stable on that posedge.
    // -------------------------------------------------------------------------
    input  logic                                hh_load                   , // Latch enable for coefficients
    input  logic signed [MF_WL_IN-1:0]          hh_real [0:MF_ROWS-1][0:MF_COLS-1], // Real coefficients (H^H)
    input  logic signed [MF_WL_IN-1:0]          hh_imag [0:MF_ROWS-1][0:MF_COLS-1], // Imag coefficients (H^H)

    // Streaming y Vector Input (One new vector per cycle)
    input  logic                                valid_in                  , // High when input y vector is valid
    input  logic signed [MF_WL_IN-1:0]          y_real  [0:MF_COLS-1]     , // Real part of input vector y
    input  logic signed [MF_WL_IN-1:0]          y_imag  [0:MF_COLS-1]     , // Imag part of input vector y

    // Outputs
    // -------------------------------------------------------------------------
    // valid_out asserts LATENCY cycles after valid_in. LATENCY = 1 + $clog2(MF_COLS).
    // gy_enable is a "pipeline primed" flag that asserts on the first valid_out.
    // -------------------------------------------------------------------------
    output logic                                valid_out                 , // High when output yhat is valid
    output logic                                gy_enable                 , // Pipeline primed sticky flag
    output logic signed [MF_WL_OUT-1:0]         yhat_real [0:MF_ROWS-1]   , // Real part of filtered output
    output logic signed [MF_WL_OUT-1:0]         yhat_imag [0:MF_ROWS-1]     // Imag part of filtered output
);

/*...........................................Local Parameters..................................................*/

    // -------------------------------------------------------------------------
    // Derived Fixed-Point Parameters
    // -------------------------------------------------------------------------
    localparam int                      FRAC_WIDEN       = MF_INTERNAL_FRAC_BITS - MF_FRAC_BITS_IN;
    
    // Full-precision product format (MATLAB 'ProductMode','FullPrecision')
    localparam int                      PROD_FRAC        = MF_INTERNAL_FRAC_BITS + MF_INTERNAL_FRAC_BITS;  // 30 default
    localparam int                      PROD_INT         = MF_INTERNAL_INT_BITS  + MF_INTERNAL_INT_BITS;   // 0 default
    localparam int                      WL_PROD          = 2 * MF_INTERNAL_WL;                             // 32 default
    
    // Right-shift to align product to output format (MATLAB 'Convergent' rounding)
    localparam int                      RIGHT_SH         = PROD_FRAC - MF_FRAC_BITS_OUT;                   // 19 default
    
    // Adder-tree depth and total pipeline latency
    localparam int                      LEVELS           = $clog2(MF_COLS);                                // 3 default
    localparam int                      LATENCY          = 1 + LEVELS;                                     // 4 default
    localparam int                      COLS_POW2_CHECK  = MF_COLS & (MF_COLS - 1);
    localparam int                      NODES_L0         = MF_COLS / 2;                                    // outputs of level-0 adder = MF_COLS/2

/*...........................................Internal Signals..................................................*/

    // H^H Coefficient Registers (Widened internal format)
    logic signed [MF_INTERNAL_WL-1:0]           coef_real [0:MF_ROWS-1][0:MF_COLS-1];
    logic signed [MF_INTERNAL_WL-1:0]           coef_imag [0:MF_ROWS-1][0:MF_COLS-1];

    // y Input Widening (Combinational)
    logic signed [MF_INTERNAL_WL-1:0]           y_real_w  [0:MF_COLS-1];
    logic signed [MF_INTERNAL_WL-1:0]           y_imag_w  [0:MF_COLS-1];

    // Stage 1: Parallel complex multipliers
    logic signed [WL_PROD-1:0]                  s1_mult_real [0:MF_ROWS-1][0:MF_COLS-1];
    logic signed [WL_PROD-1:0]                  s1_mult_imag [0:MF_ROWS-1][0:MF_COLS-1];
    logic                                       s1_valid;

    // Stage 2: Convergent rounding + level-0 adder
    logic signed [MF_WL_OUT-1:0]                s2_sum_real [0:MF_ROWS-1][0:NODES_L0-1];
    logic signed [MF_WL_OUT-1:0]                s2_sum_imag [0:MF_ROWS-1][0:NODES_L0-1];
    logic                                       s2_valid;

    // Stages 3... Balanced adder tree
    logic signed [MF_WL_OUT-1:0]                tree_real [0:LEVELS-1][0:MF_ROWS-1][0:NODES_L0-1];
    logic signed [MF_WL_OUT-1:0]                tree_imag [0:LEVELS-1][0:MF_ROWS-1][0:NODES_L0-1];
    logic                                       tree_valid [0:LEVELS-1];
    
    // gy_enable sticky flag
    logic                                       gy_enable_r;

/*...........................................Compile-Time Checks...............................................*/

`ifdef SIMULATION
    initial begin : param_check
        if (MF_WL_IN  != 1 + MF_INT_BITS_IN  + MF_FRAC_BITS_IN)             $fatal(1, "MF_WL_IN mismatch");
        if (MF_INTERNAL_WL != 1 + MF_INTERNAL_INT_BITS + MF_INTERNAL_FRAC_BITS) $fatal(1, "MF_INTERNAL_WL mismatch");
        if (MF_WL_OUT != 1 + MF_INT_BITS_OUT + MF_FRAC_BITS_OUT)            $fatal(1, "MF_WL_OUT mismatch");
        if (RIGHT_SH >= WL_PROD)                                            $fatal(1, "WL_PROD too narrow for rounding shift");
        if (RIGHT_SH < 1)                                                   $fatal(1, "output format wider than product");
        if ((MF_COLS & (MF_COLS - 1)) != 0)                                 $fatal(1, "MF_COLS must be a power of two");
        if (FRAC_WIDEN < 0)                                                 $fatal(1, "internal format less precise than input");
        if (MF_INTERNAL_INT_BITS < MF_INT_BITS_IN)                          $fatal(1, "internal format narrower than input");
    end
`endif

    // Elaboration-time dimension guards (synthesis-visible)
    generate
        if (COLS_POW2_CHECK != 0) begin : COLS_NOT_POWER_OF_TWO_ELABORATION_ERROR
            wire [(-1):0] illegal_signal_cols_must_be_power_of_two;
        end
    endgenerate

/*...........................................H^H Coefficient Load..............................................*/

    // -----------------------------------------------------------------------------
    // Widen input to internal format: sign-extend int portion, zero-pad frac LSBs
    // MATLAB eq: coef = fi(hh, 1, MF_INTERNAL_WL, MF_INTERNAL_FRAC_BITS)
    // -----------------------------------------------------------------------------
    generate
        for (genvar gr = 0; gr < MF_ROWS; gr++) begin : g_coef_row
            for (genvar gk = 0; gk < MF_COLS; gk++) begin : g_coef_col
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        coef_real[gr][gk] <= '0;
                        coef_imag[gr][gk] <= '0;
                    end else if (hh_load) begin
                        coef_real[gr][gk] <= signed'(
                            {{(MF_INTERNAL_WL - MF_WL_IN - FRAC_WIDEN){hh_real[gr][gk][MF_WL_IN-1]}},
                              hh_real[gr][gk],
                             {FRAC_WIDEN{1'b0}}}
                        );
                        coef_imag[gr][gk] <= signed'(
                            {{(MF_INTERNAL_WL - MF_WL_IN - FRAC_WIDEN){hh_imag[gr][gk][MF_WL_IN-1]}},
                              hh_imag[gr][gk],
                             {FRAC_WIDEN{1'b0}}}
                        );
                    end
                end
            end
        end
    endgenerate

/*...........................................Y Input Widening..................................................*/

    // -----------------------------------------------------------------------------
    // Combinational mirroring of coefficient widening for vector y
    // MATLAB eq: yw = fi(y, 1, MF_INTERNAL_WL, MF_INTERNAL_FRAC_BITS)
    // -----------------------------------------------------------------------------
    generate
        for (genvar gk = 0; gk < MF_COLS; gk++) begin : g_widen_y
            assign y_real_w[gk] = signed'(
                {{(MF_INTERNAL_WL - MF_WL_IN - FRAC_WIDEN){y_real[gk][MF_WL_IN-1]}},
                  y_real[gk],
                 {FRAC_WIDEN{1'b0}}}
            );
            assign y_imag_w[gk] = signed'(
                {{(MF_INTERNAL_WL - MF_WL_IN - FRAC_WIDEN){y_imag[gk][MF_WL_IN-1]}},
                  y_imag[gk],
                 {FRAC_WIDEN{1'b0}}}
            );
        end
    endgenerate

/*...........................................STAGE 1: Multipliers..............................................*/

    // -----------------------------------------------------------------------------
    // Complex product: (coef_r + j*coef_i) * (y_r + j*y_i)
    // No rounding occurs here; full precision is retained.
    // -----------------------------------------------------------------------------
    generate
        for (genvar gr = 0; gr < MF_ROWS; gr++) begin : g_s1_row
            for (genvar gk = 0; gk < MF_COLS; gk++) begin : g_s1_col

                logic signed [WL_PROD-1:0] p_rr, p_ii, p_ri, p_ir;

                assign p_rr = coef_real[gr][gk] * y_real_w[gk];
                assign p_ii = coef_imag[gr][gk] * y_imag_w[gk];
                assign p_ri = coef_real[gr][gk] * y_imag_w[gk];
                assign p_ir = coef_imag[gr][gk] * y_real_w[gk];

                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        s1_mult_real[gr][gk] <= '0;
                        s1_mult_imag[gr][gk] <= '0;
                    end else if (en) begin
                        s1_mult_real[gr][gk] <= p_rr - p_ii;
                        s1_mult_imag[gr][gk] <= p_ri + p_ir;
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)  s1_valid <= 1'b0;
        else if (en) s1_valid <= valid_in;
    end

/*...........................................STAGE 2: Rounding & L0 Adder......................................*/

    // -----------------------------------------------------------------------------
    // Convergent rounding (round-half-to-even) & Level-0 pair sum (wrap arithmetic)
    // MATLAB eq: rnd = fi(P, 1, MF_WL_OUT, MF_FRAC_BITS_OUT) % Convergent, Wrap
    // -----------------------------------------------------------------------------
    generate
        for (genvar gr = 0; gr < MF_ROWS; gr++) begin : g_s2_row
            for (genvar gk = 0; gk < NODES_L0; gk++) begin : g_s2_node

                // Node 'a' (index 2*gk)
                logic signed [MF_WL_OUT-1:0] tr_a_r, tr_a_i;
                logic                        g_a_r,  g_a_i;
                logic                        st_a_r, st_a_i;
                logic signed [MF_WL_OUT-1:0] rnd_a_r, rnd_a_i;

                assign tr_a_r  = signed'(s1_mult_real[gr][2*gk] >>> RIGHT_SH);
                assign tr_a_i  = signed'(s1_mult_imag[gr][2*gk] >>> RIGHT_SH);
                assign g_a_r   = s1_mult_real[gr][2*gk][RIGHT_SH-1];
                assign g_a_i   = s1_mult_imag[gr][2*gk][RIGHT_SH-1];

                if (RIGHT_SH >= 2) begin : g_sticky_a
                    assign st_a_r = |s1_mult_real[gr][2*gk][RIGHT_SH-2:0];
                    assign st_a_i = |s1_mult_imag[gr][2*gk][RIGHT_SH-2:0];
                end else begin : g_no_sticky_a
                    assign st_a_r = 1'b0;
                    assign st_a_i = 1'b0;
                end

                assign rnd_a_r = tr_a_r + MF_WL_OUT'({(MF_WL_OUT-1)'(0), (g_a_r & (st_a_r | tr_a_r[0]))});
                assign rnd_a_i = tr_a_i + MF_WL_OUT'({(MF_WL_OUT-1)'(0), (g_a_i & (st_a_i | tr_a_i[0]))});

                // Node 'b' (index 2*gk+1)
                logic signed [MF_WL_OUT-1:0] tr_b_r, tr_b_i;
                logic                        g_b_r,  g_b_i;
                logic                        st_b_r, st_b_i;
                logic signed [MF_WL_OUT-1:0] rnd_b_r, rnd_b_i;

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

                assign rnd_b_r = tr_b_r + MF_WL_OUT'({(MF_WL_OUT-1)'(0), (g_b_r & (st_b_r | tr_b_r[0]))});
                assign rnd_b_i = tr_b_i + MF_WL_OUT'({(MF_WL_OUT-1)'(0), (g_b_i & (st_b_i | tr_b_i[0]))});

                // Level-0 Pair Sum
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
        if (!rst_n)  s2_valid <= 1'b0;
        else if (en) s2_valid <= s1_valid;
    end

/*...........................................STAGES 3+: Adder Tree.............................................*/

    // -----------------------------------------------------------------------------
    // Levels 1 ... LEVELS-1: Pairwise wrap addition with pipeline registers.
    // -----------------------------------------------------------------------------
    generate
        for (genvar gl = 0; gl < LEVELS; gl++) begin : g_tree_level

            localparam int N_IN  = (gl == 0) ? NODES_L0 : (NODES_L0 >> (gl-1));
            localparam int N_OUT = NODES_L0 >> gl;

            if (gl == 0) begin : g_tree_seed
                for (genvar gr = 0; gr < MF_ROWS; gr++) begin : g_seed_row
                    for (genvar gn = 0; gn < N_IN; gn++) begin : g_seed_node
                        assign tree_real[0][gr][gn] = s2_sum_real[gr][gn];
                        assign tree_imag[0][gr][gn] = s2_sum_imag[gr][gn];
                    end
                end
                assign tree_valid[0] = s2_valid;

            end else begin : g_tree_add
                for (genvar gr = 0; gr < MF_ROWS; gr++) begin : g_add_row
                    for (genvar gn = 0; gn < N_OUT; gn++) begin : g_add_node
                        always_ff @(posedge clk or negedge rst_n) begin
                            if (!rst_n) begin
                                tree_real[gl][gr][gn] <= '0;
                                tree_imag[gl][gr][gn] <= '0;
                            end else if (en) begin
                                tree_real[gl][gr][gn] <= tree_real[gl-1][gr][2*gn] + tree_real[gl-1][gr][2*gn+1];
                                tree_imag[gl][gr][gn] <= tree_imag[gl-1][gr][2*gn] + tree_imag[gl-1][gr][2*gn+1];
                            end
                        end
                    end
                end

                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n)  tree_valid[gl] <= 1'b0;
                    else if (en) tree_valid[gl] <= tree_valid[gl-1];
                end
            end
        end
    endgenerate

/*...........................................Output Assignment.................................................*/

    generate
        for (genvar gr = 0; gr < MF_ROWS; gr++) begin : g_out_row
            assign yhat_real[gr] = tree_real[LEVELS-1][gr][0];
            assign yhat_imag[gr] = tree_imag[LEVELS-1][gr][0];
        end
    endgenerate

    assign valid_out = tree_valid[LEVELS-1];

    // gy_enable sticky flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          gy_enable_r <= 1'b0;
        else if (valid_out)  gy_enable_r <= 1'b1; 
    end
    
    assign gy_enable = gy_enable_r;

/*...........................................Simulation Assertions.............................................*/

`ifdef SIMULATION
    initial begin
        if (LATENCY !== 1 + LEVELS)
            $fatal(1,"LATENCY parameter mismatch");
        $display("[matched_filter_pipe] MF_ROWS=%0d MF_COLS=%0d MF_WL_IN=%0d MF_INTERNAL_WL=%0d MF_WL_OUT=%0d LEVELS=%0d LATENCY=%0d",
                 MF_ROWS, MF_COLS, MF_WL_IN, MF_INTERNAL_WL, MF_WL_OUT, LEVELS, LATENCY);
    end
`endif

endmodule
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