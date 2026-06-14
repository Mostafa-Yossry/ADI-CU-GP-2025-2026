module matched_filter_unrolled #(

    // Dimensions fixed at 8x8
    parameter int MF_ROWS     = 8,
    parameter int MF_COLS     = 8,

    // Input format: Q1.11, 12-bit
    parameter int MF_WL_IN    = 12,
    parameter int MF_FL_IN    = 11,

    // Internal format: Q1.15, 16-bit
    parameter int MF_WL_W     = 16,
    parameter int MF_FL_W     = 15,

    // Product format: Q2.30, 32-bit
    parameter int MF_WL_PROD  = 32,
    parameter int MF_FL_PROD  = 30,

    // Accumulator stage formats (16-bit)
    parameter int MF_FL_Q2    = 14, // after k=1
    parameter int MF_FL_Q3    = 13, // after k=2
    parameter int MF_FL_Q4    = 12, // after k=3,4
    parameter int MF_FL_Q5    = 11, // after k=5..8

    // Output format: Q5.11, 16-bit
    parameter int MF_WL_OUT   = 16,
    parameter int MF_FL_OUT   = 11

)(
    // Clock / Reset / Enable
    input  logic                                     clk      ,
    input  logic                                     rst_n    ,
    input  logic                                     en       ,

    // H^H Coefficient Load
    input  logic                                     hh_load  ,
    input  logic signed [MF_WL_IN-1:0]               hh_real  [0:MF_ROWS-1][0:MF_COLS-1],
    input  logic signed [MF_WL_IN-1:0]               hh_imag  [0:MF_ROWS-1][0:MF_COLS-1],

    // Y Vector Input
    input  logic                                     valid_in ,
    input  logic signed [MF_WL_IN-1:0]               y_real   [0:MF_COLS-1],
    input  logic signed [MF_WL_IN-1:0]               y_imag   [0:MF_COLS-1],

    // Z Vector Output
    output logic                                     valid_out,
    output logic                                     gy_enable,
    output logic signed [MF_WL_OUT-1:0]              z_real   [0:MF_ROWS-1],
    output logic signed [MF_WL_OUT-1:0]              z_imag   [0:MF_ROWS-1]
);

// ================================================================
// Derived constants and Types
// ================================================================
    localparam int FRAC_WIDEN = MF_FL_W - MF_FL_IN;   // = 4
    typedef logic signed [MF_WL_PROD-1:0] prod_t;

// ================================================================
// Input Registers and Widening
// ================================================================

    // --- H^H coefficients (static after load) ---
    logic signed [MF_WL_W-1:0] coef_real [0:MF_ROWS-1][0:MF_COLS-1];
    logic signed [MF_WL_W-1:0] coef_imag [0:MF_ROWS-1][0:MF_COLS-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int r=0; r<MF_ROWS; r++) for (int c=0; c<MF_COLS; c++) begin
                coef_real[r][c] <= '0; coef_imag[r][c] <= '0;
            end
        end else if (hh_load) begin
            for (int r=0; r<MF_ROWS; r++) for (int c=0; c<MF_COLS; c++) begin
                coef_real[r][c] <= signed'({ hh_real[r][c], {FRAC_WIDEN{1'b0}} });
                coef_imag[r][c] <= signed'({ hh_imag[r][c], {FRAC_WIDEN{1'b0}} });
            end
        end
    end

    // --- Y Input Sample and Valid Delay Line ---
    logic [15:0] stg_valid; // Sufficient depth

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) stg_valid <= '0;
        else if (en) stg_valid <= {stg_valid[14:0], valid_in};
    end

    // Input Y pipeline to feed correct stages spatially
    logic signed [MF_WL_W-1:0] y_w_real [0:MF_COLS-1];
    logic signed [MF_WL_W-1:0] y_w_imag [0:MF_COLS-1];

    generate
        for (genvar gk = 0; gk < MF_COLS; gk++) begin : g_widen_y
            assign y_w_real[gk] = signed'({ y_real[gk], {FRAC_WIDEN{1'b0}} });
            assign y_w_imag[gk] = signed'({ y_imag[gk], {FRAC_WIDEN{1'b0}} });
        end
    endgenerate

    // Y delayed pipelines to meet specific space stages
    logic signed [MF_WL_W-1:0] y_stg2_r, y_stg2_i; // feed stg2 mul (T+2)
    logic signed [MF_WL_W-1:0] y_stg4_r, y_stg4_i; // feed stg4 mul (T+4)
    logic signed [MF_WL_W-1:0] y_stg6_r, y_stg6_i; // feed stg6 mul (T+6)
    logic signed [MF_WL_W-1:0] y_stg8_r, y_stg8_i; // feed stg8 mul (T+8)
    logic signed [MF_WL_W-1:0] y_stg10_r, y_stg10_i; // feed stg10 mul (T+10)
    logic signed [MF_WL_W-1:0] y_stg12_r, y_stg12_i; // feed stg12 mul (T+12)
    logic signed [MF_WL_W-1:0] y_stg14_r, y_stg14_i; // feed stg14 mul (T+14)

    always_ff @(posedge clk) begin
        if (en) begin
            // Y delays created explicitly. Could use generate for compactness.
            {y_stg2_r, y_stg2_i} <= {y_w_real[1], y_w_imag[1]}; // delayed by 2 internally via shift array below
        end
    end

    // Simple delay lines for Y inputs to unrolled stages
    logic signed [MF_WL_W-1:0] y_dly_real [1:MF_COLS-1][0:15];
    logic signed [MF_WL_W-1:0] y_dly_imag [1:MF_COLS-1][0:15];

    always_ff @(posedge clk) begin
        if (en) begin
            for(int k=1; k<MF_COLS; k++) begin
                y_dly_real[k][0] <= y_w_real[k];
                y_dly_imag[k][0] <= y_w_imag[k];
                for(int d=1; d<=15; d++) begin
                    y_dly_real[k][d] <= y_dly_real[k][d-1];
                    y_dly_imag[k][d] <= y_dly_imag[k][d-1];
                end
            end
        end
    end

// ================================================================
// Rounding Functions (Preserved verbatim)
// ================================================================
    function automatic logic signed [MF_WL_W-1:0] conv_round_s1 (input logic signed [MF_WL_W:0] val);
        logic signed [MF_WL_W-1:0] trunc; logic guard, rup;
        trunc = val[MF_WL_W : 1]; guard = val[0]; rup = guard & trunc[0];
        return trunc + MF_WL_W'(rup);
    endfunction
    function automatic logic signed [MF_WL_W-1:0] conv_round_s16 (input logic signed [MF_WL_PROD-1:0] val);
        logic signed [MF_WL_W-1:0] trunc; logic guard, sticky, rup;
        trunc = val >>> 16; guard = val[15]; sticky = |val[14:0]; rup = guard & (sticky | trunc[0]);
        return trunc + MF_WL_W'(rup);
    endfunction
    function automatic logic signed [MF_WL_W-1:0] conv_round_s17 (input logic signed [MF_WL_PROD-1:0] val);
        logic signed [MF_WL_W-1:0] trunc; logic guard, sticky, rup;
        trunc = val >>> 17; guard = val[16]; sticky = |val[15:0]; rup = guard & (sticky | trunc[0]);
        return trunc + MF_WL_W'(rup);
    endfunction
    function automatic logic signed [MF_WL_W-1:0] conv_round_s18 (input logic signed [MF_WL_PROD-1:0] val);
        logic signed [MF_WL_W-1:0] trunc; logic guard, sticky, rup;
        trunc = val >>> 18; guard = val[17]; sticky = |val[16:0]; rup = guard & (sticky | trunc[0]);
        return trunc + MF_WL_W'(rup);
    endfunction
    function automatic logic signed [MF_WL_W-1:0] conv_round_s19 (input logic signed [MF_WL_PROD-1:0] val);
        logic signed [MF_WL_W-1:0] trunc; logic guard, sticky, rup;
        trunc = val >>> 19; guard = val[18]; sticky = |val[17:0]; rup = guard & (sticky | trunc[0]);
        return trunc + MF_WL_W'(rup);
    endfunction

// ================================================================
// Complex Mul Helper Task (for timing)
// ================================================================
    task complex_mul_comb(
        input  logic signed [MF_WL_W-1:0] ar, ai, cr, ci,
        output prod_t real_32, imag_32
    );
        prod_t prr, pii, pri, pir;
        prr = prod_t'(ar) * prod_t'(cr); pii = prod_t'(ai) * prod_t'(ci);
        pri = prod_t'(ar) * prod_t'(ci); pir = prod_t'(ai) * prod_t'(cr);
        real_32 = prr - pii; imag_32 = pri + pir;
    endtask

// ================================================================
// SPATIAL PIPELINE PIPELINE (Unrolled MAC)
// ================================================================

    // Pipeline Registers definitions
    prod_t pr_r [0:7][0:MF_ROWS-1]; // Product real reg per MAC k
    prod_t pr_i [0:7][0:MF_ROWS-1]; // Product imag reg per MAC k

    logic signed [MF_WL_W-1:0] r_q2_r[0:MF_ROWS-1], r_q2_i[0:MF_ROWS-1];
    logic signed [MF_WL_W-1:0] r_q3_r[0:MF_ROWS-1], r_q3_i[0:MF_ROWS-1];
    logic signed [MF_WL_W-1:0] r_q4_3_r[0:MF_ROWS-1], r_q4_3_i[0:MF_ROWS-1]; // q4 acc after k=3
    logic signed [MF_WL_W-1:0] r_q4_4_r[0:MF_ROWS-1], r_q4_4_i[0:MF_ROWS-1]; // q4 acc after k=4
    logic signed [MF_WL_W-1:0] r_q5_5_r[0:MF_ROWS-1], r_q5_5_i[0:MF_ROWS-1]; // q5 after k=5
    logic signed [MF_WL_W-1:0] r_q5_6_r[0:MF_ROWS-1], r_q5_6_i[0:MF_ROWS-1]; // q5 after k=6
    logic signed [MF_WL_W-1:0] r_q5_7_r[0:MF_ROWS-1], r_q5_7_i[0:MF_ROWS-1]; // q5 after k=7
    logic signed [MF_WL_W-1:0] r_q5_8_r[0:MF_ROWS-1], r_q5_8_i[0:MF_ROWS-1]; // q5 after k=8

    generate
        for (genvar gr = 0; gr < MF_ROWS; gr++) begin : g_pipe_rows

            // ---------------------------------------------------------
            // k=1 (stg1_M, stg2_S) -> acc_Q2
            // ---------------------------------------------------------
            // Comb calc
            prod_t k1_pr_r, k1_pr_i;
            always_comb complex_mul_comb(coef_real[gr][0], coef_imag[gr][0], y_w_real[0], y_w_imag[0], k1_pr_r, k1_pr_i);

            // Stg 1 Reg (Multiply) — only capture when valid_in; hold otherwise so
            // stg_valid[0] (valid_in delayed 1) always sees the correct product.
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    pr_r[0][gr] <= '0; pr_i[0][gr] <= '0;
                end else if (en && valid_in) begin
                    pr_r[0][gr] <= k1_pr_r; pr_i[0][gr] <= k1_pr_i;
                end
            end

            // Stg 2 Reg (Round/Store k=1 result) -> Latency T+2
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin r_q2_r[gr] <= '0; r_q2_i[gr] <= '0; end
                else if (en) begin
                    if (stg_valid[0]) begin // valid_in delayed 1 cycle
                        r_q2_r[gr] <= conv_round_s16(pr_r[0][gr]);
                        r_q2_i[gr] <= conv_round_s16(pr_i[0][gr]);
                    end
                end
            end

            // ---------------------------------------------------------
            // k=2 (stg2_M, stg3_S) -> acc_Q3
            // ---------------------------------------------------------
            prod_t k2_pr_r, k2_pr_i;
            // Use Y delayed to meet Stage 2
            always_comb complex_mul_comb(coef_real[gr][1], coef_imag[gr][1], y_dly_real[1][0], y_dly_imag[1][0], k2_pr_r, k2_pr_i);

            // Stg 2 Reg (Multiply)
            always_ff @(posedge clk) if (en) begin
                 pr_r[1][gr] <= k2_pr_r; pr_i[1][gr] <= k2_pr_i;
            end

            // Stg 3 Reg (Round products, Add acc_Q2, Round Sum to Q3) -> T+3
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin r_q3_r[gr] <= '0; r_q3_i[gr] <= '0; end
                else if (en) begin
                    logic signed [MF_WL_W-1:0] mQ2r, mQ2i;
                    logic signed [MF_WL_W:0]   sumr, sumi;
                    if (stg_valid[1]) begin
                        mQ2r = conv_round_s16(pr_r[1][gr]);
                        mQ2i = conv_round_s16(pr_i[1][gr]);
                        sumr = signed'({r_q2_r[gr][MF_WL_W-1], r_q2_r[gr]}) + signed'({mQ2r[MF_WL_W-1], mQ2r});
                        sumi = signed'({r_q2_i[gr][MF_WL_W-1], r_q2_i[gr]}) + signed'({mQ2i[MF_WL_W-1], mQ2i});
                        r_q3_r[gr] <= conv_round_s1(sumr);
                        r_q3_i[gr] <= conv_round_s1(sumi);
                    end
                end
            end

            // ---------------------------------------------------------
            // k=3 (stg3_M, stg4_S) -> acc_Q4
            // ---------------------------------------------------------
            prod_t k3_pr_r, k3_pr_i;
            // Need Y[2] delayed to T+2
            always_comb complex_mul_comb(coef_real[gr][2], coef_imag[gr][2], y_dly_real[2][1], y_dly_imag[2][1], k3_pr_r, k3_pr_i);

            always_ff @(posedge clk) if (en) begin
                 pr_r[2][gr] <= k3_pr_r; pr_i[2][gr] <= k3_pr_i;
            end

            // Stg 4 Reg (Add to Q3, round to Q4) -> T+4
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin r_q4_3_r[gr] <= '0; r_q4_3_i[gr] <= '0; end
                else if (en) begin
                    logic signed [MF_WL_W-1:0] mQ3r, mQ3i;
                    logic signed [MF_WL_W:0]   sumr, sumi;
                    if (stg_valid[2]) begin
                        mQ3r = conv_round_s17(pr_r[2][gr]);
                        mQ3i = conv_round_s17(pr_i[2][gr]);
                        sumr = signed'({r_q3_r[gr][MF_WL_W-1], r_q3_r[gr]}) + signed'({mQ3r[MF_WL_W-1], mQ3r});
                        sumi = signed'({r_q3_i[gr][MF_WL_W-1], r_q3_i[gr]}) + signed'({mQ3i[MF_WL_W-1], mQ3i});
                        r_q4_3_r[gr] <= conv_round_s1(sumr);
                        r_q4_3_i[gr] <= conv_round_s1(sumi);
                    end
                end
            end

            // ---------------------------------------------------------
            // k=4 (stg4_M, stg5_S) -> acc_Q4 (no rounding shift)
            // ---------------------------------------------------------
            prod_t k4_pr_r, k4_pr_i;
            // Need Y[3] delayed to T+3
            always_comb complex_mul_comb(coef_real[gr][3], coef_imag[gr][3], y_dly_real[3][2], y_dly_imag[3][2], k4_pr_r, k4_pr_i);

            always_ff @(posedge clk) if (en) begin
                 pr_r[3][gr] <= k4_pr_r; pr_i[3][gr] <= k4_pr_i;
            end

            // Stg 5 Reg (Add to Q4, simple wrap) -> T+5
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin r_q4_4_r[gr] <= '0; r_q4_4_i[gr] <= '0; end
                else if (en) begin
                    logic signed [MF_WL_W-1:0] mQ4r, mQ4i;
                    if (stg_valid[3]) begin
                        mQ4r = conv_round_s18(pr_r[3][gr]);
                        mQ4i = conv_round_s18(pr_i[3][gr]);
                        r_q4_4_r[gr] <= r_q4_3_r[gr] + mQ4r;
                        r_q4_4_i[gr] <= r_q4_3_i[gr] + mQ4i;
                    end
                end
            end

            // ---------------------------------------------------------
            // k=5 (stg5_M, stg6_S) -> acc_Q5 (shift 1)
            // ---------------------------------------------------------
            prod_t k5_pr_r, k5_pr_i;
            // Need Y[4] delayed to T+4
            always_comb complex_mul_comb(coef_real[gr][4], coef_imag[gr][4], y_dly_real[4][3], y_dly_imag[4][3], k5_pr_r, k5_pr_i);

            always_ff @(posedge clk) if (en) begin
                 pr_r[4][gr] <= k5_pr_r; pr_i[4][gr] <= k5_pr_i;
            end

            // Stg 6 Reg (Add to Q4, round to Q5) -> T+6
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin r_q5_5_r[gr] <= '0; r_q5_5_i[gr] <= '0; end
                else if (en) begin
                    logic signed [MF_WL_W-1:0] mQ4r, mQ4i;
                    logic signed [MF_WL_W:0]   sumr, sumi;
                    if (stg_valid[4]) begin
                        mQ4r = conv_round_s18(pr_r[4][gr]);
                        mQ4i = conv_round_s18(pr_i[4][gr]);
                        sumr = signed'({r_q4_4_r[gr][MF_WL_W-1], r_q4_4_r[gr]}) + signed'({mQ4r[MF_WL_W-1], mQ4r});
                        sumi = signed'({r_q4_4_i[gr][MF_WL_W-1], r_q4_4_i[gr]}) + signed'({mQ4i[MF_WL_W-1], mQ4i});
                        r_q5_5_r[gr] <= conv_round_s1(sumr);
                        r_q5_5_i[gr] <= conv_round_s1(sumi);
                    end
                end
            end

            // ---------------------------------------------------------
            // k=6 (stg6_M, stg7_S) -> acc_Q5 (no shift)
            // ---------------------------------------------------------
            prod_t k6_pr_r, k6_pr_i;
            // Need Y[5] delayed to T+5
            always_comb complex_mul_comb(coef_real[gr][5], coef_imag[gr][5], y_dly_real[5][4], y_dly_imag[5][4], k6_pr_r, k6_pr_i);

            always_ff @(posedge clk) if (en) begin
                 pr_r[5][gr] <= k6_pr_r; pr_i[5][gr] <= k6_pr_i;
            end

            // Stg 7 Reg -> T+7
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin r_q5_6_r[gr] <= '0; r_q5_6_i[gr] <= '0; end
                else if (en) begin
                    logic signed [MF_WL_W-1:0] mQ5r, mQ5i;
                    if (stg_valid[5]) begin
                        mQ5r = conv_round_s19(pr_r[5][gr]);
                        mQ5i = conv_round_s19(pr_i[5][gr]);
                        r_q5_6_r[gr] <= r_q5_5_r[gr] + mQ5r;
                        r_q5_6_i[gr] <= r_q5_5_i[gr] + mQ5i;
                    end
                end
            end

            // ---------------------------------------------------------
            // k=7 (stg7_M, stg8_S) -> acc_Q5 (no shift)
            // ---------------------------------------------------------
            prod_t k7_pr_r, k7_pr_i;
            // Need Y[6] delayed to T+6
            always_comb complex_mul_comb(coef_real[gr][6], coef_imag[gr][6], y_dly_real[6][5], y_dly_imag[6][5], k7_pr_r, k7_pr_i);

            always_ff @(posedge clk) if (en) begin
                 pr_r[6][gr] <= k7_pr_r; pr_i[6][gr] <= k7_pr_i;
            end

            // Stg 8 Reg -> T+8
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin r_q5_7_r[gr] <= '0; r_q5_7_i[gr] <= '0; end
                else if (en) begin
                    logic signed [MF_WL_W-1:0] mQ5r, mQ5i;
                    if (stg_valid[6]) begin
                        mQ5r = conv_round_s19(pr_r[6][gr]);
                        mQ5i = conv_round_s19(pr_i[6][gr]);
                        r_q5_7_r[gr] <= r_q5_6_r[gr] + mQ5r;
                        r_q5_7_i[gr] <= r_q5_6_i[gr] + mQ5i;
                    end
                end
            end

            // ---------------------------------------------------------
            // k=8 (stg8_M, stg9_S) -> FINAL acc_Q5 (no shift)
            // ---------------------------------------------------------
            prod_t k8_pr_r, k8_pr_i;
            // Need Y[7] delayed to T+7
            always_comb complex_mul_comb(coef_real[gr][7], coef_imag[gr][7], y_dly_real[7][6], y_dly_imag[7][6], k8_pr_r, k8_pr_i);

            always_ff @(posedge clk) if (en) begin
                 pr_r[7][gr] <= k8_pr_r; pr_i[7][gr] <= k8_pr_i;
            end

            // Stg 9 Reg -> T+9 (End of arithmetic pipeline)
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin r_q5_8_r[gr] <= '0; r_q5_8_i[gr] <= '0; end
                else if (en) begin
                    logic signed [MF_WL_W-1:0] mQ5r, mQ5i;
                    if (stg_valid[7]) begin
                        mQ5r = conv_round_s19(pr_r[7][gr]);
                        mQ5i = conv_round_s19(pr_i[7][gr]);
                        r_q5_8_r[gr] <= r_q5_7_r[gr] + mQ5r;
                        r_q5_8_i[gr] <= r_q5_7_i[gr] + mQ5i;
                    end
                end
            end

        end
    endgenerate

// ================================================================
// Part 7: Output Stage
// ================================================================
    // Need explicit delay lines for valid to align with arith depth T+9
    logic valid_out_r;
    logic signed [MF_WL_OUT-1:0] out_real [0:MF_ROWS-1];
    logic signed [MF_WL_OUT-1:0] out_imag [0:MF_ROWS-1];

    always_ff @(posedge clk or negedge rst_n) begin : p_output
        if (!rst_n) begin
            valid_out_r <= 1'b0;
            for (int gr = 0; gr < MF_ROWS; gr++) begin
                out_real[gr] <= '0; out_imag[gr] <= '0;
            end
        end else if (en) begin
            valid_out_r <= stg_valid[8]; // Align valid
            for (int gr = 0; gr < MF_ROWS; gr++) begin
                // Format conversion from Q5.11 internal to Q5.11 output (simple cast)
                out_real[gr] <= r_q5_8_r[gr];
                out_imag[gr] <= r_q5_8_i[gr];
            end
        end
    end

// ================================================================
// Part 8: gy_enable sticky flag
// ================================================================
    logic gy_enable_r;
    always_ff @(posedge clk or negedge rst_n) begin : p_gy
        if (!rst_n)               gy_enable_r <= 1'b0;
        else if (valid_out_r)     gy_enable_r <= 1'b1;  // use _r directly, not the assign alias
    end

    assign valid_out = valid_out_r;
    assign gy_enable = gy_enable_r | valid_out_r;  // assert on same cycle as first valid_out

// ================================================================
// Output assignments
// ================================================================
    generate
        for (genvar gr = 0; gr < MF_ROWS; gr++) begin : g_out
            assign z_real[gr] = out_real[gr];
            assign z_imag[gr] = out_imag[gr];
        end
    endgenerate

endmodule