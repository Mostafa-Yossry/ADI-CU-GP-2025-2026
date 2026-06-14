// ============================================================
// Module      : hermitian_pipe
// Description : Computes Hermitian (conjugate) transpose of a complex matrix
// Date        : June 2026
// ------------------------------------------------------------
// Synthesizable SystemVerilog module computing the Hermitian (conjugate)
// transpose of a complex matrix:
//
//      H^H = conj(H)^T
//
// for a channel matrix H in C^{ROWS x COLS}, producing H^H in C^{COLS x ROWS}.
//
//   H_{r,c}    = a + j b
//   H^H_{c,r}  = a - j b
//
// i.e.   Real(H^H[c][r]) =  Real(H[r][c])
//        Imag(H^H[c][r]) = -Imag(H[r][c])
//
// No multiplication, rounding, scaling, or saturation is performed anywhere
// in this module -- it is pure routing (transpose) plus two's-complement
// negation (conjugation) of the imaginary part.
// ============================================================

module hermitian_pipe #(
           
           // General Parameters (Dimensions)
           // --------------------------------------------------------------------------
           // Matrix dimensions: H is ROWS x COLS, H^H is COLS x ROWS
           // ==========================================================================
           parameter int                      ROWS            = 8       , // Number of rows in input matrix H
           parameter int                      COLS            = 8       , // Number of columns in input matrix H
   
           // Fixed-Point & Pipeline Parameters
           // --------------------------------------------------------------------------
           // Fixed-point format applies identically to input and output.
           // Format notation: Q<INT_BITS>.<FRAC_BITS> where the sign bit is
           // implicit and not counted; total WL = 1 + INT_BITS + FRAC_BITS.
           // Mode select:
           //   0 = combinational Hermitian (Mode 1), 0-cycle latency
           //   1 = registered Hermitian    (Mode 2), 1-cycle latency, 1 matrix/cycle
           // ==========================================================================
           parameter int                      WL              = 12      , // Total bit-width (1 sign bit + INT_BITS + FRAC_BITS)
           parameter int                      INT_BITS        = 0       , // Number of integer bits
           parameter int                      FRAC_BITS       = 11      , // Number of fractional bits
           parameter bit                      REGISTER_OUTPUT = 1         // 1 = Output is registered (1-cycle), 0 = Combinational

)(
    // Clock and Reset Signals
    input  logic                                clk                       , // System clock
    input  logic                                rst_n                     , // Active-low asynchronous reset

    // Input channel matrix H
    input  logic                                valid_in                  , // High when input matrices h_real/h_imag are valid
    input  logic signed [WL-1:0]                h_real  [0:ROWS-1][0:COLS-1], // Real part of input matrix H
    input  logic signed [WL-1:0]                h_imag  [0:ROWS-1][0:COLS-1], // Imaginary part of input matrix H

    // Output Hermitian matrix H^H
    output logic                                valid_out                 , // High when output matrices hh_real/hh_imag are valid
    output logic signed [WL-1:0]                hh_real [0:COLS-1][0:ROWS-1], // Real part of output Hermitian matrix (Transposed)
    output logic signed [WL-1:0]                hh_imag [0:COLS-1][0:ROWS-1]  // Imag part of output Hermitian matrix (Transposed + Negated)
);
    
/*...........................................Local Parameters..................................................*/

    // -------------------------------------------------------------------------
    // LATENCY: pipeline cycles from valid_in to valid_out.
    // Exposed as a localparam so that any wrapper or integration testbench can
    // read the latency via hierarchical reference without duplicating the
    // REGISTER_OUTPUT condition:
    //   localparam int HERM_LAT = u_herm.LATENCY;   // 0 or 1
    // -------------------------------------------------------------------------
    localparam int                      LATENCY          = REGISTER_OUTPUT ? 1 : 0;
    
    // Bounds checking for elaboration (negative when ROWS/COLS == 0)
    localparam int                      ROWS_RANGE_CHECK = ROWS - 1; 
    localparam int                      COLS_RANGE_CHECK = COLS - 1; 

/*...........................................Internal Signals..................................................*/
    
    // ----------------------------------------------------------------
    // Combinational intermediate signals (pre-registers)
    // ----------------------------------------------------------------
    logic signed [WL-1:0]               hh_real_c [0:COLS-1][0:ROWS-1];
    logic signed [WL-1:0]               hh_imag_c [0:COLS-1][0:ROWS-1];

/*...........................................Compile-Time Checks...............................................*/

`ifdef SIMULATION
    initial begin : param_check
        // Word-length consistency: WL must equal 1 + INT_BITS + FRAC_BITS.
        // A mismatch means the port width does not match the declared format,
        // causing silent truncation or zero-padding of the MSBs.
        if (WL != 1 + INT_BITS + FRAC_BITS)
            $fatal(1, "hermitian_pipe: WL mismatch: %0d != 1+%0d+%0d", WL, INT_BITS, FRAC_BITS);
            
        // Matrix dimensions must be at least 1 in each dimension.
        // ROWS=0 or COLS=0 produces empty generate loops, leaving all output
        // ports undriven -- the simulation will proceed silently with X outputs.
        if (ROWS < 1)
            $fatal(1, "hermitian_pipe: ROWS=%0d must be >= 1", ROWS);
        if (COLS < 1)
            $fatal(1, "hermitian_pipe: COLS=%0d must be >= 1", COLS);
    end
`endif

    // -----------------------------------------------------------------------------
    // Elaboration-time dimension guards (synthesis-visible)
    // The simulation-only $fatal above catches ROWS=0 or COLS=0 at runtime, but
    // a synthesis run never executes initial blocks.  These generate blocks produce
    // intentionally illegal negative-width wires whenever ROWS or COLS is zero,
    // which forces ANY elaboration tool to abort at elaboration rather than 
    // silently producing an empty netlist.
    // -----------------------------------------------------------------------------
    generate
        if (ROWS_RANGE_CHECK < 0) begin : ROWS_MUST_BE_AT_LEAST_1_ELABORATION_ERROR
            wire [(-1):0] illegal_signal_rows_must_be_positive;
        end
        if (COLS_RANGE_CHECK < 0) begin : COLS_MUST_BE_AT_LEAST_1_ELABORATION_ERROR
            wire [(-1):0] illegal_signal_cols_must_be_positive;
        end
    endgenerate

/*...........................................Combinational Logic...............................................*/

    // -----------------------------------------------------------------------------
    // Combinational Hermitian (transpose + conjugate)
    //   hh_real_c[c][r] =  h_real[r][c]      (pure transpose, no logic)
    //   hh_imag_c[c][r] = -h_imag[r][c]      (transpose + two's-complement negate,
    //                                         which wraps -2^(WL-1) -> -2^(WL-1)
    //                                         exactly as MATLAB Wrap-mode fi())
    // -----------------------------------------------------------------------------
    generate
        for (genvar gr = 0; gr < ROWS; gr++) begin : g_src_row
            for (genvar gc = 0; gc < COLS; gc++) begin : g_src_col
                assign hh_real_c[gc][gr] =  h_real[gr][gc];
                assign hh_imag_c[gc][gr] = -h_imag[gr][gc];
            end
        end
    endgenerate

/*...........................................Output Stage......................................................*/

    // ----------------------------------------------------------------
    // Pipeline selection based on REGISTER_OUTPUT
    // ----------------------------------------------------------------
    generate
        if (REGISTER_OUTPUT) begin : g_registered
            
            for (genvar gc = 0; gc < COLS; gc++) begin : g_out_col
                for (genvar gr = 0; gr < ROWS; gr++) begin : g_out_row
                    always_ff @(posedge clk or negedge rst_n) begin
                        if (!rst_n) begin
                            hh_real[gc][gr] <= '0;
                            hh_imag[gc][gr] <= '0;
                        end else begin
                            hh_real[gc][gr] <= hh_real_c[gc][gr];
                            hh_imag[gc][gr] <= hh_imag_c[gc][gr];
                        end
                    end
                end
            end

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) valid_out <= 1'b0;
                else        valid_out <= valid_in;
            end

        end else begin : g_combinational
            
            // ------------------------------------------------------------------
            // Mode 1 (REGISTER_OUTPUT=0): purely combinational.
            // clk and rst_n are declared on the module port list for interface
            // uniformity, but they drive no logic here.
            //
            // Lint suppress: the following attributes silence "unconnected
            // input" warnings for clk and rst_n in this branch on common tools.
            // They are non-functional and removed by synthesis.
            // ------------------------------------------------------------------
            // synthesis translate_off
            // pragma coverage off
            // synthesis translate_on
            
            for (genvar gc = 0; gc < COLS; gc++) begin : g_out_col
                for (genvar gr = 0; gr < ROWS; gr++) begin : g_out_row
                    assign hh_real[gc][gr] = hh_real_c[gc][gr];
                    assign hh_imag[gc][gr] = hh_imag_c[gc][gr];
                end
            end

            assign valid_out = valid_in;
            
        end
    endgenerate

endmodule

// ------------------------------------------------------------
// Intended use
// ------------------------------------------------------------
// This module is designed to sit upstream of matched_filter_pipe and produce
// its hh_real / hh_imag coefficient matrices. The output port shapes are
// [0:COLS-1][0:ROWS-1] (the Hermitian-transposed shape). For the common
// square case (ROWS == COLS, e.g. the matched filter's default 8x8), this is
// the same [0:7][0:7] shape as matched_filter_pipe's hh_real/hh_imag ports
// and can be wired directly:
//
//   hermitian_pipe   #(.ROWS(8), .COLS(8), .WL(12), .INT_BITS(0), .FRAC_BITS(11))
//       herm ( .h_real(H_real), .h_imag(H_imag), .hh_real(HH_real), .hh_imag(HH_imag), ... );
//
//   matched_filter_pipe #(.ROWS(8), .COLS(8), .WL_IN(12), .INT_BITS_IN(0), .FRAC_BITS_IN(11), ...)
//       mf ( .hh_real(HH_real), .hh_imag(HH_imag), ... );
//
// For a non-square H (ROWS_H x COLS_H feeding a matched filter with
// MF_ROWS x MF_COLS = COLS_H x ROWS_H), instantiate this module with
// ROWS=ROWS_H, COLS=COLS_H; the [0:COLS_H-1][0:ROWS_H-1] output shape then
// equals the matched filter's [0:MF_ROWS-1][0:MF_COLS-1] shape directly.
//
// ------------------------------------------------------------
// Fixed-point format table
// ------------------------------------------------------------
//   ┌───────────────┬──────────────────────────┬───────┬──────────────────┐
//   │ Signal        │ Format                   │ Width │ Notes            │
//   ├───────────────┼──────────────────────────┼───────┼──────────────────┤
//   │ h_real, h_imag│ Q(INT_BITS).(FRAC_BITS)  │ WL    │ input            │
//   │ hh_real       │ Q(INT_BITS).(FRAC_BITS)  │ WL    │ = h_real         │
//   │               │                          │       │   (pure copy)    │
//   │ hh_imag       │ Q(INT_BITS).(FRAC_BITS)  │ WL    │ = wrap-negate of │
//   │               │                          │       │   h_imag         │
//   └───────────────┴──────────────────────────┴───────┴──────────────────┘
//
//   WL = 1 + INT_BITS + FRAC_BITS  (checked by $fatal at elaboration time)
//   No word-length growth, no truncation, no rounding, no saturation.
//
// ------------------------------------------------------------
// Pipeline latency table
// ------------------------------------------------------------
//   ┌───────────────────┬──────────────────────────────────────────────────┐
//   │ REGISTER_OUTPUT=0 │ Combinational. valid_out = valid_in.             │
//   │ (Mode 1)          │ Latency = 0 cycles. Pure wiring + negation logic.│
//   ├───────────────────┼──────────────────────────────────────────────────┤
//   │ REGISTER_OUTPUT=1 │ All COLS x ROWS outputs (real & imag) and        │
//   │ (Mode 2, default) │ valid_out registered on the same clock edge.     │
//   │                   │ Latency = 1 cycle. Throughput = 1 matrix/cycle.  │
//   └───────────────────┴──────────────────────────────────────────────────┘
//
// ------------------------------------------------------------
// MATLAB equivalence
// ------------------------------------------------------------
//   MATLAB reference:
//       HH = H';            % ctranspose -- same as conj(H).'
//
//   For a fi() object with two's-complement (Wrap) storage, MATLAB's unary
//   minus on the most-negative representable value wraps back to itself:
//
//       x = fi(-2^(WL-1), 1, WL, FRAC_BITS, 'OverflowAction','Wrap');
//       -x  ==  x                      (wraps, does NOT saturate to +2^(WL-1)-1)
//
//   In two's-complement hardware, unary minus is implemented as (~x + 1).
//   For x = 1000...0 (the most negative value):
//       ~x      = 0111...1
//       ~x + 1  = 1000...0  =  x
//   i.e. plain SystemVerilog `-h_imag[r][c]` on a signed WL-bit value
//   *already* implements exactly this wrap behavior, because all
//   SystemVerilog arithmetic on fixed-width vectors is implicitly modulo
//   2^WL. No special-casing is required or present in this module --
//   `assign hh_imag_c[c][r] = -h_imag[r][c];` is bit-exact with MATLAB's
//   Wrap-mode ctranspose() for every input value, including -2^(WL-1).
//
// ------------------------------------------------------------
// Corner cases (all handled automatically by the formula above)
// ------------------------------------------------------------
//   imag = 0          -> hh_imag = -0 = 0                       (trivial)
//   imag = +2^(WL-1)-1-> hh_imag = -(2^(WL-1)-1) = -2^(WL-1)+1  (normal negate)
//   imag = -2^(WL-1)  -> hh_imag = -2^(WL-1)                    (wraps to itself,
//                                                                matches MATLAB Wrap)
//   all-zero matrix   -> hh_real = hh_imag = 0 everywhere
//   identity matrix   -> transpose of identity = identity;
//                        diagonal imag entries are typically 0, so
//                        conjugation is a no-op on the diagonal
//   random matrices   -> exact element-by-element transpose + negate
//
// ------------------------------------------------------------
// Resource analysis
// ------------------------------------------------------------
//   Combinational (Mode 1):
//     - hh_real: pure wire renaming (transpose) -- zero logic.
//     - hh_imag: ROWS*COLS independent WL-bit two's-complement negators,
//                each a WL-bit inverter + WL-bit incrementer (equivalent to
//                a WL-bit adder with one operand tied to all-1s and carry-in
//                tied to 1). For the default 8x8/WL=12 configuration this is
//                64 x 12-bit negators -- a small fraction of the multiplier
//                resources used by matched_filter_pipe itself.
//     - No multipliers, no adders combining different matrix elements,
//       no muxes (every output bit maps to exactly one input bit or its
//       negation).
//
//   Registered (Mode 2, default):
//     - Adds 2 * ROWS * COLS * WL flip-flops (for default 8x8/WL=12:
//       2*8*8*12 = 1536 FFs) plus 1 flop for valid_out.
//     - Negation logic is identical to Mode 1, evaluated combinationally
//       ahead of the output registers.
//
// ------------------------------------------------------------
// Timing analysis
// ------------------------------------------------------------
//   The critical path through this module (Mode 1, or the combinational
//   cone feeding the Mode 2 registers) is a single WL-bit two's-complement
//   negation -- i.e. one WL-bit ripple/carry chain. This is dramatically
//   shorter than matched_filter_pipe's Stage 1 critical path (a 16x16->32
//   signed multiplier followed by a subtract/add for the complex product),
//   so this module is not expected to be timing-critical in any
//   configuration where it feeds matched_filter_pipe.
//
//   Mode 2 (registered) is recommended whenever this module sits at a clock
//   domain boundary, behind a long interconnect, or simply to keep the
//   negation logic out of the matched filter's Stage 1 timing path
//   entirely. It adds exactly 1 cycle of latency, which the downstream
//   matched filter's hh_load timing constraint (hh_load for frame N must be
//   registered at least one cycle before valid_in for frame N) can absorb
//   by sourcing hh_load directly from this module's valid_out.
//
// ------------------------------------------------------------
// Verification strategy (see tb_hermitian_pipe.sv)
// ------------------------------------------------------------
//   1. Identity-matrix test       -- verifies transpose indexing.
//   2. All-zero matrix test       -- trivial baseline.
//   3. Full-scale (+max) test     -- verifies normal negation at the positive
//                                    extreme (2^(WL-1)-1 -> -2^(WL-1)+1).
//   4. Minimum-negative test      -- verifies the -2^(WL-1) wrap corner case
//                                    on the imaginary part (per MATLAB Wrap
//                                    equivalence above).
//   5. Randomized matrices        -- bulk element-by-element bit-exact check
//                                    against a golden model computed in the
//                                    testbench using the same formula.
//   6. Back-to-back burst         -- confirms 1-cycle latency and 1
//                                    matrix/cycle throughput in Mode 2.
//   7. File-based MATLAB vectors  -- H_binary.txt / HH_binary.txt
//
// ------------------------------------------------------------
// Integration note: no pipeline-enable (en) input
// ------------------------------------------------------------
// This module has no 'en' port.  In REGISTER_OUTPUT=1 mode the output
// registers update every clock cycle unconditionally.
//
// When hermitian_pipe feeds matched_filter_pipe (which does have 'en'):
//   - Asserting en=0 on the matched filter freezes its internal pipeline but
//     does NOT freeze hermitian_pipe's output registers.
//   - hh_load on the matched filter is also independent of en (by design), so
//     coefficients can be updated during a stall.
//   - The integrating control layer is responsible for not asserting hh_load
//     into the matched filter with stale hermitian_pipe outputs mid-burst.
//   - The simplest safe scheme: source hh_load directly from valid_out of this
//     module (1-cycle registered mode) and deassert valid_in to this module
//     whenever a new channel matrix is not available.  No extra gating needed.
// ============================================================