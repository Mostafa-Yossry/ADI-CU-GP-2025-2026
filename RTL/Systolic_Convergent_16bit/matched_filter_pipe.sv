// =============================================================================
// matched_filter_pipe.sv
// -----------------------------------------------------------------------------
// Fully-pipelined matched filter  ŷ = H^H · y   (8×8 MIMO, 1 output/cycle)
//
// Architecture: parallel multipliers + log₂K pipelined adder tree
//
// Fixed-point chain (identical to systolic_matmul):
//   Input boundary   : Q1.11  12-bit  (WL_IN  = 12)
//   After widening   : Q1.15  16-bit  (WL_INT = 16)  [4 zero LSBs]
//   Product          : Q2.30  32-bit  (full-precision 16×16 multiply)
//   After round      : Q5.11  16-bit  (convergent round, RIGHT_SH = 19)
//   Adder tree nodes : Q5.11  16-bit  (wrap on overflow, matches MATLAB fi)
//   Output           : Q5.11  16-bit
//
// Pipeline stages (4 cycles latency, 1 cycle throughput):
//   Stage 1 (reg): K=8 parallel complex multiplies per row  →  Q2.30
//   Stage 2 (reg): convergent round Q2.30 → Q5.11  +  level-1 adder (4 sums)
//   Stage 3 (reg): level-2 adder (2 sums)
//   Stage 4 (reg): level-3 adder (1 sum = result)
//
// H^H storage:
//   Full 8×8 complex matrix held in registers.
//   Loaded combinationally via hh_load strobe + hh_real/imag ports.
//   Stable across frames (update once per channel coherence interval).
//
// Parameters:
//   ROWS    = 8   rows of H^H (output elements)
//   K       = 8   dot-product length (columns of H^H)
//   WL_IN   = 12  I/O boundary width (Q1.11)
//   WL_INT  = 16  internal width after widening (Q1.15)
//   WL_OUT  = 16  output width (Q5.11)
// =============================================================================

module matched_filter_pipe #(
    parameter ROWS   = 8,
    parameter K      = 8,
    parameter WL_IN  = 12,
    parameter WL_INT = 16,
    parameter WL_OUT = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire en,

    // -------------------------------------------------------------------
    // H^H coefficient load interface
    // Assert hh_load for one cycle to latch all coefficients.
    // hh_real/imag must be stable on that posedge.
    // -------------------------------------------------------------------
    input  wire                       hh_load,
    input  wire signed [WL_IN-1:0]   hh_real [0:ROWS-1][0:K-1],
    input  wire signed [WL_IN-1:0]   hh_imag [0:ROWS-1][0:K-1],

    // -------------------------------------------------------------------
    // Streaming y input — one new vector per cycle
    // -------------------------------------------------------------------
    input  wire                       valid_in,
    input  wire signed [WL_IN-1:0]   y_real  [0:K-1],
    input  wire signed [WL_IN-1:0]   y_imag  [0:K-1],

    // -------------------------------------------------------------------
    // Output — valid 4 cycles after valid_in
    // -------------------------------------------------------------------
    output reg                        valid_out,
    output reg  signed [WL_OUT-1:0]  yhat_real [0:ROWS-1],
    output reg  signed [WL_OUT-1:0]  yhat_imag [0:ROWS-1]
);

// ---------------------------------------------------------------------------
// Fixed-point derived parameters
// RIGHT_SH = FRAC_PROD - FRAC_OUT = 30 - 11 = 19
// ---------------------------------------------------------------------------
localparam WL_PROD  = 2 * WL_INT;       // 32  Q2.30
localparam RIGHT_SH = (WL_INT-1)*2 - (WL_OUT - 5);  // 30 - 11 = 19
localparam LEVELS   = 3;                // log2(K=8)

// ---------------------------------------------------------------------------
// H^H coefficient registers (Q1.15 after widening, held until next hh_load)
// ---------------------------------------------------------------------------
reg signed [WL_INT-1:0] coef_real [0:ROWS-1][0:K-1];
reg signed [WL_INT-1:0] coef_imag [0:ROWS-1][0:K-1];

genvar gr, gk;
generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : coef_row
        for (gk = 0; gk < K; gk = gk + 1) begin : coef_col
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    coef_real[gr][gk] <= {WL_INT{1'b0}};
                    coef_imag[gr][gk] <= {WL_INT{1'b0}};
                end else if (hh_load) begin
                    // Widen Q1.11 → Q1.15 by appending 4 zero LSBs
                    coef_real[gr][gk] <= {hh_real[gr][gk], 4'b0};
                    coef_imag[gr][gk] <= {hh_imag[gr][gk], 4'b0};
                end
            end
        end
    end
endgenerate

// ---------------------------------------------------------------------------
// Y input widening (Q1.11 → Q1.15, combinational)
// ---------------------------------------------------------------------------
wire signed [WL_INT-1:0] y_real_w [0:K-1];
wire signed [WL_INT-1:0] y_imag_w [0:K-1];

generate
    for (gk = 0; gk < K; gk = gk + 1) begin : widen_y
        assign y_real_w[gk] = {y_real[gk], 4'b0};
        assign y_imag_w[gk] = {y_imag[gk], 4'b0};
    end
endgenerate

// ---------------------------------------------------------------------------
// STAGE 1 : K parallel complex multiplies per row  →  Q2.30 (32-bit)
// Registered at end of stage.
// ---------------------------------------------------------------------------
reg signed [WL_PROD-1:0] s1_mult_real [0:ROWS-1][0:K-1];
reg signed [WL_PROD-1:0] s1_mult_imag [0:ROWS-1][0:K-1];
reg                       s1_valid;

generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : s1_row
        for (gk = 0; gk < K; gk = gk + 1) begin : s1_col
            wire signed [WL_PROD-1:0] p_rr = coef_real[gr][gk] * y_real_w[gk];
            wire signed [WL_PROD-1:0] p_ii = coef_imag[gr][gk] * y_imag_w[gk];
            wire signed [WL_PROD-1:0] p_ri = coef_real[gr][gk] * y_imag_w[gk];
            wire signed [WL_PROD-1:0] p_ir = coef_imag[gr][gk] * y_real_w[gk];

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s1_mult_real[gr][gk] <= {WL_PROD{1'b0}};
                    s1_mult_imag[gr][gk] <= {WL_PROD{1'b0}};
                end else if (en) begin
                    s1_mult_real[gr][gk] <= p_rr - p_ii;
                    s1_mult_imag[gr][gk] <= p_ri + p_ir;
                end
            end
        end
    end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s1_valid <= 1'b0;
    else if (en) s1_valid <= valid_in;
end

// ---------------------------------------------------------------------------
// STAGE 2 : Convergent round Q2.30 → Q5.11  +  level-1 adder (pairs → 4)
//
// Round each of the K=8 products, then add pairs:
//   node[k/2] = rounded[k] + rounded[k+1]   for k = 0,2,4,6
//
// rounded is Q5.11 16-bit; pair sum fits in Q6.11 17-bit but we keep Q5.11
// (wrap matches MATLAB fi Wrap behaviour).
// Registered at end of stage.
// ---------------------------------------------------------------------------
localparam NODES_L1 = K / 2;  // 4

reg signed [WL_OUT-1:0] s2_sum_real [0:ROWS-1][0:NODES_L1-1];
reg signed [WL_OUT-1:0] s2_sum_imag [0:ROWS-1][0:NODES_L1-1];
reg                      s2_valid;

generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : s2_row
        for (gk = 0; gk < NODES_L1; gk = gk + 1) begin : s2_node

            // Round product 2*gk
            wire signed [WL_OUT-1:0] tr_a_r = s1_mult_real[gr][2*gk] >>> RIGHT_SH;
            wire signed [WL_OUT-1:0] tr_a_i = s1_mult_imag[gr][2*gk] >>> RIGHT_SH;
            wire g_a_r  = s1_mult_real[gr][2*gk][RIGHT_SH-1];
            wire g_a_i  = s1_mult_imag[gr][2*gk][RIGHT_SH-1];
            wire st_a_r = |s1_mult_real[gr][2*gk][RIGHT_SH-2:0];
            wire st_a_i = |s1_mult_imag[gr][2*gk][RIGHT_SH-2:0];
            wire signed [WL_OUT-1:0] rnd_a_r = tr_a_r + {{(WL_OUT-1){1'b0}}, (g_a_r & (st_a_r | tr_a_r[0]))};
            wire signed [WL_OUT-1:0] rnd_a_i = tr_a_i + {{(WL_OUT-1){1'b0}}, (g_a_i & (st_a_i | tr_a_i[0]))};

            // Round product 2*gk+1
            wire signed [WL_OUT-1:0] tr_b_r = s1_mult_real[gr][2*gk+1] >>> RIGHT_SH;
            wire signed [WL_OUT-1:0] tr_b_i = s1_mult_imag[gr][2*gk+1] >>> RIGHT_SH;
            wire g_b_r  = s1_mult_real[gr][2*gk+1][RIGHT_SH-1];
            wire g_b_i  = s1_mult_imag[gr][2*gk+1][RIGHT_SH-1];
            wire st_b_r = |s1_mult_real[gr][2*gk+1][RIGHT_SH-2:0];
            wire st_b_i = |s1_mult_imag[gr][2*gk+1][RIGHT_SH-2:0];
            wire signed [WL_OUT-1:0] rnd_b_r = tr_b_r + {{(WL_OUT-1){1'b0}}, (g_b_r & (st_b_r | tr_b_r[0]))};
            wire signed [WL_OUT-1:0] rnd_b_i = tr_b_i + {{(WL_OUT-1){1'b0}}, (g_b_i & (st_b_i | tr_b_i[0]))};

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s2_sum_real[gr][gk] <= {WL_OUT{1'b0}};
                    s2_sum_imag[gr][gk] <= {WL_OUT{1'b0}};
                end else if (en) begin
                    s2_sum_real[gr][gk] <= rnd_a_r + rnd_b_r;
                    s2_sum_imag[gr][gk] <= rnd_a_i + rnd_b_i;
                end
            end
        end
    end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s2_valid <= 1'b0;
    else if (en) s2_valid <= s1_valid;
end

// ---------------------------------------------------------------------------
// STAGE 3 : Level-2 adder  (4 → 2 sums per row)
// ---------------------------------------------------------------------------
localparam NODES_L2 = NODES_L1 / 2;  // 2

reg signed [WL_OUT-1:0] s3_sum_real [0:ROWS-1][0:NODES_L2-1];
reg signed [WL_OUT-1:0] s3_sum_imag [0:ROWS-1][0:NODES_L2-1];
reg                      s3_valid;

generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : s3_row
        for (gk = 0; gk < NODES_L2; gk = gk + 1) begin : s3_node
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s3_sum_real[gr][gk] <= {WL_OUT{1'b0}};
                    s3_sum_imag[gr][gk] <= {WL_OUT{1'b0}};
                end else if (en) begin
                    s3_sum_real[gr][gk] <= s2_sum_real[gr][2*gk] + s2_sum_real[gr][2*gk+1];
                    s3_sum_imag[gr][gk] <= s2_sum_imag[gr][2*gk] + s2_sum_imag[gr][2*gk+1];
                end
            end
        end
    end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s3_valid <= 1'b0;
    else if (en) s3_valid <= s2_valid;
end

// ---------------------------------------------------------------------------
// STAGE 4 : Level-3 adder  (2 → 1 sum = final result per row)
// Output registered directly into yhat_real/imag.
// ---------------------------------------------------------------------------
generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : s4_row
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                yhat_real[gr] <= {WL_OUT{1'b0}};
                yhat_imag[gr] <= {WL_OUT{1'b0}};
            end else if (en) begin
                yhat_real[gr] <= s3_sum_real[gr][0] + s3_sum_real[gr][1];
                yhat_imag[gr] <= s3_sum_imag[gr][0] + s3_sum_imag[gr][1];
            end
        end
    end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) valid_out <= 1'b0;
    else if (en) valid_out <= s3_valid;
end

endmodule