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

    // Accumulator stage formats (16-bit) — kept for documentation
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
    output logic signed [MF_WL_OUT-1:0]              z_real   [0:MF_ROWS-1],
    output logic signed [MF_WL_OUT-1:0]              z_imag   [0:MF_ROWS-1]
);

// ================================================================
// Derived constants
// ================================================================
    localparam int FRAC_WIDEN = MF_FL_W - MF_FL_IN;   // = 4
    typedef logic signed [MF_WL_PROD-1:0] prod_t;

// ================================================================
// Rounding functions  (identical to original — bit-exact with MATLAB)
// ================================================================

    // Shift-by-1: 17-bit signed sum → 16-bit  (ties-to-odd)
    function automatic logic signed [MF_WL_W-1:0] conv_round_s1 (
        input logic signed [MF_WL_W:0] val
    );
        logic signed [MF_WL_W-1:0] trunc;
        logic guard, rup;
        trunc = val[MF_WL_W : 1];
        guard = val[0];
        rup   = guard & trunc[0];
        return trunc + MF_WL_W'(rup);
    endfunction

    // 32-bit product → 16-bit Q2.14  (shift 16, ties-to-odd)
    function automatic logic signed [MF_WL_W-1:0] conv_round_s16 (
        input logic signed [MF_WL_PROD-1:0] val
    );
        logic signed [MF_WL_W-1:0] trunc;
        logic guard, sticky, rup;
        trunc  = val >>> 16;
        guard  = val[15];
        sticky = |val[14:0];
        rup    = guard & (sticky | trunc[0]);
        return trunc + MF_WL_W'(rup);
    endfunction

    // 32-bit product → 16-bit Q2.13  (shift 17, ties-to-odd)
    function automatic logic signed [MF_WL_W-1:0] conv_round_s17 (
        input logic signed [MF_WL_PROD-1:0] val
    );
        logic signed [MF_WL_W-1:0] trunc;
        logic guard, sticky, rup;
        trunc  = val >>> 17;
        guard  = val[16];
        sticky = |val[15:0];
        rup    = guard & (sticky | trunc[0]);
        return trunc + MF_WL_W'(rup);
    endfunction

    // 32-bit product → 16-bit Q2.12  (shift 18, ties-to-odd)
    function automatic logic signed [MF_WL_W-1:0] conv_round_s18 (
        input logic signed [MF_WL_PROD-1:0] val
    );
        logic signed [MF_WL_W-1:0] trunc;
        logic guard, sticky, rup;
        trunc  = val >>> 18;
        guard  = val[17];
        sticky = |val[16:0];
        rup    = guard & (sticky | trunc[0]);
        return trunc + MF_WL_W'(rup);
    endfunction

    // 32-bit product → 16-bit Q5.11  (shift 19, ties-to-odd)
    function automatic logic signed [MF_WL_W-1:0] conv_round_s19 (
        input logic signed [MF_WL_PROD-1:0] val
    );
        logic signed [MF_WL_W-1:0] trunc;
        logic guard, sticky, rup;
        trunc  = val >>> 19;
        guard  = val[18];
        sticky = |val[17:0];
        rup    = guard & (sticky | trunc[0]);
        return trunc + MF_WL_W'(rup);
    endfunction

// ================================================================
// H^H Coefficient registers  (static after hh_load)
// ================================================================
    logic signed [MF_WL_W-1:0] coef_real [0:MF_ROWS-1][0:MF_COLS-1];
    logic signed [MF_WL_W-1:0] coef_imag [0:MF_ROWS-1][0:MF_COLS-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int r = 0; r < MF_ROWS; r++)
                for (int c = 0; c < MF_COLS; c++) begin
                    coef_real[r][c] <= '0;
                    coef_imag[r][c] <= '0;
                end
        end else if (hh_load) begin
            for (int r = 0; r < MF_ROWS; r++)
                for (int c = 0; c < MF_COLS; c++) begin
                    coef_real[r][c] <= signed'({ hh_real[r][c], {FRAC_WIDEN{1'b0}} });
                    coef_imag[r][c] <= signed'({ hh_imag[r][c], {FRAC_WIDEN{1'b0}} });
                end
        end
    end

// ================================================================
// Input register  — captures y[k] and valid_in on the clock edge
// ================================================================
    logic signed [MF_WL_W-1:0] yw_r [0:MF_COLS-1];   // widened, registered
    logic signed [MF_WL_W-1:0] yw_i [0:MF_COLS-1];
    logic                       valid_in_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_in_r <= 1'b0;
            for (int k = 0; k < MF_COLS; k++) begin
                yw_r[k] <= '0;
                yw_i[k] <= '0;
            end
        end else if (en) begin
            valid_in_r <= valid_in;
            for (int k = 0; k < MF_COLS; k++) begin
                // Q1.11 → Q1.15 : append FRAC_WIDEN=4 zero LSBs
                yw_r[k] <= signed'({ y_real[k], {FRAC_WIDEN{1'b0}} });
                yw_i[k] <= signed'({ y_imag[k], {FRAC_WIDEN{1'b0}} });
            end
        end
    end

// ================================================================
// Pure combinational datapath  (all signals are wires)
//
// The rounding schedule is preserved exactly:
//   k=1       : product → round_s16 → Q2.14  (acc_q2)
//   k=2       : product → round_s16 + acc_q2 → round_s1 → Q2.13 (acc_q3)
//   k=3       : product → round_s17 + acc_q3 → round_s1 → Q2.12 (acc_q4_3)
//   k=4       : product → round_s18 + acc_q4_3           → Q2.12 (acc_q4_4)
//   k=5       : product → round_s18 + acc_q4_4 → round_s1→ Q5.11 (acc_q5_5)
//   k=6..8    : product → round_s19 + acc                → Q5.11
// ================================================================
    generate
        for (genvar gr = 0; gr < MF_ROWS; gr++) begin : g_comb_rows

            // ---- intermediate wire declarations ----
            prod_t                     p1r, p1i;   // k=1 raw product  Q2.30
            prod_t                     p2r, p2i;   // k=2 raw product  Q2.30
            prod_t                     p3r, p3i;   // k=3 raw product  Q2.30
            prod_t                     p4r, p4i;   // k=4 raw product  Q2.30
            prod_t                     p5r, p5i;   // k=5 raw product  Q2.30
            prod_t                     p6r, p6i;   // k=6 raw product  Q2.30
            prod_t                     p7r, p7i;   // k=7 raw product  Q2.30
            prod_t                     p8r, p8i;   // k=8 raw product  Q2.30

            logic signed [MF_WL_W-1:0] acc_q2_r,  acc_q2_i;   // after k=1  Q2.14
            logic signed [MF_WL_W-1:0] acc_q3_r,  acc_q3_i;   // after k=2  Q2.13
            logic signed [MF_WL_W-1:0] acc_q4_3r, acc_q4_3i;  // after k=3  Q2.12
            logic signed [MF_WL_W-1:0] acc_q4_4r, acc_q4_4i;  // after k=4  Q2.12
            logic signed [MF_WL_W-1:0] acc_q5_5r, acc_q5_5i;  // after k=5  Q5.11
            logic signed [MF_WL_W-1:0] acc_q5_6r, acc_q5_6i;  // after k=6  Q5.11
            logic signed [MF_WL_W-1:0] acc_q5_7r, acc_q5_7i;  // after k=7  Q5.11
            logic signed [MF_WL_W-1:0] acc_q5_8r, acc_q5_8i;  // after k=8  Q5.11  FINAL

            always_comb begin : comb_mac

                // ----------------------------------------------------------
                // k=1 : H[r][0] * y[0]   →  round_s16  →  acc_q2  (Q2.14)
                // ----------------------------------------------------------
                begin
                    prod_t prr, pii, pri, pir;
                    prr = prod_t'(coef_real[gr][0]) * prod_t'(yw_r[0]);
                    pii = prod_t'(coef_imag[gr][0]) * prod_t'(yw_i[0]);
                    pri = prod_t'(coef_real[gr][0]) * prod_t'(yw_i[0]);
                    pir = prod_t'(coef_imag[gr][0]) * prod_t'(yw_r[0]);
                    p1r = prr - pii;
                    p1i = pri + pir;
                end
                acc_q2_r = conv_round_s16(p1r);   // Q2.14
                acc_q2_i = conv_round_s16(p1i);

                // ----------------------------------------------------------
                // k=2 : H[r][1] * y[1]   →  round_s16 + acc_q2 → round_s1
                //                                                 → acc_q3 (Q2.13)
                // ----------------------------------------------------------
                begin
                    prod_t prr, pii, pri, pir;
                    prr = prod_t'(coef_real[gr][1]) * prod_t'(yw_r[1]);
                    pii = prod_t'(coef_imag[gr][1]) * prod_t'(yw_i[1]);
                    pri = prod_t'(coef_real[gr][1]) * prod_t'(yw_i[1]);
                    pir = prod_t'(coef_imag[gr][1]) * prod_t'(yw_r[1]);
                    p2r = prr - pii;
                    p2i = pri + pir;
                end
                begin
                    logic signed [MF_WL_W-1:0] m2r, m2i;
                    logic signed [MF_WL_W:0]   sr,  si;
                    m2r = conv_round_s16(p2r);   // Q2.14
                    m2i = conv_round_s16(p2i);
                    sr  = signed'({acc_q2_r[MF_WL_W-1], acc_q2_r}) +
                          signed'({m2r[MF_WL_W-1],      m2r     });
                    si  = signed'({acc_q2_i[MF_WL_W-1], acc_q2_i}) +
                          signed'({m2i[MF_WL_W-1],      m2i     });
                    acc_q3_r = conv_round_s1(sr);   // Q2.13
                    acc_q3_i = conv_round_s1(si);
                end

                // ----------------------------------------------------------
                // k=3 : H[r][2] * y[2]   →  round_s17 + acc_q3 → round_s1
                //                                                 → acc_q4_3 (Q2.12)
                // ----------------------------------------------------------
                begin
                    prod_t prr, pii, pri, pir;
                    prr = prod_t'(coef_real[gr][2]) * prod_t'(yw_r[2]);
                    pii = prod_t'(coef_imag[gr][2]) * prod_t'(yw_i[2]);
                    pri = prod_t'(coef_real[gr][2]) * prod_t'(yw_i[2]);
                    pir = prod_t'(coef_imag[gr][2]) * prod_t'(yw_r[2]);
                    p3r = prr - pii;
                    p3i = pri + pir;
                end
                begin
                    logic signed [MF_WL_W-1:0] m3r, m3i;
                    logic signed [MF_WL_W:0]   sr,  si;
                    m3r = conv_round_s17(p3r);   // Q2.13
                    m3i = conv_round_s17(p3i);
                    sr  = signed'({acc_q3_r[MF_WL_W-1], acc_q3_r}) +
                          signed'({m3r[MF_WL_W-1],      m3r     });
                    si  = signed'({acc_q3_i[MF_WL_W-1], acc_q3_i}) +
                          signed'({m3i[MF_WL_W-1],      m3i     });
                    acc_q4_3r = conv_round_s1(sr);   // Q2.12
                    acc_q4_3i = conv_round_s1(si);
                end

                // ----------------------------------------------------------
                // k=4 : H[r][3] * y[3]   →  round_s18 + acc_q4_3
                //                                       → acc_q4_4 (Q2.12, no s1)
                // ----------------------------------------------------------
                begin
                    prod_t prr, pii, pri, pir;
                    prr = prod_t'(coef_real[gr][3]) * prod_t'(yw_r[3]);
                    pii = prod_t'(coef_imag[gr][3]) * prod_t'(yw_i[3]);
                    pri = prod_t'(coef_real[gr][3]) * prod_t'(yw_i[3]);
                    pir = prod_t'(coef_imag[gr][3]) * prod_t'(yw_r[3]);
                    p4r = prr - pii;
                    p4i = pri + pir;
                end
                begin
                    logic signed [MF_WL_W-1:0] m4r, m4i;
                    m4r = conv_round_s18(p4r);   // Q2.12
                    m4i = conv_round_s18(p4i);
                    // Both operands already Q2.12 → direct add, no s1 needed
                    acc_q4_4r = acc_q4_3r + m4r;
                    acc_q4_4i = acc_q4_3i + m4i;
                end

                // ----------------------------------------------------------
                // k=5 : H[r][4] * y[4]   →  round_s18 + acc_q4_4 → round_s1
                //                                                   → acc_q5_5 (Q5.11)
                //   (format domain transition Q4→Q5 happens here via round_s1)
                // ----------------------------------------------------------
                begin
                    prod_t prr, pii, pri, pir;
                    prr = prod_t'(coef_real[gr][4]) * prod_t'(yw_r[4]);
                    pii = prod_t'(coef_imag[gr][4]) * prod_t'(yw_i[4]);
                    pri = prod_t'(coef_real[gr][4]) * prod_t'(yw_i[4]);
                    pir = prod_t'(coef_imag[gr][4]) * prod_t'(yw_r[4]);
                    p5r = prr - pii;
                    p5i = pri + pir;
                end
                begin
                    logic signed [MF_WL_W-1:0] m5r, m5i;
                    logic signed [MF_WL_W:0]   sr,  si;
                    m5r = conv_round_s18(p5r);   // Q2.12
                    m5i = conv_round_s18(p5i);
                    sr  = signed'({acc_q4_4r[MF_WL_W-1], acc_q4_4r}) +
                          signed'({m5r[MF_WL_W-1],       m5r      });
                    si  = signed'({acc_q4_4i[MF_WL_W-1], acc_q4_4i}) +
                          signed'({m5i[MF_WL_W-1],       m5i      });
                    acc_q5_5r = conv_round_s1(sr);   // Q5.11  ← domain entry
                    acc_q5_5i = conv_round_s1(si);
                end

                // ----------------------------------------------------------
                // k=6 : H[r][5] * y[5]   →  round_s19 + acc_q5_5 → acc_q5_6 (Q5.11)
                // ----------------------------------------------------------
                begin
                    prod_t prr, pii, pri, pir;
                    prr = prod_t'(coef_real[gr][5]) * prod_t'(yw_r[5]);
                    pii = prod_t'(coef_imag[gr][5]) * prod_t'(yw_i[5]);
                    pri = prod_t'(coef_real[gr][5]) * prod_t'(yw_i[5]);
                    pir = prod_t'(coef_imag[gr][5]) * prod_t'(yw_r[5]);
                    p6r = prr - pii;
                    p6i = pri + pir;
                end
                begin
                    logic signed [MF_WL_W-1:0] m6r, m6i;
                    m6r = conv_round_s19(p6r);   // Q5.11
                    m6i = conv_round_s19(p6i);
                    acc_q5_6r = acc_q5_5r + m6r;
                    acc_q5_6i = acc_q5_5i + m6i;
                end

                // ----------------------------------------------------------
                // k=7 : H[r][6] * y[6]   →  round_s19 + acc_q5_6 → acc_q5_7 (Q5.11)
                // ----------------------------------------------------------
                begin
                    prod_t prr, pii, pri, pir;
                    prr = prod_t'(coef_real[gr][6]) * prod_t'(yw_r[6]);
                    pii = prod_t'(coef_imag[gr][6]) * prod_t'(yw_i[6]);
                    pri = prod_t'(coef_real[gr][6]) * prod_t'(yw_i[6]);
                    pir = prod_t'(coef_imag[gr][6]) * prod_t'(yw_r[6]);
                    p7r = prr - pii;
                    p7i = pri + pir;
                end
                begin
                    logic signed [MF_WL_W-1:0] m7r, m7i;
                    m7r = conv_round_s19(p7r);   // Q5.11
                    m7i = conv_round_s19(p7i);
                    acc_q5_7r = acc_q5_6r + m7r;
                    acc_q5_7i = acc_q5_6i + m7i;
                end

                // ----------------------------------------------------------
                // k=8 : H[r][7] * y[7]   →  round_s19 + acc_q5_7 → acc_q5_8 (Q5.11)
                //   FINAL combinational result for row r
                // ----------------------------------------------------------
                begin
                    prod_t prr, pii, pri, pir;
                    prr = prod_t'(coef_real[gr][7]) * prod_t'(yw_r[7]);
                    pii = prod_t'(coef_imag[gr][7]) * prod_t'(yw_i[7]);
                    pri = prod_t'(coef_real[gr][7]) * prod_t'(yw_i[7]);
                    pir = prod_t'(coef_imag[gr][7]) * prod_t'(yw_r[7]);
                    p8r = prr - pii;
                    p8i = pri + pir;
                end
                begin
                    logic signed [MF_WL_W-1:0] m8r, m8i;
                    m8r = conv_round_s19(p8r);   // Q5.11
                    m8i = conv_round_s19(p8i);
                    acc_q5_8r = acc_q5_7r + m8r;
                    acc_q5_8i = acc_q5_7i + m8i;
                end

            end : comb_mac

// ================================================================
// Output register  — latches final result on posedge clk
// ================================================================
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    z_real[gr] <= '0;
                    z_imag[gr] <= '0;
                end else if (en) begin
                    z_real[gr] <= acc_q5_8r;   // Q5.11
                    z_imag[gr] <= acc_q5_8i;
                end
            end

        end // g_comb_rows
    endgenerate

// ================================================================
// Valid / control output
//   valid_out : input register adds 1 cycle latency;
//               output register adds 1 more → total 2 cycles
// ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_out <= 1'b0;
        else if (en) valid_out <= valid_in_r;   // 2nd FF: aligns with z output
    end

endmodule
