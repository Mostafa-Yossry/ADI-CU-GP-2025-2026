// =============================================================================
// complex_mac_pe.sv
// -----------------------------------------------------------------------------
// MATCHED FILTER PE — Fixed-point format matches MATLAB golden exactly.
//
// MATLAB model: gen_rtl_vectors_Z_Q1_11.m
//   WL_OP  = 16  (Q1.15 after input widening)
//   WL_ACC = 16  (Q5.11 output)
//
// Fixed-point chain:
//   Input (boundary)  : Q1.11,  12-bit   (WL_IN  = 12)
//   After widening    : Q1.15,  16-bit   (WL_INT = 16)  [4 zero LSBs]
//   Product           : Q2.30,  32-bit   (full-precision 16x16 multiply)
//   After prod round  : Q5.11,  16-bit   (convergent round RIGHT_SH=19 each cycle)
//   Accumulator       : Q5.11,  16-bit   (acc += rounded_prod each valid cycle)
//   Output yhat       : Q5.11,  16-bit   — matches MATLAB FL_OUT=11 exactly
//
// Accumulation model — CRITICAL (must match MATLAB loop exactly):
//
//   MATLAB per k:
//     ac     = fi(a*c, Q2.30, 32-bit)              % full-precision product
//     bd     = fi(b*d, Q2.30, 32-bit)
//     prod_r = fi(ac-bd, Q5.11, 16-bit)            % convergent round EACH cycle
//     acc_r  = fi(acc_r + prod_r, Q5.11, 16-bit)   % accumulate in Q5.11
//
//   RTL per valid_in pulse:
//     1. Form full 32-bit Q2.30 complex product  (mult_real, mult_imag)
//     2. Convergent-round mult -> Q5.11 16-bit   (prod_rounded_*)
//     3. acc_next = acc + prod_rounded            (Q5.11 + Q5.11, keep Q5.11)
//     4. Register: acc <= acc_next,  e_out <= acc_next
//
//   The acc register is Q5.11 16-bit throughout — no wide internal accumulator.
//   Overflow behaviour: wrap (matches MATLAB fi OverflowAction='Wrap').
//
// Pipeline timing (valid_in pulse k, k=0..K-1):
//   posedge clk:  prod_rounded = round(mult)         (combinational)
//                 acc_next     = acc + prod_rounded   (combinational)
//                 acc          <= acc_next            (registered)
//                 e_out        <= acc_next            (registered)
//                 valid_out    <= valid_in
//   => on the last valid_in=1 pulse (k=K-1), e_out holds the final result.
//
// Parameters:
//   WL_OP  = 16  operand width  (Q1.15 widened inputs)
//   WL_ACC = 16  accumulator / output width (Q5.11)
// =============================================================================

module complex_mac_pe #(
    parameter WL_OP  = 16,   // operand word length  (Q1.15 after widening)
    parameter WL_ACC = 16    // accumulator/output word length (Q5.11)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,

    input  wire signed [WL_OP-1:0]  a_real,
    input  wire signed [WL_OP-1:0]  a_imag,
    input  wire signed [WL_OP-1:0]  b_real,
    input  wire signed [WL_OP-1:0]  b_imag,

    input  wire signed [WL_ACC-1:0] e_in_real,   // unused; kept for port compatibility
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
//
// FRAC_PROD = 2*WL_OP - 2 = 30   Q2.30 product fractional bits
// FRAC_ACC  = WL_ACC - 5  = 11   Q5.11 accumulator fractional bits
// RIGHT_SH  = 30 - 11     = 19   bits discarded rounding product -> acc
// WL_PROD   = 2*WL_OP     = 32   full-precision product width
// ---------------------------------------------------------------------------
localparam FRAC_PROD = 2*WL_OP - 2;          // 30
localparam FRAC_ACC  = WL_ACC - 5;           // 11
localparam RIGHT_SH  = FRAC_PROD - FRAC_ACC; // 19
localparam WL_PROD   = 2*WL_OP;              // 32

// ---------------------------------------------------------------------------
// STAGE 1 : Full-precision 16x16 complex multiply -> Q2.30 (32-bit signed)
//
//   real part : a_real*b_real - a_imag*b_imag
//   imag part : a_real*b_imag + a_imag*b_real
// ---------------------------------------------------------------------------
wire signed [WL_PROD-1:0] prod_rr = a_real * b_real;
wire signed [WL_PROD-1:0] prod_ii = a_imag * b_imag;
wire signed [WL_PROD-1:0] prod_ri = a_real * b_imag;
wire signed [WL_PROD-1:0] prod_ir = a_imag * b_real;

wire signed [WL_PROD-1:0] mult_real = prod_rr - prod_ii;  // Q2.30
wire signed [WL_PROD-1:0] mult_imag = prod_ri + prod_ir;  // Q2.30

// ---------------------------------------------------------------------------
// STAGE 2 : Convergent round Q2.30 -> Q5.11 per cycle  (RIGHT_SH = 19)
//
// Matches MATLAB per-k operation:
//   prod_r = fi(double(ac) - double(bd), 1, WL_OUT, FL_OUT, FM)
//
// guard  = mult[RIGHT_SH-1]       first discarded bit
// sticky = |mult[RIGHT_SH-2:0]    OR of all remaining discarded bits
// lsb    = trunc[0]               LSB of the kept result
// inc    = guard & (sticky | lsb) convergent rounding increment
// ---------------------------------------------------------------------------
wire signed [WL_ACC-1:0] trunc_real = mult_real >>> RIGHT_SH;
wire signed [WL_ACC-1:0] trunc_imag = mult_imag >>> RIGHT_SH;

wire guard_real  = mult_real[RIGHT_SH-1];
wire guard_imag  = mult_imag[RIGHT_SH-1];

wire sticky_real = |mult_real[RIGHT_SH-2:0];
wire sticky_imag = |mult_imag[RIGHT_SH-2:0];

wire lsb_real    = trunc_real[0];
wire lsb_imag    = trunc_imag[0];

wire inc_real    = guard_real & (sticky_real | lsb_real);
wire inc_imag    = guard_imag & (sticky_imag | lsb_imag);

// Rounded product in Q5.11 16-bit. Wrap-on-overflow matches MATLAB fi Wrap.
wire signed [WL_ACC-1:0] prod_rounded_real = trunc_real + {{(WL_ACC-1){1'b0}}, inc_real};
wire signed [WL_ACC-1:0] prod_rounded_imag = trunc_imag + {{(WL_ACC-1){1'b0}}, inc_imag};

// ---------------------------------------------------------------------------
// STAGE 3 : Q5.11 accumulator  (16-bit, wrap on overflow)
//
// Matches MATLAB per-k operation:
//   acc_r = fi(double(acc_r) + double(prod_r), 1, WL_OUT, FL_OUT, FM)
// ---------------------------------------------------------------------------
reg signed [WL_ACC-1:0] acc_real;
reg signed [WL_ACC-1:0] acc_imag;

wire signed [WL_ACC-1:0] acc_next_real = acc_real + prod_rounded_real;
wire signed [WL_ACC-1:0] acc_next_imag = acc_imag + prod_rounded_imag;

// ---------------------------------------------------------------------------
// STAGE 4 : Registered update
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        a_pass_real <= {WL_OP{1'b0}};
        a_pass_imag <= {WL_OP{1'b0}};
        b_pass_real <= {WL_OP{1'b0}};
        b_pass_imag <= {WL_OP{1'b0}};
        acc_real    <= {WL_ACC{1'b0}};
        acc_imag    <= {WL_ACC{1'b0}};
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
            e_out_real <= acc_next_real;
            e_out_imag <= acc_next_imag;
        end
        // else: HOLD acc and e_out across idle cycles

        valid_out <= valid_in;
    end
end

endmodule