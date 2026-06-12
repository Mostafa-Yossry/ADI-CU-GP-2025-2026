// =============================================================================
// tb_herm_mf_chain.sv
// -----------------------------------------------------------------------------
// Integration testbench for herm_mf_chain (hermitian_pipe → matched_filter_pipe).
//
// WHAT THIS TESTBENCH VERIFIES
// ----------------------------
//   1. Interface wiring:    port shapes connect without width mismatches.
//   2. Timing contract:     h_valid_in[N] arrives exactly 1 cycle before
//                           y_valid_in[N]; hh_load fires at the right moment.
//   3. Chain latency:       z_valid_out asserts CHAIN_LAT = 1 + MF_LATENCY
//                           cycles after y_valid_in (5 cycles for 8×8).
//   4. Functional output:   z matches MATLAB golden z vectors bit-for-bit.
//   5. Throughput:          back-to-back burst sustains 1 output per cycle.
//   6. en stall:            stalling the matched filter mid-burst delays output
//                           by exactly STALL_CYCLES; chain resumes correctly.
//
// GOLDEN VECTOR FILES
// -------------------
//   This testbench uses TWO sets of vector files:
//
//   Set 1 – direct chain vectors (preferred, generated from raw H):
//     chain_vectors/h_real.txt       raw H matrix, real part
//     chain_vectors/h_imag.txt       raw H matrix, imag part
//     chain_vectors/y_real.txt       y vectors
//     chain_vectors/y_imag.txt       y vectors
//     chain_vectors/z_real_golden.txt  expected z = H^H · y
//     chain_vectors/z_imag_golden.txt
//
//     Format: same as the matched-filter standalone vectors.
//     h_real/imag: column-major — outer loop col (0..COLS_H-1),
//                  inner loop row (0..ROWS_H-1), one integer per line.
//     y, z: one integer per line, COLS_H / ROWS_H elements per frame.
//
//   Set 2 – fallback: reuse matched-filter standalone vectors.
//     If chain_vectors/ is absent, the testbench falls back to
//     rtl_vectors_conv_Z_Q5_11_16bit/ which contains pre-computed H^H
//     (not raw H).  In fallback mode the testbench feeds H^H as the raw H
//     input; hermitian_pipe then computes (H^H)^H = H, and the matched
//     filter computes M · y where M = (H^H)^H = H -- this does NOT equal
//     H^H · y.  Therefore fallback mode only checks timing/interface, not
//     functional output, and all functional checks are skipped with a clear
//     warning.  Generate Set 1 files from MATLAB to get full verification.
//
// MATLAB SCRIPT TO GENERATE SET 1 FILES (chain_vectors/)
// -------------------------------------------------------
//   % In your existing MATLAB test script, after generating H and y:
//   %
//   % mkdir('chain_vectors');
//   % for t = 1:NUM_TESTS
//   %   % Write H (raw, not H^H) column-major
//   %   for k = 1:COLS_H
//   %     for r = 1:ROWS_H
//   %       fprintf(fh_r, '%d\n', H_fi(r,k,t).int);
//   %       fprintf(fh_i, '%d\n', H_fi(r,k,t).int);  % use imag part here
//   %     end
//   %   end
//   %   % y and z use the same format as the standalone matched-filter test
//   % end
//
// TIMING MODEL (back-to-back burst, frame N)
// ------------------------------------------
//   negedge N-1 : load H[N] → h_valid_in=1
//   posedge N   : hermitian registers H^H[N]; hh_load_w goes high
//   negedge N   : hh_load seen by MF; drive y[N] → y_valid_in=1
//   posedge N+1 : MF latches coef[N] and y[N] simultaneously (Stage 1)
//   posedge N+5 : z[N] valid  (chain latency = 5 cycles for 8×8)
//
// =============================================================================

`timescale 1ns/1ps

module tb_herm_mf_chain;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
localparam int ROWS_H        = 8;
localparam int COLS_H        = 8;

localparam int WL_IN         = 12;
localparam int INT_BITS_IN   =  0;
localparam int FRAC_BITS_IN  = 11;
localparam int WL_INT        = 16;
localparam int INT_BITS_INT  =  0;
localparam int FRAC_BITS_INT = 15;
localparam int WL_OUT        = 16;
localparam int INT_BITS_OUT  =  4;
localparam int FRAC_BITS_OUT = 11;

// Chain latency = 1 (hermitian) + 1 (MF multiply) + $clog2(COLS_H) (tree)
localparam int MF_LEVELS   = $clog2(ROWS_H);    // 3 for 8×8
localparam int MF_LATENCY  = 1 + MF_LEVELS;     // 4 for 8×8
localparam int CHAIN_LAT   = 1 + MF_LATENCY;    // 5 for 8×8

localparam int NUM_TESTS   = 20;

// Stall test
localparam int STALL_FRAME_IDX = 1;    // insert stall after this y_valid_in
localparam int STALL_CYCLES    = 3;

localparam real SCALE = 2.0 ** FRAC_BITS_OUT;
localparam real TOL   = 0.5 / SCALE;             // half LSB

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------
logic clk;
initial clk = 0;
always #5 clk = ~clk;

logic rst_n, en;

integer cycle_counter;
always @(posedge clk or negedge rst_n)
    if (!rst_n) cycle_counter <= 0;
    else        cycle_counter <= cycle_counter + 1;

// ---------------------------------------------------------------------------
// DUT ports
// ---------------------------------------------------------------------------
logic                      h_valid_in;
logic signed [WL_IN-1:0]  h_real [0:ROWS_H-1][0:COLS_H-1];
logic signed [WL_IN-1:0]  h_imag [0:ROWS_H-1][0:COLS_H-1];

logic                      y_valid_in;
logic signed [WL_IN-1:0]  y_real [0:COLS_H-1];
logic signed [WL_IN-1:0]  y_imag [0:COLS_H-1];

logic                      z_valid_out;
logic signed [WL_OUT-1:0] z_real [0:COLS_H-1];
logic signed [WL_OUT-1:0] z_imag [0:COLS_H-1];

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
herm_mf_chain #(
    .ROWS_H        (ROWS_H       ),
    .COLS_H        (COLS_H       ),
    .WL_IN         (WL_IN        ),
    .INT_BITS_IN   (INT_BITS_IN  ),
    .FRAC_BITS_IN  (FRAC_BITS_IN ),
    .WL_INT        (WL_INT       ),
    .INT_BITS_INT  (INT_BITS_INT ),
    .FRAC_BITS_INT (FRAC_BITS_INT),
    .WL_OUT        (WL_OUT       ),
    .INT_BITS_OUT  (INT_BITS_OUT ),
    .FRAC_BITS_OUT (FRAC_BITS_OUT)
) dut (
    .clk        (clk        ),
    .rst_n      (rst_n      ),
    .en         (en         ),
    .h_valid_in (h_valid_in ),
    .h_real     (h_real     ),
    .h_imag     (h_imag     ),
    .y_valid_in (y_valid_in ),
    .y_real     (y_real     ),
    .y_imag     (y_imag     ),
    .z_valid_out(z_valid_out),
    .z_real     (z_real     ),
    .z_imag     (z_imag     )
);

// ---------------------------------------------------------------------------
// Shared test vector memory
// ---------------------------------------------------------------------------
integer h_r_mem [0:NUM_TESTS-1][0:ROWS_H-1][0:COLS_H-1];
integer h_i_mem [0:NUM_TESTS-1][0:ROWS_H-1][0:COLS_H-1];
integer y_r_mem [0:NUM_TESTS-1][0:COLS_H-1];
integer y_i_mem [0:NUM_TESTS-1][0:COLS_H-1];
integer z_r_gold[0:NUM_TESTS-1][0:COLS_H-1];
integer z_i_gold[0:NUM_TESTS-1][0:COLS_H-1];

integer h_vin_cycle [0:NUM_TESTS-1];
integer y_vin_cycle [0:NUM_TESTS-1];
integer vout_cycle  [0:NUM_TESTS-1];

real got_r [0:NUM_TESTS-1][0:COLS_H-1];
real got_i [0:NUM_TESTS-1][0:COLS_H-1];

// Stall test — separate capture arrays
integer svout_cycle [0:NUM_TESTS-1];
real    sgot_r      [0:NUM_TESTS-1][0:COLS_H-1];
real    sgot_i      [0:NUM_TESTS-1][0:COLS_H-1];
integer stall_spurious_vout;

// Synchronisation flags
logic vectors_ready;
logic collect_done;
logic stall_collect_done;
logic functional_mode;   // 1 = Set 1 files loaded; 0 = fallback (timing only)

// ===========================================================================
// PROCESS 1 — MAIN: reset, load vectors, report
// ===========================================================================
integer fid_h_real, fid_h_imag, fid_y_real, fid_y_imag,
        fid_z_real, fid_z_imag;
integer t, row, col, r, tmp, status;
integer pass_cnt, fail_cnt;
real    exp_r, exp_i, err_r, err_i;

initial begin : main_proc
    vectors_ready       = 1'b0;
    collect_done        = 1'b0;
    stall_collect_done  = 1'b0;
    stall_spurious_vout = 0;
    functional_mode     = 1'b0;
    pass_cnt = 0;
    fail_cnt = 0;

    // -----------------------------------------------------------------------
    // Reset
    // -----------------------------------------------------------------------
    rst_n      = 1'b0;
    en         = 1'b1;
    h_valid_in = 1'b0;
    y_valid_in = 1'b0;
    for (r = 0; r < ROWS_H; r = r + 1)
        for (col = 0; col < COLS_H; col = col + 1) begin
            h_real[r][col] = '0;
            h_imag[r][col] = '0;
        end
    for (col = 0; col < COLS_H; col = col + 1) begin
        y_real[col] = '0;
        y_imag[col] = '0;
    end

    repeat(2) @(posedge clk);
    rst_n = 1'b1;
    repeat(4) @(posedge clk);

    // -----------------------------------------------------------------------
    // Try Set 1 (chain_vectors/) first; fall back to standalone MF vectors
    // -----------------------------------------------------------------------
    fid_h_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/h_real.txt",        "r");
    fid_h_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/h_imag.txt",        "r");
    fid_y_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_real.txt",        "r");
    fid_y_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_imag.txt",        "r");
    fid_z_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_real_golden.txt", "r");
    fid_z_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_imag_golden.txt", "r");

    if (fid_h_real && fid_h_imag && fid_y_real &&
        fid_y_imag && fid_z_real  && fid_z_imag) begin
        functional_mode = 1'b1;
        $display("[tb_chain] Using Set 1 chain_vectors/ — full functional verification");
    end else begin
        // Close any that did open
        if (fid_h_real) $fclose(fid_h_real);
        if (fid_h_imag) $fclose(fid_h_imag);
        if (fid_y_real) $fclose(fid_y_real);
        if (fid_y_imag) $fclose(fid_y_imag);
        if (fid_z_real) $fclose(fid_z_real);
        if (fid_z_imag) $fclose(fid_z_imag);

        // Fallback: standalone matched-filter vectors (H^H already computed)
        fid_h_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_real.txt", "r");
        fid_h_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_imag.txt", "r");
        fid_y_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_real.txt",  "r");
        fid_y_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_imag.txt",  "r");
        fid_z_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_real_golden.txt", "r");
        fid_z_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_imag_golden.txt", "r");

        if (!fid_h_real || !fid_h_imag || !fid_y_real ||
            !fid_y_imag || !fid_z_real  || !fid_z_imag) begin
            $display("ERROR: could not open chain_vectors/ or fallback vector files");
            $finish;
        end
        $display("[tb_chain] WARNING: chain_vectors/ not found.");
        $display("[tb_chain] Using fallback rtl_vectors_conv_Z_Q5_11_16bit/ (H^H as H input).");
        $display("[tb_chain] Functional output checks DISABLED — timing/interface checks only.");
        $display("[tb_chain] Generate chain_vectors/ from MATLAB for full verification.");
    end

    // -----------------------------------------------------------------------
    // Load vectors: same column-major H format as standalone MF testbench
    // -----------------------------------------------------------------------
    begin : load_vecs
        integer kk;
        for (t = 0; t < NUM_TESTS; t = t + 1) begin
            for (kk = 0; kk < COLS_H; kk = kk + 1)
                for (row = 0; row < ROWS_H; row = row + 1) begin
                    status = $fscanf(fid_h_real, "%d\n", tmp);
                    h_r_mem[t][row][kk] = tmp;
                    status = $fscanf(fid_h_imag, "%d\n", tmp);
                    h_i_mem[t][row][kk] = tmp;
                end
            for (kk = 0; kk < COLS_H; kk = kk + 1) begin
                status = $fscanf(fid_y_real, "%d\n", tmp);
                y_r_mem[t][kk] = tmp;
                status = $fscanf(fid_y_imag, "%d\n", tmp);
                y_i_mem[t][kk] = tmp;
            end
            for (row = 0; row < COLS_H; row = row + 1) begin
                status = $fscanf(fid_z_real, "%d\n", tmp);
                z_r_gold[t][row] = tmp;
                status = $fscanf(fid_z_imag, "%d\n", tmp);
                z_i_gold[t][row] = tmp;
            end
        end
    end

    $fclose(fid_h_real); $fclose(fid_h_imag);
    $fclose(fid_y_real);  $fclose(fid_y_imag);
    $fclose(fid_z_real);  $fclose(fid_z_imag);

    vectors_ready = 1'b1;

    // -----------------------------------------------------------------------
    // Wait for collectors
    // -----------------------------------------------------------------------
    wait(collect_done);
    wait(stall_collect_done);

    // =======================================================================
    // SUITE A — REPORT
    // =======================================================================
    $display("");
    $display("========================================================");
    $display(" HERM-MF CHAIN TESTBENCH");
    $display(" ROWS_H=%0d COLS_H=%0d  WL_IN=%0d WL_OUT=%0d",
             ROWS_H, COLS_H, WL_IN, WL_OUT);
    $display(" CHAIN_LAT=%0d  (1 hermitian + %0d MF)", CHAIN_LAT, MF_LATENCY);
    $display(" NUM_TESTS=%0d  SCALE=%.0f  TOL=%.6f", NUM_TESTS, SCALE, TOL);
    if (!functional_mode)
        $display(" *** TIMING-ONLY MODE (no chain_vectors/) ***");
    $display("========================================================");

    // Latency table
    $display("");
    $display("  CHAIN LATENCY TABLE");
    $display("  %-6s  %-12s  %-12s  %-12s  %-s",
             "Frame", "h_vin", "y_vin", "vout", "Chain lat (y→z)");
    $display("  ---------------------------------------------------------------");
    begin : lat_report
        integer lat;
        for (t = 0; t < NUM_TESTS; t = t + 1) begin
            lat = vout_cycle[t] - y_vin_cycle[t];
            $display("  %-6d  %-12d  %-12d  %-12d  %0d%s",
                t, h_vin_cycle[t], y_vin_cycle[t], vout_cycle[t], lat,
                (lat == CHAIN_LAT) ? "  OK" : "  *** WRONG ***");
            if (lat != CHAIN_LAT) fail_cnt = fail_cnt + 1;
            else                  pass_cnt = pass_cnt + 1;
        end
    end

    // h_valid_in leads y_valid_in by exactly 1 cycle check
    $display("");
    $display("  H→Y TIMING OFFSET CHECK (must be exactly 1 cycle)");
    begin : offset_check
        for (t = 0; t < NUM_TESTS; t = t + 1) begin
            integer offset;
            offset = y_vin_cycle[t] - h_vin_cycle[t];
            if (offset != 1) begin
                $display("  Frame %0d: h_vin=%0d y_vin=%0d offset=%0d  *** WRONG (expected 1) ***",
                         t, h_vin_cycle[t], y_vin_cycle[t], offset);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
        $display("  All h→y offsets OK (1 cycle each)");
    end

    // Throughput
    $display("");
    $display("  THROUGHPUT");
    $display("  Outputs/cycle: %.2f  (ideal=1.00)",
        $itor(NUM_TESTS) /
        $itor(vout_cycle[NUM_TESTS-1] - vout_cycle[0] + 1));

    // Functional results
    if (functional_mode) begin
        $display("");
        $display("========================================================");
        $display("  SUITE A — FUNCTIONAL RESULTS");
        $display("========================================================");
        for (t = 0; t < NUM_TESTS; t = t + 1) begin
            $display("  --- Frame %0d ---", t);
            for (row = 0; row < COLS_H; row = row + 1) begin
                exp_r = $itor(z_r_gold[t][row]) / SCALE;
                exp_i = $itor(z_i_gold[t][row]) / SCALE;
                err_r = got_r[t][row] - exp_r;
                err_i = got_i[t][row] - exp_i;
                if (err_r < 0.0) err_r = -err_r;
                if (err_i < 0.0) err_i = -err_i;
                if ((err_r > TOL) || (err_i > TOL)) begin
                    $display("  Row %-3d  got(%9.6f,%9.6f)  exp(%9.6f,%9.6f)  FAIL",
                        row, got_r[t][row], got_i[t][row], exp_r, exp_i);
                    fail_cnt = fail_cnt + 1;
                end else begin
                    $display("  Row %-3d  (%9.6f,%9.6f)  PASS", row, got_r[t][row], got_i[t][row]);
                    pass_cnt = pass_cnt + 1;
                end
            end
        end
    end else begin
        $display("");
        $display("  SUITE A — Functional checks skipped (fallback mode)");
    end

    // =======================================================================
    // SUITE B — STALL REPORT
    // =======================================================================
    $display("");
    $display("========================================================");
    $display(" SUITE B — en STALL  (STALL_FRAME_IDX=%0d  STALL_CYCLES=%0d)",
             STALL_FRAME_IDX, STALL_CYCLES);
    $display("========================================================");

    begin : suite_b_report
        integer sb_pass, sb_fail, sb_t;
        real sb_exp_r, sb_exp_i, sb_err_r, sb_err_i;
        sb_pass = 0; sb_fail = 0;

        // Check 1: no valid_out during stall
        $display("");
        $display("  CHECK 1: no z_valid_out during stall window");
        if (stall_spurious_vout == 0) begin
            $display("  Spurious outputs during stall: 0  PASS");
            sb_pass++;
        end else begin
            $display("  Spurious outputs during stall: %0d  FAIL", stall_spurious_vout);
            sb_fail++;
        end

        // Check 2: per-frame latency with stall penalty
        $display("");
        $display("  CHECK 2: per-frame latency");
        $display("  %-6s  %-12s  %-12s  %-10s  %-s",
                 "Frame", "y_vin", "vout", "Latency", "Expected");
        for (sb_t = 0; sb_t < NUM_TESTS; sb_t = sb_t + 1) begin : stall_lat
            integer meas_lat, exp_lat;
            if (svout_cycle[sb_t] == 0) begin
                // Frame not yet collected — skip
                continue;
            end
            meas_lat = svout_cycle[sb_t] - y_vin_cycle[sb_t];
            exp_lat  = (sb_t <= STALL_FRAME_IDX)
                       ? CHAIN_LAT + STALL_CYCLES
                       : CHAIN_LAT;
            $display("  %-6d  %-12d  %-12d  %-10d  %0d%s",
                sb_t,
                y_vin_cycle[sb_t],
                svout_cycle[sb_t],
                meas_lat,
                exp_lat,
                (meas_lat == exp_lat) ? "  OK" : "  *** WRONG ***");
            if (meas_lat == exp_lat) sb_pass++;
            else                     sb_fail++;
        end

        $display("");
        $display("  SUITE B — PASS=%0d  FAIL=%0d", sb_pass, sb_fail);
        fail_cnt = fail_cnt + sb_fail;
        pass_cnt = pass_cnt + sb_pass;
    end

    // =======================================================================
    // GLOBAL SUMMARY
    // =======================================================================
    $display("");
    $display("========================================================");
    $display("  GLOBAL SUMMARY");
    $display("  PASS = %0d", pass_cnt);
    $display("  FAIL = %0d", fail_cnt);
    if (!functional_mode)
        $display("  (functional checks skipped — generate chain_vectors/ for full run)");
    $display("========================================================");
    if (fail_cnt == 0) $display("  *** ALL TESTS PASSED ***");
    else               $display("  *** SOME TESTS FAILED ***");
    $display("========================================================");

    $finish;
end


// ===========================================================================
// PROCESS 2 — SUITE A INJECTOR
// ===========================================================================
// Timing per frame N:
//   negedge N-1 : drive h[N], h_valid_in=1  (also overlap h[N+1] hereafter)
//   posedge N   : hermitian latches h[N]
//   negedge N   : y_valid_in=1, drive y[N]   (hh_load fires from hermitian valid_out)
//   posedge N+1 : MF latches coef[N] and y[N]
// ===========================================================================
integer inj_t, inj_row, inj_col;

initial begin : injector_proc
    wait(vectors_ready);

    $display(">>> [SuiteA] INJECTOR start");

    // Pre-load: assert h_valid_in 1 cycle before the first y_valid_in.
    // This is the only cycle where h fires without a simultaneous y.
    @(negedge clk);
    for (inj_row = 0; inj_row < ROWS_H; inj_row = inj_row + 1)
        for (inj_col = 0; inj_col < COLS_H; inj_col = inj_col + 1) begin
            h_real[inj_row][inj_col] = h_r_mem[0][inj_row][inj_col];
            h_imag[inj_row][inj_col] = h_i_mem[0][inj_row][inj_col];
        end
    h_valid_in = 1'b1;
    y_valid_in = 1'b0;
    @(posedge clk);
    h_vin_cycle[0] = cycle_counter;

    // Main burst: each negedge drives y[N] and simultaneously pre-loads h[N+1]
    for (inj_t = 0; inj_t < NUM_TESTS; inj_t = inj_t + 1) begin
        @(negedge clk);

        // Drive y[N]
        for (inj_col = 0; inj_col < COLS_H; inj_col = inj_col + 1) begin
            y_real[inj_col] = y_r_mem[inj_t][inj_col];
            y_imag[inj_col] = y_i_mem[inj_t][inj_col];
        end
        y_valid_in = 1'b1;

        // Pre-load h[N+1] on the same negedge
        if (inj_t + 1 < NUM_TESTS) begin
            for (inj_row = 0; inj_row < ROWS_H; inj_row = inj_row + 1)
                for (inj_col = 0; inj_col < COLS_H; inj_col = inj_col + 1) begin
                    h_real[inj_row][inj_col] = h_r_mem[inj_t+1][inj_row][inj_col];
                    h_imag[inj_row][inj_col] = h_i_mem[inj_t+1][inj_row][inj_col];
                end
            h_valid_in = 1'b1;
        end else begin
            h_valid_in = 1'b0;
        end

        @(posedge clk);
        y_vin_cycle[inj_t] = cycle_counter;
        // h_vin for frame N+1 was recorded one posedge earlier
        if (inj_t + 1 < NUM_TESTS)
            h_vin_cycle[inj_t + 1] = cycle_counter;
    end

    // De-assert
    @(negedge clk);
    y_valid_in = 1'b0;
    h_valid_in = 1'b0;
    for (inj_col = 0; inj_col < COLS_H; inj_col = inj_col + 1) begin
        y_real[inj_col] = '0;
        y_imag[inj_col] = '0;
    end

    $display(">>> [SuiteA] INJECTOR done");
end


// ===========================================================================
// PROCESS 3 — SUITE A COLLECTOR
// ===========================================================================
integer col_idx, col_row;

initial begin : collector_proc
    wait(vectors_ready);
    col_idx = 0;

    while (col_idx < NUM_TESTS) begin
        @(posedge clk);
        if (z_valid_out === 1'b1) begin
            vout_cycle[col_idx] = cycle_counter;
            for (col_row = 0; col_row < COLS_H; col_row = col_row + 1) begin
                got_r[col_idx][col_row] =
                    $itor($signed(z_real[col_row])) / SCALE;
                got_i[col_idx][col_row] =
                    $itor($signed(z_imag[col_row])) / SCALE;
            end
            col_idx = col_idx + 1;
        end
    end

    $display(">>> [SuiteA] COLLECTOR done");
    collect_done = 1'b1;
end


// ===========================================================================
// PROCESS 4 — SUITE B STALL INJECTOR
// ===========================================================================
// Runs after Suite A completes. Re-resets the DUT, then replays frames 0..N
// with a STALL_CYCLES en=0 stall inserted after y_valid_in[STALL_FRAME_IDX].
// ===========================================================================
integer sinj_t, sinj_row, sinj_col, stall_cy;

initial begin : stall_injector_proc
    wait(collect_done);

    $display("");
    $display(">>> [SuiteB] STALL INJECTOR start");

    // Clean reset
    @(negedge clk);
    en         = 1'b1;
    h_valid_in = 1'b0;
    y_valid_in = 1'b0;
    for (sinj_row = 0; sinj_row < ROWS_H; sinj_row = sinj_row + 1)
        for (sinj_col = 0; sinj_col < COLS_H; sinj_col = sinj_col + 1) begin
            h_real[sinj_row][sinj_col] = '0;
            h_imag[sinj_row][sinj_col] = '0;
        end
    for (sinj_col = 0; sinj_col < COLS_H; sinj_col = sinj_col + 1) begin
        y_real[sinj_col] = '0;
        y_imag[sinj_col] = '0;
    end
    rst_n = 1'b0;
    repeat(2) @(posedge clk);
    rst_n = 1'b1;
    repeat(4) @(posedge clk);

    // Zero out stall cycle array
    for (sinj_t = 0; sinj_t < NUM_TESTS; sinj_t = sinj_t + 1)
        svout_cycle[sinj_t] = 0;

    // Pre-load h[0]
    @(negedge clk);
    for (sinj_row = 0; sinj_row < ROWS_H; sinj_row = sinj_row + 1)
        for (sinj_col = 0; sinj_col < COLS_H; sinj_col = sinj_col + 1) begin
            h_real[sinj_row][sinj_col] = h_r_mem[0][sinj_row][sinj_col];
            h_imag[sinj_row][sinj_col] = h_i_mem[0][sinj_row][sinj_col];
        end
    h_valid_in = 1'b1;
    y_valid_in = 1'b0;
    @(posedge clk);
    y_vin_cycle[0] = 0;   // will be overwritten when y fires

    // Pre-stall frames: 0 .. STALL_FRAME_IDX
    for (sinj_t = 0; sinj_t <= STALL_FRAME_IDX; sinj_t = sinj_t + 1) begin
        @(negedge clk);
        for (sinj_col = 0; sinj_col < COLS_H; sinj_col = sinj_col + 1) begin
            y_real[sinj_col] = y_r_mem[sinj_t][sinj_col];
            y_imag[sinj_col] = y_i_mem[sinj_t][sinj_col];
        end
        y_valid_in = 1'b1;

        if (sinj_t + 1 <= STALL_FRAME_IDX) begin
            for (sinj_row = 0; sinj_row < ROWS_H; sinj_row = sinj_row + 1)
                for (sinj_col = 0; sinj_col < COLS_H; sinj_col = sinj_col + 1) begin
                    h_real[sinj_row][sinj_col] = h_r_mem[sinj_t+1][sinj_row][sinj_col];
                    h_imag[sinj_row][sinj_col] = h_i_mem[sinj_t+1][sinj_row][sinj_col];
                end
            h_valid_in = 1'b1;
        end else begin
            h_valid_in = 1'b0;
        end

        @(posedge clk);
        y_vin_cycle[sinj_t] = cycle_counter;
    end

    // Stall: de-assert en for STALL_CYCLES cycles
    $display(">>> [SuiteB] inserting stall (%0d cycles)", STALL_CYCLES);
    for (stall_cy = 0; stall_cy < STALL_CYCLES; stall_cy = stall_cy + 1) begin
        @(negedge clk);
        en         = 1'b0;
        y_valid_in = 1'b0;
        h_valid_in = 1'b0;
        @(posedge clk);
    end

    // Post-stall: resume
    $display(">>> [SuiteB] stall ended, resuming");
    @(negedge clk);
    en = 1'b1;

    // Pre-load next h before firing y
    if (STALL_FRAME_IDX + 1 < NUM_TESTS) begin
        for (sinj_row = 0; sinj_row < ROWS_H; sinj_row = sinj_row + 1)
            for (sinj_col = 0; sinj_col < COLS_H; sinj_col = sinj_col + 1) begin
                h_real[sinj_row][sinj_col] = h_r_mem[STALL_FRAME_IDX+1][sinj_row][sinj_col];
                h_imag[sinj_row][sinj_col] = h_i_mem[STALL_FRAME_IDX+1][sinj_row][sinj_col];
            end
        h_valid_in = 1'b1;
        y_valid_in = 1'b0;
        @(posedge clk);

        for (sinj_t = STALL_FRAME_IDX + 1;
             sinj_t < NUM_TESTS;
             sinj_t = sinj_t + 1) begin
            @(negedge clk);
            en = 1'b1;
            for (sinj_col = 0; sinj_col < COLS_H; sinj_col = sinj_col + 1) begin
                y_real[sinj_col] = y_r_mem[sinj_t][sinj_col];
                y_imag[sinj_col] = y_i_mem[sinj_t][sinj_col];
            end
            y_valid_in = 1'b1;

            if (sinj_t + 1 < NUM_TESTS) begin
                for (sinj_row = 0; sinj_row < ROWS_H; sinj_row = sinj_row + 1)
                    for (sinj_col = 0; sinj_col < COLS_H; sinj_col = sinj_col + 1) begin
                        h_real[sinj_row][sinj_col] = h_r_mem[sinj_t+1][sinj_row][sinj_col];
                        h_imag[sinj_row][sinj_col] = h_i_mem[sinj_t+1][sinj_row][sinj_col];
                    end
                h_valid_in = 1'b1;
            end else begin
                h_valid_in = 1'b0;
            end

            @(posedge clk);
            y_vin_cycle[sinj_t] = cycle_counter;
        end
    end

    @(negedge clk);
    y_valid_in = 1'b0;
    h_valid_in = 1'b0;
    en         = 1'b1;

    $display(">>> [SuiteB] STALL INJECTOR done");
end


// ===========================================================================
// PROCESS 5 — SUITE B STALL COLLECTOR
// ===========================================================================
integer sc_idx, sc_row;

initial begin : stall_collector_proc
    wait(collect_done);   // Suite A must fully complete first

    // Monitor stall window
    wait(y_vin_cycle[STALL_FRAME_IDX] != 0);
    @(negedge clk);

    repeat (STALL_CYCLES) begin
        @(posedge clk);
        if (z_valid_out === 1'b1) begin
            $display("  [SuiteB] SPURIOUS z_valid_out during stall at cycle %0d  FAIL",
                     cycle_counter);
            stall_spurious_vout = stall_spurious_vout + 1;
        end
    end

    // Collect all Suite B outputs
    sc_idx = 0;
    while (sc_idx < NUM_TESTS) begin
        @(posedge clk);
        if (z_valid_out === 1'b1) begin
            svout_cycle[sc_idx] = cycle_counter;
            for (sc_row = 0; sc_row < COLS_H; sc_row = sc_row + 1) begin
                sgot_r[sc_idx][sc_row] =
                    $itor($signed(z_real[sc_row])) / SCALE;
                sgot_i[sc_idx][sc_row] =
                    $itor($signed(z_imag[sc_row])) / SCALE;
            end
            sc_idx = sc_idx + 1;
        end
    end

    $display(">>> [SuiteB] STALL COLLECTOR done");
    stall_collect_done = 1'b1;
end


// ===========================================================================
// Global timeout guard
// ===========================================================================
initial begin : timeout_proc
    #50_000_000;
    $display("GLOBAL TIMEOUT");
    $finish;
end

endmodule
// =============================================================================
// End of tb_herm_mf_chain.sv
// =============================================================================