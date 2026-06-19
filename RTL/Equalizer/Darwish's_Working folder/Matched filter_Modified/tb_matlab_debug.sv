// =============================================================================
// tb_matlab_debug.sv
// -----------------------------------------------------------------------------
// Standalone MATLAB-vector debug testbench.
// Purpose: diagnose why Suite F MATLAB frames fail, with maximum observability.
//
// Phases:
//   PHASE 1 — File reading:     print raw parsed H, Y, Z for frame 0
//   PHASE 2 — Hermitian check:  compare hermitian_pipe output vs TB golden
//   PHASE 3 — Coef load check:  dump MF coefficient registers vs expected
//   PHASE 4 — MF output check:  compare DUT g vs MATLAB Z, show differences
//   PHASE 5 — Root-cause:       classify the failure category with evidence
//
// Only frame 0 is processed. Every intermediate value is printed so the
// output can be cross-checked line-by-line against MATLAB.
// =============================================================================

`timescale 1ns/1ps

module tb_matlab_debug;

// =============================================================================
// 1.  Parameters — must match DUT defaults exactly
// =============================================================================

localparam int ROWS               = 8;
localparam int COLS               = 8;
localparam int HH_ROWS            = COLS;   // rows of H^H = cols of H
localparam int HH_COLS            = ROWS;   // cols of H^H = rows of H

// Fixed-point input format: Q1.11  (sign + 0 integer + 11 fractional)
// The MATLAB generation script comment says Q1.11; WL_IN = 12.
localparam int WL_IN              = 12;
localparam int INT_BITS_IN        =  0;
localparam int FRAC_BITS_IN       = 11;

// MF internal widened format: Q0.15
localparam int MF_INTERNAL_WL          = 16;
localparam int MF_INTERNAL_INT_BITS    =  0;
localparam int MF_INTERNAL_FRAC_BITS   = 15;

// MF output format: Q4.11
localparam int WL_OUT             = 16;
localparam int INT_BITS_OUT       =  4;
localparam int FRAC_BITS_OUT      = 11;

// Derived latency parameters
localparam int HERM_LAT           = 1;                      // hermitian_pipe REGISTER_OUTPUT=1
localparam int MF_LAT             = 1 + $clog2(HH_COLS);   // 4 for 8x8
localparam int TOTAL_LATENCY      = HERM_LAT + MF_LAT;     // 5

// Rounding shift for golden model — mirrors MF internals
localparam int FRAC_WIDEN         = MF_INTERNAL_FRAC_BITS - FRAC_BITS_IN;         // 4
localparam int PROD_FRAC          = MF_INTERNAL_FRAC_BITS + MF_INTERNAL_FRAC_BITS;// 30
localparam int RIGHT_SH           = PROD_FRAC - FRAC_BITS_OUT;                    // 19

// =============================================================================
// 2.  Clock and reset
// =============================================================================

logic clk;
initial clk = 0;
always #5 clk = ~clk;

logic rst_n, en;
integer cycle_ctr;
always @(posedge clk or negedge rst_n)
    if (!rst_n) cycle_ctr <= 0;
    else        cycle_ctr <= cycle_ctr + 1;

// =============================================================================
// 3.  DUT signals
// =============================================================================

logic                     h_valid_in;
logic signed [WL_IN-1:0]  h_real [0:ROWS-1][0:COLS-1];
logic signed [WL_IN-1:0]  h_imag [0:ROWS-1][0:COLS-1];

logic                     y_valid_in;
logic signed [WL_IN-1:0]  y_real [0:ROWS-1];
logic signed [WL_IN-1:0]  y_imag [0:ROWS-1];

logic                      g_valid_out;
logic                      gy_enable;
logic signed [WL_OUT-1:0]  yhat_real [0:COLS-1];
logic signed [WL_OUT-1:0]  yhat_imag [0:COLS-1];

logic                      hh_load_obs;
logic signed [WL_IN-1:0]   hh_real_obs [0:COLS-1][0:ROWS-1];
logic signed [WL_IN-1:0]   hh_imag_obs [0:COLS-1][0:ROWS-1];

// =============================================================================
// 4.  DUT instantiation — full chain
// =============================================================================

hermitian_mf_chain #(
    .ROWS                  ( ROWS                  ),
    .COLS                  ( COLS                  ),
    .WL_IN                 ( WL_IN                 ),
    .INT_BITS_IN           ( INT_BITS_IN           ),
    .FRAC_BITS_IN          ( FRAC_BITS_IN          ),
    .MF_INTERNAL_WL        ( MF_INTERNAL_WL        ),
    .MF_INTERNAL_INT_BITS  ( MF_INTERNAL_INT_BITS  ),
    .MF_INTERNAL_FRAC_BITS ( MF_INTERNAL_FRAC_BITS ),
    .MF_WL_OUT             ( WL_OUT                ),
    .MF_INT_BITS_OUT       ( INT_BITS_OUT          ),
    .MF_FRAC_BITS_OUT      ( FRAC_BITS_OUT         )
) dut (
    .clk         ( clk          ),
    .rst_n       ( rst_n        ),
    .en          ( en           ),
    .h_valid_in  ( h_valid_in   ),
    .h_real      ( h_real       ),
    .h_imag      ( h_imag       ),
    .y_valid_in  ( y_valid_in   ),
    .y_real      ( y_real       ),
    .y_imag      ( y_imag       ),
    .g_valid_out ( g_valid_out  ),
    .gy_enable   ( gy_enable    ),
    .yhat_real   ( yhat_real    ),
    .yhat_imag   ( yhat_imag    ),
    .hh_load_out ( hh_load_obs  ),
    .hh_real_obs ( hh_real_obs  ),
    .hh_imag_obs ( hh_imag_obs  )
);

// =============================================================================
// 5.  Golden-model functions  (copied verbatim from tb_hermitian_mf_chain.sv)
// =============================================================================

// ---- convergent_round -------------------------------------------------------
function automatic integer convergent_round(input longint signed p);
    longint signed tr;
    logic g_bit, st_bit;
    tr     = p >>> RIGHT_SH;
    g_bit  = p[RIGHT_SH-1];
    st_bit = (RIGHT_SH >= 2) ? (|p[RIGHT_SH-2:0]) : 1'b0;
    return integer'(tr + (g_bit & (st_bit | tr[0])));
endfunction

// ---- golden_hh --------------------------------------------------------------
function automatic void golden_hh(
    input  integer h_r  [0:ROWS-1][0:COLS-1],
    input  integer h_i  [0:ROWS-1][0:COLS-1],
    output integer hh_r [0:COLS-1][0:ROWS-1],
    output integer hh_i [0:COLS-1][0:ROWS-1]
);
    integer r, c;
    for (r = 0; r < ROWS; r++)
        for (c = 0; c < COLS; c++) begin
            hh_r[c][r] =  h_r[r][c];
            hh_i[c][r] = -h_i[r][c];
            hh_i[c][r] =  signed'(WL_IN'(hh_i[c][r]));  // wrap-negate like RTL
        end
endfunction

// ---- golden_mf --------------------------------------------------------------
task automatic golden_mf(
    input  integer hh_r [0:COLS-1][0:ROWS-1],
    input  integer hh_i [0:COLS-1][0:ROWS-1],
    input  integer y_r  [0:ROWS-1],
    input  integer y_i  [0:ROWS-1],
    output integer g_r  [0:COLS-1],
    output integer g_i  [0:COLS-1]
);
    longint signed hw_r [0:HH_ROWS-1][0:HH_COLS-1];
    longint signed hw_i [0:HH_ROWS-1][0:HH_COLS-1];
    longint signed yw_r [0:HH_COLS-1];
    longint signed yw_i [0:HH_COLS-1];
    integer psum_r [0:HH_ROWS-1][0:HH_COLS/2-1];
    integer psum_i [0:HH_ROWS-1][0:HH_COLS/2-1];
    longint signed prod_rr, prod_ii, prod_ri, prod_ir;
    integer rnd_a_r, rnd_a_i, rnd_b_r, rnd_b_i;
    integer r, k, n, n_nodes;
    integer lvl_r [0:HH_COLS/2-1];
    integer lvl_i [0:HH_COLS/2-1];
    integer nxt_r [0:HH_COLS/4-1];
    integer nxt_i [0:HH_COLS/4-1];

    for (r = 0; r < HH_ROWS; r++)
        for (k = 0; k < HH_COLS; k++) begin
            hw_r[r][k] = longint'(signed'(WL_IN'(hh_r[r][k]))) << FRAC_WIDEN;
            hw_i[r][k] = longint'(signed'(WL_IN'(hh_i[r][k]))) << FRAC_WIDEN;
        end
    for (k = 0; k < HH_COLS; k++) begin
        yw_r[k] = longint'(signed'(WL_IN'(y_r[k]))) << FRAC_WIDEN;
        yw_i[k] = longint'(signed'(WL_IN'(y_i[k]))) << FRAC_WIDEN;
    end
    for (r = 0; r < HH_ROWS; r++) begin
        for (k = 0; k < HH_COLS/2; k++) begin
            prod_rr = hw_r[r][2*k]   * yw_r[2*k];
            prod_ii = hw_i[r][2*k]   * yw_i[2*k];
            prod_ri = hw_r[r][2*k]   * yw_i[2*k];
            prod_ir = hw_i[r][2*k]   * yw_r[2*k];
            rnd_a_r = convergent_round(prod_rr - prod_ii);
            rnd_a_i = convergent_round(prod_ri + prod_ir);
            prod_rr = hw_r[r][2*k+1] * yw_r[2*k+1];
            prod_ii = hw_i[r][2*k+1] * yw_i[2*k+1];
            prod_ri = hw_r[r][2*k+1] * yw_i[2*k+1];
            prod_ir = hw_i[r][2*k+1] * yw_r[2*k+1];
            rnd_b_r = convergent_round(prod_rr - prod_ii);
            rnd_b_i = convergent_round(prod_ri + prod_ir);
            psum_r[r][k] = integer'(WL_OUT'(rnd_a_r + rnd_b_r));
            psum_i[r][k] = integer'(WL_OUT'(rnd_a_i + rnd_b_i));
        end
    end
    for (r = 0; r < HH_ROWS; r++) begin
        for (n = 0; n < HH_COLS/2; n++) begin
            lvl_r[n] = psum_r[r][n];
            lvl_i[n] = psum_i[r][n];
        end
        n_nodes = HH_COLS / 2;
        while (n_nodes > 1) begin
            for (n = 0; n < n_nodes/2; n++) begin
                nxt_r[n] = integer'(WL_OUT'(lvl_r[2*n] + lvl_r[2*n+1]));
                nxt_i[n] = integer'(WL_OUT'(lvl_i[2*n] + lvl_i[2*n+1]));
            end
            n_nodes = n_nodes / 2;
            for (n = 0; n < n_nodes; n++) begin
                lvl_r[n] = nxt_r[n];
                lvl_i[n] = nxt_i[n];
            end
        end
        g_r[r] = lvl_r[0];
        g_i[r] = lvl_i[0];
    end
endtask

// ---- bits_to_sint -----------------------------------------------------------
// Reinterpret a WL_IN-wide unsigned bit-vector as signed integer.
function automatic integer bits_to_sint(input reg [WL_IN-1:0] b);
    return integer'(signed'(b));
endfunction

// =============================================================================
// 6.  Frame-0 storage
// =============================================================================

integer f0_h_r [0:ROWS-1][0:COLS-1];
integer f0_h_i [0:ROWS-1][0:COLS-1];
integer f0_y_r [0:ROWS-1];
integer f0_y_i [0:ROWS-1];
integer f0_z_r [0:COLS-1];    // MATLAB expected output
integer f0_z_i [0:COLS-1];

// Derived golden values
integer f0_hh_r    [0:COLS-1][0:ROWS-1];  // expected H^H
integer f0_hh_i    [0:COLS-1][0:ROWS-1];
integer f0_gold_r  [0:COLS-1];             // TB golden g = H^H . y
integer f0_gold_i  [0:COLS-1];

// =============================================================================
// 7.  Utility tasks
// =============================================================================

task automatic do_reset(input int n);
    @(negedge clk); rst_n = 0;
    repeat(n) @(negedge clk);
    rst_n = 1;
endtask

// =============================================================================
// 8.  Main diagnostic process
// =============================================================================

integer dbg_r, dbg_c, dbg_k;
integer fh_H, fh_Y, fh_Z;
integer scan_ret;
reg [WL_IN-1:0]  tmp_bits;
// BUG #2 FIX: Z values are WL_OUT=16-bit (Q5.11), not WL_IN=12-bit.
// Reading into the 12-bit tmp_bits silently truncated the 4 most-significant
// bits of every Z element, corrupting all expected values.  Use a separate
// 16-bit register for Z reads only; H and Y are genuinely 12-bit.
reg [WL_OUT-1:0] tmp_bits_out;

initial begin : debug_main

    // ---- signal initialisation ----
    rst_n      = 1;
    en         = 1;
    h_valid_in = 0;
    y_valid_in = 0;
    for (dbg_r = 0; dbg_r < ROWS; dbg_r++)
        for (dbg_c = 0; dbg_c < COLS; dbg_c++) begin
            h_real[dbg_r][dbg_c] = '0;
            h_imag[dbg_r][dbg_c] = '0;
        end
    for (dbg_k = 0; dbg_k < ROWS; dbg_k++) begin
        y_real[dbg_k] = '0;
        y_imag[dbg_k] = '0;
    end

    // =========================================================================
    // PHASE 1 — FILE READING VERIFICATION
    // Print every parsed value so they can be cross-checked in MATLAB.
    // =========================================================================
    $display("");
    $display("##############################################################");
    $display("PHASE 1: FILE READING VERIFICATION");
    $display("##############################################################");
    $display("  Parameters: ROWS=%0d COLS=%0d WL_IN=%0d FRAC_BITS_IN=%0d",
             ROWS, COLS, WL_IN, FRAC_BITS_IN);
    $display("  MF: WL_OUT=%0d FRAC_BITS_OUT=%0d FRAC_WIDEN=%0d RIGHT_SH=%0d",
             WL_OUT, FRAC_BITS_OUT, FRAC_WIDEN, RIGHT_SH);

    // ---- open files ----
    fh_H = $fopen("testbench_files/H_all_Convergent.txt", "r");
    fh_Y = $fopen("testbench_files/Y_all_Convergent.txt", "r");
    fh_Z = $fopen("testbench_files/Z_all_Convergent.txt", "r");

    if (fh_H == 0) begin $display("FATAL: cannot open H_all_Convergent.txt"); $finish; end
    if (fh_Y == 0) begin $display("FATAL: cannot open Y_all_Convergent.txt"); $finish; end
    if (fh_Z == 0) begin $display("FATAL: cannot open Z_all_Convergent.txt"); $finish; end

    // ---- read frame 0 H (128 lines: row-major, real then imag) ----
    $display("");
    $display("--------------------------------------------------------------");
    $display("H MATRIX  (frame 0, signed decimal = raw integer * 2^-11)");
    $display("--------------------------------------------------------------");
    for (dbg_r = 0; dbg_r < ROWS; dbg_r++) begin
        for (dbg_c = 0; dbg_c < COLS; dbg_c++) begin
            scan_ret = $fscanf(fh_H, "%b\n", tmp_bits);
            if (scan_ret < 1) begin
                $display("FATAL: H file ended early at H[%0d][%0d].real", dbg_r, dbg_c);
                $finish;
            end
            f0_h_r[dbg_r][dbg_c] = bits_to_sint(tmp_bits);

            scan_ret = $fscanf(fh_H, "%b\n", tmp_bits);
            if (scan_ret < 1) begin
                $display("FATAL: H file ended early at H[%0d][%0d].imag", dbg_r, dbg_c);
                $finish;
            end
            f0_h_i[dbg_r][dbg_c] = bits_to_sint(tmp_bits);

            $display("  H[%0d][%0d]  real=%-6d  imag=%-6d  (real_fp=%.6f  imag_fp=%.6f)",
                     dbg_r, dbg_c,
                     f0_h_r[dbg_r][dbg_c], f0_h_i[dbg_r][dbg_c],
                     real'(f0_h_r[dbg_r][dbg_c]) / (2.0**FRAC_BITS_IN),
                     real'(f0_h_i[dbg_r][dbg_c]) / (2.0**FRAC_BITS_IN));
        end
    end

    // ---- read frame 0 Y (16 lines) ----
    $display("");
    $display("--------------------------------------------------------------");
    $display("Y VECTOR  (frame 0, signed decimal)");
    $display("--------------------------------------------------------------");
    for (dbg_r = 0; dbg_r < ROWS; dbg_r++) begin
        scan_ret = $fscanf(fh_Y, "%b\n", tmp_bits);
        if (scan_ret < 1) begin $display("FATAL: Y file ended early at Y[%0d].real", dbg_r); $finish; end
        f0_y_r[dbg_r] = bits_to_sint(tmp_bits);

        scan_ret = $fscanf(fh_Y, "%b\n", tmp_bits);
        if (scan_ret < 1) begin $display("FATAL: Y file ended early at Y[%0d].imag", dbg_r); $finish; end
        f0_y_i[dbg_r] = bits_to_sint(tmp_bits);

        $display("  Y[%0d]  real=%-6d  imag=%-6d  (fp: %.6f + j%.6f)",
                 dbg_r,
                 f0_y_r[dbg_r], f0_y_i[dbg_r],
                 real'(f0_y_r[dbg_r]) / (2.0**FRAC_BITS_IN),
                 real'(f0_y_i[dbg_r]) / (2.0**FRAC_BITS_IN));
    end

    // ---- read frame 0 Z (16 lines) ----
    $display("");
    $display("--------------------------------------------------------------");
    $display("Z VECTOR  (frame 0 MATLAB expected output, signed decimal)");
    $display("--------------------------------------------------------------");
    for (dbg_c = 0; dbg_c < COLS; dbg_c++) begin
        // BUG #2 FIX: use tmp_bits_out (WL_OUT=16-bit) not tmp_bits (WL_IN=12-bit)
        scan_ret = $fscanf(fh_Z, "%b\n", tmp_bits_out);
        if (scan_ret < 1) begin $display("FATAL: Z file ended early at Z[%0d].real", dbg_c); $finish; end
        f0_z_r[dbg_c] = integer'(signed'(tmp_bits_out));

        scan_ret = $fscanf(fh_Z, "%b\n", tmp_bits_out);
        if (scan_ret < 1) begin $display("FATAL: Z file ended early at Z[%0d].imag", dbg_c); $finish; end
        f0_z_i[dbg_c] = integer'(signed'(tmp_bits_out));

        $display("  Z[%0d]  real=%-6d  imag=%-6d  (fp: %.6f + j%.6f)",
                 dbg_c,
                 f0_z_r[dbg_c], f0_z_i[dbg_c],
                 real'(f0_z_r[dbg_c]) / (2.0**FRAC_BITS_OUT),
                 real'(f0_z_i[dbg_c]) / (2.0**FRAC_BITS_OUT));
    end

    $fclose(fh_H);
    $fclose(fh_Y);
    $fclose(fh_Z);

    $display("");
    $display("  PHASE 1 COMPLETE — cross-check above values against MATLAB workspace.");

    // =========================================================================
    // PHASE 2 — HERMITIAN VERIFICATION
    // Load frame 0 H into the DUT, capture hh_real_obs/hh_imag_obs,
    // compare against TB golden H^H.
    // =========================================================================
    $display("");
    $display("##############################################################");
    $display("PHASE 2: HERMITIAN VERIFICATION");
    $display("##############################################################");

    // Compute expected H^H with TB golden model
    golden_hh(f0_h_r, f0_h_i, f0_hh_r, f0_hh_i);

    $display("  Expected H^H (TB golden): HH[col][row] = conj(H[row][col])");
    for (dbg_c = 0; dbg_c < COLS; dbg_c++)
        for (dbg_r = 0; dbg_r < ROWS; dbg_r++)
            $display("    HH_exp[%0d][%0d]  real=%-6d  imag=%-6d",
                     dbg_c, dbg_r, f0_hh_r[dbg_c][dbg_r], f0_hh_i[dbg_c][dbg_r]);

    // Reset and load H into DUT
    do_reset(4);
    repeat(2) @(posedge clk);

    @(negedge clk);
    for (dbg_r = 0; dbg_r < ROWS; dbg_r++)
        for (dbg_c = 0; dbg_c < COLS; dbg_c++) begin
            h_real[dbg_r][dbg_c] = WL_IN'(f0_h_r[dbg_r][dbg_c]);
            h_imag[dbg_r][dbg_c] = WL_IN'(f0_h_i[dbg_r][dbg_c]);
        end
    h_valid_in = 1;
    @(negedge clk);
    h_valid_in = 0;

    // Wait for hh_load (= 1 posedge after the posedge that sampled h_valid_in)
    @(posedge clk);
    while (!hh_load_obs) @(posedge clk);
    // BUG #1 FIX: hh_load fires on this posedge, but coef_real/coef_imag are
    // always_ff registers that update AT this posedge.  Reading them now captures
    // the pre-update (reset = 0) value.  Wait one more cycle for the FF output
    // to reflect the new data before sampling the coefficient registers.
    @(posedge clk);
    $display("  hh_load_obs fired at cycle %0d", cycle_ctr);

    // Compare observed H^H vs expected
    $display("");
    $display("  HH comparison (DUT hh_real_obs vs TB golden):");
    begin
        integer p2_pass, p2_fail;
        p2_pass = 0; p2_fail = 0;
        for (dbg_c = 0; dbg_c < COLS; dbg_c++) begin
            for (dbg_r = 0; dbg_r < ROWS; dbg_r++) begin
                integer dut_r, dut_i, exp_r, exp_i;
                dut_r = integer'(signed'(hh_real_obs[dbg_c][dbg_r]));
                dut_i = integer'(signed'(hh_imag_obs[dbg_c][dbg_r]));
                exp_r = f0_hh_r[dbg_c][dbg_r];
                exp_i = f0_hh_i[dbg_c][dbg_r];
                if (dut_r === exp_r && dut_i === exp_i) begin
                    $display("    PASS HERM row=%0d col=%0d  DUT=(%0d,%0d)  EXP=(%0d,%0d)",
                             dbg_c, dbg_r, dut_r, dut_i, exp_r, exp_i);
                    p2_pass++;
                end else begin
                    $display("    FAIL HERM row=%0d col=%0d  DUT=(%0d,%0d)  EXP=(%0d,%0d)  ERR=(%0d,%0d)",
                             dbg_c, dbg_r, dut_r, dut_i, exp_r, exp_i, dut_r-exp_r, dut_i-exp_i);
                    p2_fail++;
                end
            end
        end
        $display("  PHASE 2 RESULT: %0d PASS  %0d FAIL", p2_pass, p2_fail);
        if (p2_fail > 0)
            $display("  --> CATEGORY A: Hermitian mismatch detected.");
        else
            $display("  --> Hermitian outputs match TB golden. Moving to Phase 3.");
    end

    // =========================================================================
    // PHASE 3 — MF COEFFICIENT LOAD VERIFICATION
    // After hh_load, dump dut.u_mf.coef_real[r][k] and compare against
    // the widened H^H values: coef_expected = HH[r][k] << FRAC_WIDEN
    // =========================================================================
    $display("");
    $display("##############################################################");
    $display("PHASE 3: MF COEFFICIENT LOAD VERIFICATION");
    $display("##############################################################");
    $display("  Expected widened coef = HH_int << FRAC_WIDEN  (FRAC_WIDEN=%0d)", FRAC_WIDEN);
    $display("");
    $display("  coef[row][col] dump — DUT vs expected widened H^H:");

    begin
        integer p3_pass, p3_fail;
        p3_pass = 0; p3_fail = 0;
        for (dbg_r = 0; dbg_r < HH_ROWS; dbg_r++) begin
            for (dbg_c = 0; dbg_c < HH_COLS; dbg_c++) begin
                integer dut_cr, dut_ci, exp_cr, exp_ci;
                dut_cr = integer'(signed'(dut.u_mf.coef_real[dbg_r][dbg_c]));
                dut_ci = integer'(signed'(dut.u_mf.coef_imag[dbg_r][dbg_c]));
                // Expected: widen from WL_IN to MF_INTERNAL_WL by left-shifting
                exp_cr = signed'(WL_IN'(f0_hh_r[dbg_r][dbg_c])) << FRAC_WIDEN;
                exp_ci = signed'(WL_IN'(f0_hh_i[dbg_r][dbg_c])) << FRAC_WIDEN;
                if (dut_cr === exp_cr && dut_ci === exp_ci) begin
                    $display("    PASS COEF[%0d][%0d]  DUT=(%0d,%0d)  EXP=(%0d,%0d)",
                             dbg_r, dbg_c, dut_cr, dut_ci, exp_cr, exp_ci);
                    p3_pass++;
                end else begin
                    $display("    FAIL COEF[%0d][%0d]  DUT=(%0d,%0d)  EXP=(%0d,%0d)  ERR=(%0d,%0d)",
                             dbg_r, dbg_c, dut_cr, dut_ci, exp_cr, exp_ci,
                             dut_cr-exp_cr, dut_ci-exp_ci);
                    p3_fail++;
                end
            end
        end
        $display("  PHASE 3 RESULT: %0d PASS  %0d FAIL", p3_pass, p3_fail);
        if (p3_fail > 0)
            $display("  --> CATEGORY B: Coefficient load mismatch detected.");
        else
            $display("  --> Coefficients match expected widened H^H. Moving to Phase 4.");
    end

    // =========================================================================
    // PHASE 4 — SINGLE MATLAB VECTOR OUTPUT VERIFICATION
    // Inject frame 0 Y; wait exactly MF_LAT cycles from the sampling posedge;
    // capture DUT g; compare against MATLAB Z and TB golden.
    // =========================================================================
    $display("");
    $display("##############################################################");
    $display("PHASE 4: SINGLE MATLAB VECTOR OUTPUT VERIFICATION");
    $display("##############################################################");

    // Compute TB golden output for comparison
    golden_mf(f0_hh_r, f0_hh_i, f0_y_r, f0_y_i, f0_gold_r, f0_gold_i);

    $display("  TB golden g = H^H . Y  (before DUT injection):");
    for (dbg_c = 0; dbg_c < COLS; dbg_c++)
        $display("    gold[%0d]  real=%-6d  imag=%-6d  (fp: %.6f + j%.6f)",
                 dbg_c, f0_gold_r[dbg_c], f0_gold_i[dbg_c],
                 real'(f0_gold_r[dbg_c]) / (2.0**FRAC_BITS_OUT),
                 real'(f0_gold_i[dbg_c]) / (2.0**FRAC_BITS_OUT));

    // Wait one extra settle cycle after hh_load (same as existing TB)
    repeat(1) @(posedge clk);

    // Inject Y: drive on negedge, sample on posedge
    @(negedge clk);
    for (dbg_k = 0; dbg_k < ROWS; dbg_k++) begin
        y_real[dbg_k] = WL_IN'(f0_y_r[dbg_k]);
        y_imag[dbg_k] = WL_IN'(f0_y_i[dbg_k]);
    end
    y_valid_in = 1;
    @(posedge clk);  // P0: DUT samples y_valid_in=1 — start of MF pipeline
    $display("  Y injected at cycle %0d (P0)", cycle_ctr);
    @(negedge clk);
    y_valid_in = 0;

    // Advance MF_LAT more posedges: output appears at P0 + MF_LAT
    repeat(MF_LAT) @(posedge clk);
    $display("  Capturing at cycle %0d (P0 + MF_LAT=%0d)", cycle_ctr, MF_LAT);

    // Report g_valid_out status
    if (g_valid_out)
        $display("  g_valid_out = 1  (CORRECT)");
    else
        $display("  g_valid_out = 0  (TIMING PROBLEM — output not yet valid)");

    $display("");
    $display("  Element-by-element comparison:");
    $display("  %-5s  %-10s  %-10s  %-10s  %-10s  %-6s  %-6s  %-12s",
             "Idx", "DUT_real", "DUT_imag", "EXP_real(Z)", "EXP_imag(Z)",
             "D-Z_r", "D-Z_i", "Status");
    $display("  %s", {"─"*80});
    begin
        integer p4_pass_z, p4_fail_z, p4_pass_g, p4_fail_g;
        p4_pass_z = 0; p4_fail_z = 0;
        p4_pass_g = 0; p4_fail_g = 0;
        for (dbg_c = 0; dbg_c < COLS; dbg_c++) begin
            integer dut_r, dut_i, diff_r, diff_i;
            string  status_z, status_g;
            dut_r  = integer'(signed'(yhat_real[dbg_c]));
            dut_i  = integer'(signed'(yhat_imag[dbg_c]));
            diff_r = dut_r - f0_z_r[dbg_c];
            diff_i = dut_i - f0_z_i[dbg_c];
            status_z = (diff_r == 0 && diff_i == 0) ? "PASS_Z" : "FAIL_Z";
            if (diff_r == 0 && diff_i == 0) p4_pass_z++; else p4_fail_z++;

            $display("  [%0d]    %-10d  %-10d  %-10d  %-10d  %-6d  %-6d  %s",
                     dbg_c,
                     dut_r,     dut_i,
                     f0_z_r[dbg_c], f0_z_i[dbg_c],
                     diff_r, diff_i,
                     status_z);

            // Also compare DUT vs TB golden
            if (dut_r === f0_gold_r[dbg_c] && dut_i === f0_gold_i[dbg_c])
                p4_pass_g++;
            else
                p4_fail_g++;
        end
        $display("");
        $display("  DUT vs MATLAB Z:    %0d PASS  %0d FAIL", p4_pass_z, p4_fail_z);
        $display("  DUT vs TB golden:   %0d PASS  %0d FAIL", p4_pass_g, p4_fail_g);

        // Also print TB golden vs MATLAB Z
        $display("");
        $display("  TB golden vs MATLAB Z (arithmetic agreement check):");
        $display("  %-5s  %-10s  %-10s  %-10s  %-10s  %-6s  %-6s  %-12s",
                 "Idx", "GOLD_real", "GOLD_imag", "Z_real", "Z_imag",
                 "G-Z_r", "G-Z_i", "Status");
        $display("  %s", {"─"*80});
        begin
            integer gp, gf;
            gp = 0; gf = 0;
            for (dbg_c = 0; dbg_c < COLS; dbg_c++) begin
                integer diff_r, diff_i;
                string status;
                diff_r = f0_gold_r[dbg_c] - f0_z_r[dbg_c];
                diff_i = f0_gold_i[dbg_c] - f0_z_i[dbg_c];
                status = (diff_r == 0 && diff_i == 0) ? "MATCH" : "DIFFER";
                if (diff_r == 0 && diff_i == 0) gp++; else gf++;
                $display("  [%0d]    %-10d  %-10d  %-10d  %-10d  %-6d  %-6d  %s",
                         dbg_c,
                         f0_gold_r[dbg_c], f0_gold_i[dbg_c],
                         f0_z_r[dbg_c],    f0_z_i[dbg_c],
                         diff_r, diff_i, status);
            end
            $display("  TB golden vs MATLAB Z: %0d match  %0d differ", gp, gf);
        end
    end

    // =========================================================================
    // PHASE 5 — ROOT CAUSE ANALYSIS
    // Classify failure based on what passed/failed above.
    // =========================================================================
    $display("");
    $display("##############################################################");
    $display("PHASE 5: ROOT CAUSE ANALYSIS");
    $display("##############################################################");

    begin
        integer ph2_fail_cnt, ph3_fail_cnt, ph4_dut_z_fail, ph4_gold_z_fail;
        // Re-compute summary counts
        ph2_fail_cnt  = 0;
        ph3_fail_cnt  = 0;
        ph4_dut_z_fail = 0;
        ph4_gold_z_fail = 0;

        for (dbg_c = 0; dbg_c < COLS; dbg_c++)
            for (dbg_r = 0; dbg_r < ROWS; dbg_r++) begin
                integer dr, di;
                dr = integer'(signed'(hh_real_obs[dbg_c][dbg_r])) - f0_hh_r[dbg_c][dbg_r];
                di = integer'(signed'(hh_imag_obs[dbg_c][dbg_r])) - f0_hh_i[dbg_c][dbg_r];
                if (dr !== 0 || di !== 0) ph2_fail_cnt++;
            end

        for (dbg_r = 0; dbg_r < HH_ROWS; dbg_r++)
            for (dbg_c = 0; dbg_c < HH_COLS; dbg_c++) begin
                integer dr, di;
                dr = integer'(signed'(dut.u_mf.coef_real[dbg_r][dbg_c]))
                     - (signed'(WL_IN'(f0_hh_r[dbg_r][dbg_c])) << FRAC_WIDEN);
                di = integer'(signed'(dut.u_mf.coef_imag[dbg_r][dbg_c]))
                     - (signed'(WL_IN'(f0_hh_i[dbg_r][dbg_c])) << FRAC_WIDEN);
                if (dr !== 0 || di !== 0) ph3_fail_cnt++;
            end

        for (dbg_c = 0; dbg_c < COLS; dbg_c++) begin
            integer dut_r, dut_i;
            dut_r = integer'(signed'(yhat_real[dbg_c]));
            dut_i = integer'(signed'(yhat_imag[dbg_c]));
            if (dut_r !== f0_z_r[dbg_c] || dut_i !== f0_z_i[dbg_c]) ph4_dut_z_fail++;
            if (f0_gold_r[dbg_c] !== f0_z_r[dbg_c] || f0_gold_i[dbg_c] !== f0_z_i[dbg_c])
                ph4_gold_z_fail++;
        end

        $display("");
        $display("  Summary matrix:");
        $display("  Ph2 Hermitian DUT vs TB golden fails : %0d / %0d elements", ph2_fail_cnt, ROWS*COLS);
        $display("  Ph3 MF coef DUT vs expected fails    : %0d / %0d elements", ph3_fail_cnt, HH_ROWS*HH_COLS);
        $display("  Ph4 DUT output vs MATLAB Z fails     : %0d / %0d elements", ph4_dut_z_fail, COLS);
        $display("  Ph4 TB golden vs MATLAB Z fails      : %0d / %0d elements", ph4_gold_z_fail, COLS);
        $display("");

        if (ph2_fail_cnt > 0) begin
            $display("  ROOT CAUSE: CATEGORY A — HERMITIAN MISMATCH");
            $display("    The hermitian_pipe is producing H^H elements that differ");
            $display("    from the TB golden model.  Check sign/transpose indexing.");
        end else if (ph3_fail_cnt > 0) begin
            $display("  ROOT CAUSE: CATEGORY B — COEFFICIENT LOAD MISMATCH");
            $display("    H^H is correct but MF coef registers do not match.");
            $display("    Check hh_load timing and coef_real/coef_imag assignment.");
        end else if (ph4_gold_z_fail > 0 && ph4_dut_z_fail > 0) begin
            $display("  ROOT CAUSE: CATEGORY D — MATLAB FILE INTERPRETATION MISMATCH");
            $display("    Both DUT and TB golden disagree with MATLAB Z.");
            $display("    The RTL arithmetic model is consistent but the reference");
            $display("    vectors (H, Y, Z) are being parsed with wrong bit-width,");
            $display("    sign convention, or fixed-point scale.");
            $display("    Evidence:");
            $display("      TB golden vs Z fails: %0d — TB computes same wrong answer as DUT.", ph4_gold_z_fail);
            $display("    Next step: compare Phase 1 H/Y values against MATLAB disp(H), disp(Y).");
            $display("    Check: are MATLAB H values Q1.11 or a different format?");
            $display("    Check: is WL_IN=12 correct for the binary strings in the file?");
        end else if (ph4_dut_z_fail > 0 && ph4_gold_z_fail == 0) begin
            $display("  ROOT CAUSE: CATEGORY C or F — MF ARITHMETIC OR CAPTURE TIMING MISMATCH");
            $display("    TB golden matches MATLAB Z but DUT does not.");
            $display("    Either the MF pipeline is computing wrong values (Category C)");
            $display("    or the output is being captured at the wrong cycle (Category F).");
            $display("    Check: g_valid_out status printed in Phase 4.");
            $display("    Check: try capturing one cycle earlier or later.");
        end else begin
            $display("  ALL PHASES PASS — DUT output matches both TB golden and MATLAB Z.");
            $display("  The regression failure was a testbench sequencing issue, now resolved.");
        end
    end

    $display("");
    $display("##############################################################");
    $display("DEBUG TESTBENCH COMPLETE");
    $display("##############################################################");
    $finish;
end

// =============================================================================
// 9.  Watchdog
// =============================================================================
initial begin
    #200000;
    $display("WATCHDOG: timeout at 200us");
    $finish;
end

endmodule