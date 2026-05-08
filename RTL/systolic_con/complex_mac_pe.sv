// =============================================================================
// complex_mac_pe.sv
// -----------------------------------------------------------------------------
// MATCHED FILTER PE — Fixed-point format matches MATLAB golden exactly.
//
// MATLAB model: MULTIPLICATION_TYPES('fixed_point_Z_8x8', 12)
//   WL_OP  = 16  (Q1.15 after input widening)
//   WL_ACC = 12  (Q5.7 accumulator / output)
//
// Fixed-point chain:
//   Input (boundary)  : Q1.11,  12-bit   (WL_IN  = 12)
//   After widening    : Q1.15,  16-bit   (WL_INT = 16)  [4 zero LSBs]
//   After multiply    : Q2.30,  32-bit   (full precision product)
//   RIGHT_SH = FRAC_PROD - FRAC_ACC = 30 - 7 = 23
//   After rounding    : Q5.7,   12-bit   (WL_ACC = 12)  [convergent]
//   Output Z          : Q5.7,   12-bit   — matches MATLAB T.Q1_11 exactly
//
// Accumulation model:
//   The MATLAB staged accumulator (Q2_->Q3_->Q4_->Q5_) widens format
//   at each doubling of K, but the FINAL output is always Q5.7 (12-bit).
//   The RTL accumulates directly in Q5.7 throughout — each product is
//   rounded to Q5.7 before being added, matching the MATLAB golden
//   because the golden files are generated with length=12 (Q5.7 output).
//   Rounding method: Convergent (round-half-to-even), matching fimath.
//
// Self-accumulation (COLS=1):
//   e_in is hardwired to 0 (leftmost column). e_out self-accumulates:
//     e_out += round(product)   when valid_in=1
//     e_out holds               when valid_in=0
//   rst_n clears e_out between transactions.
// =============================================================================

module complex_mac_pe #(
    parameter WL_OP  = 16,   // operand word length  (Q1.15 after widening)
    parameter WL_ACC = 12    // accumulator word length (Q5.7)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,

    input  wire signed [WL_OP-1:0]  a_real,
    input  wire signed [WL_OP-1:0]  a_imag,
    input  wire signed [WL_OP-1:0]  b_real,
    input  wire signed [WL_OP-1:0]  b_imag,

    input  wire signed [WL_ACC-1:0] e_in_real,
    input  wire signed [WL_ACC-1:0] e_in_imag,

    input  wire        valid_in,

    output reg  signed [WL_OP-1:0]  a_pass_real,
    output reg  signed [WL_OP-1:0]  a_pass_imag,
    output reg  signed [WL_OP-1:0]  b_pass_real,
    output reg  signed [WL_OP-1:0]  b_pass_imag,

    output reg  signed [WL_ACC-1:0] e_out_real,
    output reg  signed [WL_ACC-1:0] e_out_imag,

    output reg         valid_out
);

// ---------------------------------------------------------------------------
// STAGE 1: Full-precision 16x16 complex multiply -> Q2.30
// ---------------------------------------------------------------------------
wire signed [2*WL_OP-1:0] prod_rr = a_real * b_real;
wire signed [2*WL_OP-1:0] prod_ii = a_imag * b_imag;
wire signed [2*WL_OP-1:0] prod_ri = a_real * b_imag;
wire signed [2*WL_OP-1:0] prod_ir = a_imag * b_real;

wire signed [2*WL_OP-1:0] mult_real = prod_rr - prod_ii;
wire signed [2*WL_OP-1:0] mult_imag = prod_ri + prod_ir;

// ---------------------------------------------------------------------------
// STAGE 2: Align Q2.30 -> Q5.7 using CONVERGENT ROUNDING
//
// FRAC_PROD = 2*WL_OP - 2 = 30   (Q2.30 product fractional bits)
// FRAC_ACC  = WL_ACC - 5   =  7   (Q5.7 accumulator: 5 integer, 7 fractional)
// RIGHT_SH  = 30 - 7       = 23   (bits to discard)
//
// Convergent rounding (round-half-to-even):
//   round = guard & (sticky | lsb)
//   where guard  = bit[RIGHT_SH-1]  (first discarded bit)
//         sticky = OR(bits[RIGHT_SH-2:0])  (any remaining discarded bits)
//         lsb    = retained result bit[0]  (for tie-breaking)
// ---------------------------------------------------------------------------
localparam FRAC_PROD = 2*WL_OP - 2;           // 30
localparam FRAC_ACC  = WL_ACC - 5;            //  7  (Q5.7)
localparam RIGHT_SH  = FRAC_PROD - FRAC_ACC;  // 23

// Truncated (arithmetic right shift)
wire signed [WL_ACC-1:0] trunc_real = mult_real >>> RIGHT_SH;
wire signed [WL_ACC-1:0] trunc_imag = mult_imag >>> RIGHT_SH;

// Guard bit (first dropped bit)
wire guard_real = mult_real[RIGHT_SH-1];
wire guard_imag = mult_imag[RIGHT_SH-1];

// Sticky bit (OR of remaining dropped bits)
wire sticky_real = |mult_real[RIGHT_SH-2:0];
wire sticky_imag = |mult_imag[RIGHT_SH-2:0];

// LSB of retained result (for tie-breaking)
wire lsb_real = trunc_real[0];
wire lsb_imag = trunc_imag[0];

// Convergent round decision
wire round_real = guard_real & (sticky_real | lsb_real);
wire round_imag = guard_imag & (sticky_imag | lsb_imag);

// Rounded product aligned to Q5.7
wire signed [WL_ACC-1:0] prod_real_aligned = trunc_real + {{(WL_ACC-1){1'b0}}, round_real};
wire signed [WL_ACC-1:0] prod_imag_aligned = trunc_imag + {{(WL_ACC-1){1'b0}}, round_imag};

// ---------------------------------------------------------------------------
// STAGE 3: Registered self-accumulate + pass-through
//
// e_out updated ONLY when valid_in=1 (hold otherwise).
// Self-accumulates: e_out += prod_aligned  (e_in unused for COLS=1).
// rst_n (async) clears e_out between transactions.
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        a_pass_real <= {WL_OP{1'b0}};
        a_pass_imag <= {WL_OP{1'b0}};
        b_pass_real <= {WL_OP{1'b0}};
        b_pass_imag <= {WL_OP{1'b0}};
        e_out_real  <= {WL_ACC{1'b0}};
        e_out_imag  <= {WL_ACC{1'b0}};
        valid_out   <= 1'b0;
    end else if (en) begin
        a_pass_real <= a_real;
        a_pass_imag <= a_imag;
        b_pass_real <= b_real;
        b_pass_imag <= b_imag;

        if (valid_in) begin
            e_out_real <= e_out_real + prod_real_aligned;
            e_out_imag <= e_out_imag + prod_imag_aligned;
        end
        // else: HOLD — partial sum survives across idle cycles

        valid_out <= valid_in;
    end
end

endmodule