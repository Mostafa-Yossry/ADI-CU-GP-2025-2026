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

// --- Compile-time proof that this fixed source is being elaborated ----------
// Remove or comment this out after confirming 40/40.
initial $display("[complex_mac_pe] FIXED version elaborated (hold on valid_in=0)");

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
// STAGE 2: Align Q2.30 -> Q5.11 (right-shift by 19)
// ---------------------------------------------------------------------------
localparam FRAC_PROD = 2*WL_OP - 2;           // 30
localparam FRAC_ACC  = WL_ACC - 5;            // 11
localparam RIGHT_SH  = FRAC_PROD - FRAC_ACC;  // 19

wire signed [WL_ACC-1:0] prod_real_aligned = mult_real >>> RIGHT_SH;
wire signed [WL_ACC-1:0] prod_imag_aligned = mult_imag >>> RIGHT_SH;

// ---------------------------------------------------------------------------
// STAGE 3: Registered add + pass-through
//
// KEY RULE: e_out is updated ONLY when valid_in=1.
//   On valid_in=1: accumulate (e_in + product) into e_out.
//   On valid_in=0: HOLD e_out — do NOT overwrite with e_in.
//
// Why hold matters: valid_in fires exactly once per PE per transaction.
// After it fires, e_in from the left neighbour returns to 0 (the leftmost
// PE's e_in is hardwired zero). If we passed e_in through on valid_in=0,
// we would clobber the correct accumulated result before the right
// neighbour's valid fires to read it.
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
            e_out_real <= e_in_real + prod_real_aligned;
            e_out_imag <= e_in_imag + prod_imag_aligned;
        end
        // else: HOLD — do not touch e_out_real / e_out_imag

        valid_out <= valid_in;
    end
    // else (en=0): hold all state — pipeline stall
end

endmodule