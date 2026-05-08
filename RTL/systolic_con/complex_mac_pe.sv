// =============================================================================
// complex_mac_pe.sv   (also provided as complex_mac_pe.v — identical content)
// -----------------------------------------------------------------------------
// FIXED VERSION: else-branch pass-through removed.
// e_out HOLDS when valid_in=0 so partial sums survive across idle cycles.
// =============================================================================

module complex_mac_pe #(
    parameter WL_OP  = 16,   // operand word length  (Q1.15)
    parameter WL_ACC = 16    // accumulator / e word length (Q5.11)
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
/*
// ---------------------------------------------------------------------------
// STAGE 2: Align Q2.30 -> Q5.11 (right-shift by 19)
// ---------------------------------------------------------------------------
localparam FRAC_PROD = 2*WL_OP - 2;           // 30
localparam FRAC_ACC  = WL_ACC - 5;            // 11
localparam RIGHT_SH  = FRAC_PROD - FRAC_ACC;  // 19

wire signed [WL_ACC-1:0] prod_real_aligned = mult_real >>> RIGHT_SH;
wire signed [WL_ACC-1:0] prod_imag_aligned = mult_imag >>> RIGHT_SH;
*/
// ---------------------------------------------------------------------------
// STAGE 2: Align Q2.30 -> Q5.11 using CONVERGENT ROUNDING
// ---------------------------------------------------------------------------
localparam FRAC_PROD = 2*WL_OP - 2;           // 30
localparam FRAC_ACC  = WL_ACC - 5;            // 11
localparam RIGHT_SH  = FRAC_PROD - FRAC_ACC;  // 19

// Arithmetic shift result
wire signed [WL_ACC-1:0] trunc_real = mult_real >>> RIGHT_SH;
wire signed [WL_ACC-1:0] trunc_imag = mult_imag >>> RIGHT_SH;

// First dropped bit
wire guard_real = mult_real[RIGHT_SH-1];
wire guard_imag = mult_imag[RIGHT_SH-1];

// Remaining dropped bits
wire sticky_real = |mult_real[RIGHT_SH-2:0];
wire sticky_imag = |mult_imag[RIGHT_SH-2:0];

// LSB of retained result
wire lsb_real = trunc_real[0];
wire lsb_imag = trunc_imag[0];

// Convergent rounding (round-half-to-even)
wire round_real = guard_real & (sticky_real | lsb_real);
wire round_imag = guard_imag & (sticky_imag | lsb_imag);

wire signed [WL_ACC-1:0] prod_real_aligned =
    trunc_real + round_real;

wire signed [WL_ACC-1:0] prod_imag_aligned =
    trunc_imag + round_imag;

// ---------------------------------------------------------------------------
// STAGE 3: Registered add + pass-through
//
// KEY RULE: e_out is updated ONLY when valid_in=1.
//   On valid_in=1: self-accumulate — add new product to e_out.
//   On valid_in=0: HOLD e_out.
//
// With valid_burst, valid_in fires K_DEPTH consecutive cycles per
// transaction.  Each PE must accumulate all K_DEPTH products into e_out.
// e_in is hardwired to 0 for the leftmost column (COLS=1 matched filter),
// so accumulation must be e_out += product, not e_in + product.
// e_out is cleared by rst_n between transactions.
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
            e_out_real <= e_out_real + prod_real_aligned;  // self-accumulate
            e_out_imag <= e_out_imag + prod_imag_aligned;
        end
        // else: HOLD — do not touch e_out_real / e_out_imag

        valid_out <= valid_in;
    end
    // else (en=0): hold all state — pipeline stall
end

endmodule