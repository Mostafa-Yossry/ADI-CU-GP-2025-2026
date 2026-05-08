// =============================================================================
// complex_mac_pe.sv
// -----------------------------------------------------------------------------
// MATCHED FILTER PE — Fixed-point format matches MATLAB golden exactly.
//
// MATLAB model: MULTIPLICATION_TYPES('fixed_point_Z_8x8', 12)
//   WL_OP  = 16  (Q1.15 after input widening)
//   WL_ACC = 12  (Q5.7 output)
//
// Fixed-point chain:
//   Input (boundary)  : Q1.11,  12-bit   (WL_IN  = 12)
//   After widening    : Q1.15,  16-bit   (WL_INT = 16)  [4 zero LSBs]
//   After multiply    : Q2.30,  32-bit   (full precision product)
//   Internal acc      : Q5.30,  35-bit   (sum of K=8 products, no rounding)
//   RIGHT_SH = FRAC_PROD - FRAC_ACC = 30 - 7 = 23
//   After rounding    : Q5.7,   12-bit   (WL_ACC = 12)  [single convergent round]
//   Output Z          : Q5.7,   12-bit   — matches MATLAB T.Q1_11 exactly
//
// Accumulation model — CRITICAL:
//   MATLAB accumulates K=8 full-precision Q2.30 products in a widening
//   accumulator (Q2_->Q3_->Q4_->Q5_) and rounds ONCE to Q5.7 at output.
//   Rounding each product before accumulation compounds rounding error
//   and causes ~94/800 failures by 1 LSB. This RTL matches MATLAB by:
//     1. Accumulating in a 35-bit Q5.30 register (no intermediate rounding)
//     2. Rounding to Q5.7 once, from acc_next (the post-update value)
//
// Pipeline timing (valid_in pulse k, k=0..K-1):
//   posedge clk:  acc_next = acc + product[k]
//                 acc      <= acc_next          (registered)
//                 e_out    <= round(acc_next)   (registered, uses acc_next)
//                 valid_out<= valid_in
//   => on the last valid_in=1 pulse (k=K-1), e_out captures round(acc_final).
//   Testbench overwrite-on-every-pulse captures this last value. Correct.
//
// Internal accumulator width:
//   WL_PROD    = 2*WL_OP     = 32  (signed Q2.30 product)
//   WL_INT_ACC = WL_PROD + 3 = 35  (Q5.30: +3 bits for up to 8 products)
// =============================================================================

module complex_mac_pe #(
    parameter WL_OP  = 16,   // operand word length  (Q1.15 after widening)
    parameter WL_ACC = 12    // output word length   (Q5.7)
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
// Fixed-point parameters
// FRAC_PROD  = 2*WL_OP - 2 = 30  (Q2.30 fractional bits)
// FRAC_ACC   = WL_ACC - 5  =  7  (Q5.7  fractional bits)
// RIGHT_SH   = 30 - 7      = 23  (bits discarded in final round)
// WL_PROD    = 2*WL_OP     = 32  (signed product width)
// WL_INT_ACC = WL_PROD + 3 = 35  (internal Q5.30 accumulator)
// ---------------------------------------------------------------------------
localparam FRAC_PROD  = 2*WL_OP - 2;
localparam FRAC_ACC   = WL_ACC - 5;
localparam RIGHT_SH   = FRAC_PROD - FRAC_ACC;  // 23
localparam WL_PROD    = 2*WL_OP;               // 32
localparam WL_INT_ACC = WL_PROD + 3;           // 35

// ---------------------------------------------------------------------------
// STAGE 1: Full-precision 16x16 complex multiply -> Q2.30 (32-bit signed)
// ---------------------------------------------------------------------------
wire signed [WL_PROD-1:0] prod_rr = a_real * b_real;
wire signed [WL_PROD-1:0] prod_ii = a_imag * b_imag;
wire signed [WL_PROD-1:0] prod_ri = a_real * b_imag;
wire signed [WL_PROD-1:0] prod_ir = a_imag * b_real;

wire signed [WL_PROD-1:0] mult_real = prod_rr - prod_ii;
wire signed [WL_PROD-1:0] mult_imag = prod_ri + prod_ir;

// ---------------------------------------------------------------------------
// STAGE 2: Wide internal accumulator state (Q5.30, 35-bit)
// ---------------------------------------------------------------------------
reg signed [WL_INT_ACC-1:0] acc_real;
reg signed [WL_INT_ACC-1:0] acc_imag;

// ---------------------------------------------------------------------------
// Combinational next-accumulator value.
// This is the value that will be stored in acc on the next posedge when
// valid_in=1. e_out is rounded from acc_next so that e_out and acc stay
// synchronised — e_out captures the fully-updated sum on every valid pulse.
// ---------------------------------------------------------------------------
wire signed [WL_INT_ACC-1:0] acc_next_real = acc_real + {{3{mult_real[WL_PROD-1]}}, mult_real};
wire signed [WL_INT_ACC-1:0] acc_next_imag = acc_imag + {{3{mult_imag[WL_PROD-1]}}, mult_imag};

// ---------------------------------------------------------------------------
// STAGE 3: Convergent rounding of acc_next -> Q5.7
//
// Operates on acc_next so that on each valid_in=1 posedge:
//   acc    <= acc_next               (updated sum)
//   e_out  <= round(acc_next)        (rounded view of updated sum)
// Both land in the same register cycle. On valid_in=0 acc holds, so
//   acc_next == acc and e_out holds as well.
//
// guard  = acc_next[RIGHT_SH-1]      first discarded bit
// sticky = |acc_next[RIGHT_SH-2:0]   OR of remaining discarded bits
// lsb    = trunc[0]                  LSB of retained result (tie-break)
// round  = guard & (sticky | lsb)
// ---------------------------------------------------------------------------
wire signed [WL_ACC-1:0] trunc_real_n = acc_next_real >>> RIGHT_SH;
wire signed [WL_ACC-1:0] trunc_imag_n = acc_next_imag >>> RIGHT_SH;

wire guard_real_n  = acc_next_real[RIGHT_SH-1];
wire guard_imag_n  = acc_next_imag[RIGHT_SH-1];

wire sticky_real_n = |acc_next_real[RIGHT_SH-2:0];
wire sticky_imag_n = |acc_next_imag[RIGHT_SH-2:0];

wire lsb_real_n    = trunc_real_n[0];
wire lsb_imag_n    = trunc_imag_n[0];

wire round_real_n  = guard_real_n  & (sticky_real_n  | lsb_real_n);
wire round_imag_n  = guard_imag_n  & (sticky_imag_n  | lsb_imag_n);

wire signed [WL_ACC-1:0] rounded_real_n = trunc_real_n + {{(WL_ACC-1){1'b0}}, round_real_n};
wire signed [WL_ACC-1:0] rounded_imag_n = trunc_imag_n + {{(WL_ACC-1){1'b0}}, round_imag_n};

// ---------------------------------------------------------------------------
// STAGE 4: Registered update
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        a_pass_real <= {WL_OP{1'b0}};
        a_pass_imag <= {WL_OP{1'b0}};
        b_pass_real <= {WL_OP{1'b0}};
        b_pass_imag <= {WL_OP{1'b0}};
        acc_real    <= {WL_INT_ACC{1'b0}};
        acc_imag    <= {WL_INT_ACC{1'b0}};
        e_out_real  <= {WL_ACC{1'b0}};
        e_out_imag  <= {WL_ACC{1'b0}};
        valid_out   <= 1'b0;
    end else if (en) begin
        a_pass_real <= a_real;
        a_pass_imag <= a_imag;
        b_pass_real <= b_real;
        b_pass_imag <= b_imag;

        if (valid_in) begin
            acc_real   <= acc_next_real;
            acc_imag   <= acc_next_imag;
            e_out_real <= rounded_real_n;
            e_out_imag <= rounded_imag_n;
        end
        // else: HOLD acc and e_out across idle cycles

        valid_out <= valid_in;
    end
end

endmodule