// =============================================================================
// tb_matched_filter_pipe.sv
// -----------------------------------------------------------------------------
// Extended testbench for matched_filter_pipe.
//
// TEST SUITES
// -----------
// Suite A – Back-to-back golden burst  (original test, preserved verbatim)
//   Three concurrent processes: MAIN / INJECTOR / COLLECTOR.
//   Fires NUM_TESTS back-to-back valid_in pulses, compares every output
//   element against MATLAB-generated golden vectors.  en held high throughout.
//
// Suite B – Pipeline-enable (en) stall test  (new)
//   Validates that asserting en=0 mid-burst:
//     1. Freezes all pipeline stages simultaneously (no output while stalled).
//     2. Resumes correctly after en is re-asserted; every output matches the
//        same golden result it would have produced without the stall.
//     3. Latency for in-flight frames is extended by exactly STALL_CYCLES.
//     4. hh_load fires during the stall window and updates coef_real/coef_imag
//        even while en=0 (CHECK 4, verified directly via hierarchical
//        reference to dut.coef_real/coef_imag).
//     5. A coefficient load registered one cycle ahead of valid_in is
//        correctly used by that frame (CHECK 5, the normal hh_load timing
//        constraint, exercised with "sentinel" coefficient/y values chosen
//        so the expected output is a simple analytical constant).
//
// HOW Suite B WORKS
// -----------------
// A separate injector (stall_injector_proc) drives a burst of STALL_TESTS
// frames.  After frame STALL_FRAME_IDX has been accepted (i.e. on the
// negedge after its posedge), en is de-asserted for STALL_CYCLES cycles.
// During that window hh_load is pulsed once with a "sentinel" coefficient
// set; CHECK 4 reads the coefficient registers directly right after the
// stall to confirm the load took effect. The coefficient bank holds only
// ONE set at a time, so this sentinel set is then overwritten by the normal
// overlap scheme for post-stall frames -- CHECK 5 separately re-loads the
// sentinel set one cycle ahead of the dedicated sentinel frame (index
// STALL_TESTS-1) to verify it is correctly used.
//
// A separate collector (stall_collector_proc) captures every valid_out
// independently of Suite A.
//
// TIMING MODEL FOR en STALL
// -------------------------
//   Cycle  C  : valid_in[STALL_FRAME_IDX] accepted at posedge; en still 1.
//   Cycle C+1 (negedge): en deasserted.
//   Cycles C+1 … C+STALL_CYCLES: pipeline frozen; valid_out must stay 0
//                                  (assuming no output was already in-flight
//                                  before the stall; checked separately).
//   Cycle C+STALL_CYCLES+1 (negedge): en reasserted; also drive next y + hh_load.
//   Cycle C+STALL_CYCLES+1 (posedge): pipeline resumes.
//
// EXPECTED LATENCY WITH STALL
// ---------------------------
//   Frames 0 … STALL_FRAME_IDX-1: received before stall.  If PIPE_LAT >
//     remaining pipeline depth at stall time, their outputs are delayed by
//     exactly STALL_CYCLES cycles compared to the unstalled case.
//   Frames after the stall: normal PIPE_LAT latency from their own vin_cycle.
//
// IMPORTANT: hh_load is NOT gated by en (by design). CHECK 4 verifies this
// directly via the coefficient registers.
//
// en-STALL valid_out GUARD
// ------------------------
// stall_collector_proc waits on the stall_window_active flag (driven by the
// injector for exactly the STALL_CYCLES en=0 posedges), then checks every
// posedge in that window; any spurious valid_out is flagged as a FAIL
// immediately.
// =============================================================================

`timescale 1ns/1ps

module tb_matched_filter_pipe;

// ---------------------------------------------------------------------------
// Testbench parameters — must match DUT defaults
// ---------------------------------------------------------------------------
localparam int ROWS      = 8;
localparam int COLS      = 8;

localparam int WL_IN         = 12;
localparam int INT_BITS_IN   =  0;
localparam int FRAC_BITS_IN  = 11;
localparam int WL_INT        = 16;
localparam int INT_BITS_INT  =  0;
localparam int FRAC_BITS_INT = 15;
localparam int WL_OUT        = 16;
localparam int INT_BITS_OUT  =  4;
localparam int FRAC_BITS_OUT = 11;

// Pipeline latency: 1 (multiply) + $clog2(COLS) (round+tree) = 1+3 = 4
localparam int LEVELS   = $clog2(COLS);   // 3 for COLS=8
localparam int PIPE_LAT = 1 + LEVELS;     // 4 for COLS=8

// Suite A: golden back-to-back burst
localparam int NUM_TESTS = 20;

// Suite B: stall test
localparam int STALL_TESTS     = 8;    // total frames in stall burst
// STALL_FRAME_IDX must satisfy STALL_FRAME_IDX < PIPE_LAT - 1 so that no
// frame has exited the pipeline when the stall fires and Check 1 is clean.
// With PIPE_LAT=4: idx=2 puts frame 0 on the boundary (exits on the exact
// posedge the stall opens); idx=1 gives a 2-cycle margin.
localparam int STALL_FRAME_IDX = 1;    // insert stall AFTER this frame is accepted
localparam int STALL_CYCLES    = 3;    // number of cycles en=0

// Output scaling: SCALE = 2^FRAC_BITS_OUT, TOL = half LSB
localparam real SCALE = 2.0 ** FRAC_BITS_OUT;   // 2048.0
localparam real TOL   = 0.5 / SCALE;             // 0.000244...

// ---------------------------------------------------------------------------
// Clock and global cycle counter
// ---------------------------------------------------------------------------
logic clk;
initial clk = 0;
always #5 clk = ~clk;

logic   rst_n, en;
integer cycle_counter;

always @(posedge clk or negedge rst_n)
    if (!rst_n) cycle_counter <= 0;
    else        cycle_counter <= cycle_counter + 1;

// ---------------------------------------------------------------------------
// DUT ports
// ---------------------------------------------------------------------------
logic                      hh_load;
logic signed [WL_IN-1:0]  hh_real [0:ROWS-1][0:COLS-1];
logic signed [WL_IN-1:0]  hh_imag [0:ROWS-1][0:COLS-1];
logic                      valid_in;
logic signed [WL_IN-1:0]  y_real  [0:COLS-1];
logic signed [WL_IN-1:0]  y_imag  [0:COLS-1];

logic                      valid_out;
logic signed [WL_OUT-1:0] yhat_real [0:ROWS-1];
logic signed [WL_OUT-1:0] yhat_imag [0:ROWS-1];

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
matched_filter_pipe #(
    .ROWS         (ROWS        ),
    .COLS         (COLS        ),
    .WL_IN        (WL_IN       ),
    .INT_BITS_IN  (INT_BITS_IN ),
    .FRAC_BITS_IN (FRAC_BITS_IN),
    .WL_INT       (WL_INT      ),
    .INT_BITS_INT (INT_BITS_INT ),
    .FRAC_BITS_INT(FRAC_BITS_INT),
    .WL_OUT       (WL_OUT      ),
    .INT_BITS_OUT (INT_BITS_OUT ),
    .FRAC_BITS_OUT(FRAC_BITS_OUT)
) dut (
    .clk      (clk      ),
    .rst_n    (rst_n    ),
    .en       (en       ),
    .hh_load  (hh_load  ),
    .hh_real  (hh_real  ),
    .hh_imag  (hh_imag  ),
    .valid_in (valid_in ),
    .y_real   (y_real   ),
    .y_imag   (y_imag   ),
    .valid_out(valid_out),
    .yhat_real(yhat_real),
    .yhat_imag(yhat_imag)
);

// ---------------------------------------------------------------------------
// Suite A shared memory: test vectors and captured outputs
// ---------------------------------------------------------------------------
integer hh_r_mem [0:NUM_TESTS-1][0:ROWS-1][0:COLS-1];
integer hh_i_mem [0:NUM_TESTS-1][0:ROWS-1][0:COLS-1];
integer y_r_mem  [0:NUM_TESTS-1][0:COLS-1];
integer y_i_mem  [0:NUM_TESTS-1][0:COLS-1];
integer z_r_gold [0:NUM_TESTS-1][0:ROWS-1];
integer z_i_gold [0:NUM_TESTS-1][0:ROWS-1];

integer vin_cycle  [0:NUM_TESTS+STALL_TESTS-1];   // [0..19] Suite A, [20..27] Suite B
integer vout_cycle [0:NUM_TESTS+STALL_TESTS-1];   // same layout

real    got_r [0:NUM_TESTS-1][0:ROWS-1];
real    got_i [0:NUM_TESTS-1][0:ROWS-1];

// Suite A inter-process synchronisation
logic vectors_ready;
logic collect_done;

// ---------------------------------------------------------------------------
// Suite B shared memory
// ---------------------------------------------------------------------------
// Coefficients and y vectors re-use hh_r_mem[0..STALL_TESTS-1] and
// y_r_mem[0..STALL_TESTS-1] already loaded by MAIN.
// Golden outputs for Suite B also reuse z_r_gold[0..STALL_TESTS-1].
//
// Sentinel coefficient set: all elements set to a known non-zero constant so
// that the output for the sentinel frame is numerically distinct from the
// other frames.  This lets us confirm hh_load fired during the stall and that
// the post-stall frame actually used the updated coefficients.
//
// The sentinel coef value is chosen as 12'sh200 (0.25 in Q0.11), a value
// that is unlikely to coincide with any random vector's coefficient.
localparam logic signed [WL_IN-1:0] SENTINEL_COEF = 12'sh200;
localparam logic signed [WL_IN-1:0] SENTINEL_Y    = 12'sh100;  // 0.125 in Q0.11

// Widened (internal-format) sentinel coefficient, computed with the exact
// same sign-extend + zero-pad formula the DUT uses for hh_real/hh_imag
// (Part 3). Used by CHECK 4 to verify the coefficient registers directly
// via hierarchical reference right after hh_load fires during the stall.
localparam int FRAC_WIDEN_TB = FRAC_BITS_INT - FRAC_BITS_IN;          // 4 default
localparam logic signed [WL_INT-1:0] SENTINEL_COEF_W = signed'(
    {{(WL_INT - WL_IN - FRAC_WIDEN_TB){SENTINEL_COEF[WL_IN-1]}},
       SENTINEL_COEF,
     {FRAC_WIDEN_TB{1'b0}}});

// Captured stall-test outputs
integer svout_cycle [0:STALL_TESTS-1];  // vout cycle for each stall-burst frame
real    sgot_r      [0:STALL_TESTS-1][0:ROWS-1];
real    sgot_i      [0:STALL_TESTS-1][0:ROWS-1];

// Stall-test sentinel golden values (computed analytically below)
real    sentinel_gold_r [0:ROWS-1];
real    sentinel_gold_i [0:ROWS-1];

// Stall-test inter-process synchronisation
logic stall_vectors_ready;
logic stall_collect_done;
logic stall_window_active;   // driven 1 by injector for exactly the en=0 window
integer stall_spurious_vout; // count of valid_out pulses seen during stall window

// CHECK 4 (direct coef-register check) results, filled in by stall_injector_proc
integer check4a_pass, check4a_fail;


// ===========================================================================
// PROCESS 1 — MAIN
// ===========================================================================
integer fid_hh_real, fid_hh_imag, fid_y_real, fid_y_imag,
        fid_z_real,  fid_z_imag;
integer t, row, col_idx_main, r, tmp, status;
integer pass_cnt, fail_cnt, lat_min, lat_max, lat_sum, lat_count;
real    exp_r, exp_i, err_r, err_i;

initial begin : main_proc

    // -----------------------------------------------------------------------
    // Initialise inter-process flags
    // -----------------------------------------------------------------------
    vectors_ready       = 1'b0;
    collect_done        = 1'b0;
    stall_vectors_ready = 1'b0;
    stall_collect_done  = 1'b0;
    stall_window_active = 1'b0;
    stall_spurious_vout = 0;
    check4a_pass        = 0;
    check4a_fail        = 0;

    pass_cnt  = 0;  fail_cnt  = 0;
    lat_min   = 32767; lat_max = 0; lat_sum = 0; lat_count = 0;

    // -----------------------------------------------------------------------
    // Open MATLAB-generated vector files
    //   Layout (all integers, one per line):
    //     hh_real/imag : column-major — for each frame, values written
    //                    col-by-col (outer loop col, inner loop row).
    //                    Total: ROWS*COLS values per frame, NUM_TESTS frames.
    //     y_real/imag  : COLS values per frame, NUM_TESTS frames.
    //     z_*_golden   : ROWS values per frame, NUM_TESTS frames.
    // -----------------------------------------------------------------------
    fid_hh_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_real.txt", "r");
    fid_hh_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_imag.txt", "r");
    fid_y_real  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_real.txt",  "r");
    fid_y_imag  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_imag.txt",  "r");
    fid_z_real  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_real_golden.txt", "r");
    fid_z_imag  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_imag_golden.txt", "r");

    if (!fid_hh_real || !fid_hh_imag || !fid_y_real ||
        !fid_y_imag  || !fid_z_real  || !fid_z_imag) begin
        $display("ERROR: could not open one or more vector files");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Reset sequence: hold rst_n low for 2 clocks, then settle pipeline
    // -----------------------------------------------------------------------
    rst_n    = 1'b0;
    en       = 1'b1;
    hh_load  = 1'b0;
    valid_in = 1'b0;

    for (r = 0; r < ROWS; r = r + 1)
        for (col_idx_main = 0; col_idx_main < COLS; col_idx_main = col_idx_main + 1) begin
            hh_real[r][col_idx_main] = '0;
            hh_imag[r][col_idx_main] = '0;
        end
    for (col_idx_main = 0; col_idx_main < COLS; col_idx_main = col_idx_main + 1) begin
        y_real[col_idx_main] = '0;
        y_imag[col_idx_main] = '0;
    end

    repeat(2) @(posedge clk);
    rst_n = 1'b1;
    repeat(4) @(posedge clk);

    // -----------------------------------------------------------------------
    // Load all test vectors from files into shared memory arrays
    // -----------------------------------------------------------------------
    begin : load_vecs
        integer kk;
        for (t = 0; t < NUM_TESTS; t = t + 1) begin
            // H^H: column-major — outer loop col, inner loop row
            for (kk = 0; kk < COLS; kk = kk + 1)
                for (row = 0; row < ROWS; row = row + 1) begin
                    status = $fscanf(fid_hh_real, "%d\n", tmp);
                    hh_r_mem[t][row][kk] = tmp;
                    status = $fscanf(fid_hh_imag, "%d\n", tmp);
                    hh_i_mem[t][row][kk] = tmp;
                end
            // y vector: COLS elements
            for (kk = 0; kk < COLS; kk = kk + 1) begin
                status = $fscanf(fid_y_real, "%d\n", tmp);
                y_r_mem[t][kk] = tmp;
                status = $fscanf(fid_y_imag, "%d\n", tmp);
                y_i_mem[t][kk] = tmp;
            end
            // Golden outputs: ROWS elements
            for (row = 0; row < ROWS; row = row + 1) begin
                status = $fscanf(fid_z_real, "%d\n", tmp);
                z_r_gold[t][row] = tmp;
                status = $fscanf(fid_z_imag, "%d\n", tmp);
                z_i_gold[t][row] = tmp;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Pre-compute sentinel golden values analytically.
    //
    //   Sentinel coef:  SENTINEL_COEF for every (row,col), real part only;
    //                   imaginary coef = 0.
    //   Sentinel y:     SENTINEL_Y for every col, real part only;
    //                   imaginary y = 0.
    //
    //   With purely-real coef and y the complex multiply reduces to:
    //     real = coef_r * y_r   (all other terms zero)
    //     imag = 0
    //
    //   Each row has COLS identical terms, so:
    //     z_real[row] = COLS * (SENTINEL_COEF * SENTINEL_Y)
    //                   expressed in Q4.11 output format
    //     z_imag[row] = 0
    //
    //   In fixed-point integer counts at FRAC_BITS_OUT:
    //     coef_w = SENTINEL_COEF << FRAC_WIDEN  (widen from Q0.11 to Q0.15)
    //     y_w    = SENTINEL_Y    << FRAC_WIDEN
    //     prod   = coef_w * y_w                 (Q0.30, 32-bit)
    //     After RIGHT_SH=19 convergent-round to Q4.11 (16-bit):
    //       prod_shifted = prod >>> 19
    //     Sum = COLS * prod_shifted  (in Q4.11 integer counts)
    //   We compute this in real arithmetic and store as a fractional value
    //   (dividing by SCALE) for consistency with the comparison below.
    // -----------------------------------------------------------------------
    begin : sentinel_gold_calc
        real coef_fp, y_fp, prod_fp, sum_fp;
        integer frac_widen_lp;
        frac_widen_lp = FRAC_BITS_INT - FRAC_BITS_IN;  // 4 default

        // Convert sentinel integer coef/y values to fractional representation
        // at the widened format (Q0.15), then multiply to get Q0.30, then
        // apply convergent round and express as Q4.11 integer counts.
        //
        // Shortcut: work entirely in Q4.11 counts.
        //   coef_int15 = SENTINEL_COEF_int * 2^FRAC_WIDEN
        //   y_int15    = SENTINEL_Y_int    * 2^FRAC_WIDEN
        //   prod_int30 = coef_int15 * y_int15
        //   prod_int11 = prod_int30 >> 19  (convergent round; no tie for these
        //                                    clean power-of-two values)
        //   sum_int11  = COLS * prod_int11
        //
        // Using real arithmetic (no rounding edge cases for power-of-two inputs).
        coef_fp = $itor($signed(SENTINEL_COEF)) * (2.0 ** frac_widen_lp);
        y_fp    = $itor($signed(SENTINEL_Y))    * (2.0 ** frac_widen_lp);
        prod_fp = coef_fp * y_fp;
        // Right-shift by RIGHT_SH=19:
        sum_fp  = COLS * (prod_fp / (2.0 ** (FRAC_BITS_INT + FRAC_BITS_INT
                                             - FRAC_BITS_OUT)));  // divide by 2^19
        for (row = 0; row < ROWS; row = row + 1) begin
            sentinel_gold_r[row] = sum_fp / SCALE;
            sentinel_gold_i[row] = 0.0;
        end
    end

    // Release both injectors and both collectors simultaneously
    vectors_ready       = 1'b1;
    stall_vectors_ready = 1'b1;

    // -----------------------------------------------------------------------
    // Wait for Suite A collector to finish
    // -----------------------------------------------------------------------
    wait(collect_done);

    // =======================================================================
    // SUITE A — REPORT
    // =======================================================================
    $display("");
    $display("========================================================");
    $display(" SUITE A — BACK-TO-BACK GOLDEN BURST");
    $display(" ROWS=%0d  COLS=%0d  PIPE_LAT=%0d  NUM_TESTS=%0d",
             ROWS, COLS, PIPE_LAT, NUM_TESTS);
    $display(" Fixed-point: Q%0d.%0d input, Q%0d.%0d output",
             INT_BITS_IN, FRAC_BITS_IN, INT_BITS_OUT, FRAC_BITS_OUT);
    $display(" TOL=%.6f  (half LSB in Q%0d.%0d output)",
             TOL, INT_BITS_OUT, FRAC_BITS_OUT);
    $display("========================================================");

    // Pipeline timing table
    $display("");
    $display("  PIPELINE TIMING TABLE");
    $display("  %-6s  %-12s  %-12s  %-s",
             "Frame", "vin_cycle", "vout_cycle", "Latency");
    $display("  --------------------------------------------------------");

    for (t = 0; t < NUM_TESTS; t = t + 1) begin : timing_loop
        integer lat;
        lat = vout_cycle[t] - vin_cycle[t];
        $display("  %-6d  %-12d  %-12d  %0d cycles%s",
            t, vin_cycle[t], vout_cycle[t], lat,
            (lat == PIPE_LAT) ? "  OK" : "  *** WRONG ***");
        if (lat < lat_min) lat_min = lat;
        if (lat > lat_max) lat_max = lat;
        lat_sum   = lat_sum + lat;
        lat_count = lat_count + 1;
    end

    $display("");
    $display("  THROUGHPUT");
    $display("  First valid_in  : cycle %0d", vin_cycle[0]);
    $display("  Last valid_out  : cycle %0d", vout_cycle[NUM_TESTS-1]);
    $display("  Outputs/cycle   : %.2f  (ideal=1.00)",
        $itor(NUM_TESTS) /
        $itor(vout_cycle[NUM_TESTS-1] - vout_cycle[0] + 1));
    $display("  Input interval  : cycle %0d..%0d  (%0d cycles, %0d frames)",
        vin_cycle[0], vin_cycle[NUM_TESTS-1],
        vin_cycle[NUM_TESTS-1] - vin_cycle[0] + 1, NUM_TESTS);
    $display("  Pipeline latency: %0d cycles measured  (expected %0d)",
        vout_cycle[0] - vin_cycle[0], PIPE_LAT);

    // Functional results
    $display("");
    $display("========================================================");
    $display("  FUNCTIONAL RESULTS");
    $display("========================================================");

    for (t = 0; t < NUM_TESTS; t = t + 1) begin : func_loop
        integer lat2;
        lat2 = vout_cycle[t] - vin_cycle[t];
        $display("");
        $display("  --- Frame %0d  vin=%0d  vout=%0d  lat=%0d ---",
                 t, vin_cycle[t], vout_cycle[t], lat2);
        $display("  %-5s  %-30s  %-s", "Row", "Output (real, imag)", "Status");

        for (row = 0; row < ROWS; row = row + 1) begin
            exp_r = $itor(z_r_gold[t][row]) / SCALE;
            exp_i = $itor(z_i_gold[t][row]) / SCALE;
            err_r = got_r[t][row] - exp_r;
            err_i = got_i[t][row] - exp_i;
            if (err_r < 0.0) err_r = -err_r;
            if (err_i < 0.0) err_i = -err_i;
            if ((err_r > TOL) || (err_i > TOL)) begin
                $display("  %-5d  got(%9.6f, %9.6f)  exp(%9.6f, %9.6f)  FAIL err=(%.5f,%.5f)",
                    row, got_r[t][row], got_i[t][row],
                    exp_r, exp_i, err_r, err_i);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("  %-5d  (%9.6f, %9.6f)          PASS",
                    row, got_r[t][row], got_i[t][row]);
                pass_cnt = pass_cnt + 1;
            end
        end
    end

    $display("");
    $display("========================================================");
    $display("  SUITE A — LATENCY SUMMARY (%0d frames)", lat_count);
    $display("  Min latency  : %0d cycles", lat_min);
    $display("  Max latency  : %0d cycles", lat_max);
    $display("  Mean latency : %.2f cycles",
             $itor(lat_sum) / $itor(lat_count));
    $display("  Expected     : %0d cycles (1 + $clog2(%0d))", PIPE_LAT, COLS);
    $display("========================================================");
    $display("  SUITE A — FUNCTIONAL SUMMARY");
    $display("  PASS = %0d / %0d  rows x frames", pass_cnt, NUM_TESTS * ROWS);
    $display("  FAIL = %0d / %0d  rows x frames", fail_cnt, NUM_TESTS * ROWS);
    $display("========================================================");
    if (fail_cnt == 0) $display("  *** SUITE A ALL PASSED ***");
    else               $display("  *** SUITE A FAILURES DETECTED ***");

    // -----------------------------------------------------------------------
    // Wait for Suite B stall collector to finish
    // -----------------------------------------------------------------------
    wait(stall_collect_done);

    // =======================================================================
    // SUITE B — REPORT
    // =======================================================================
    $display("");
    $display("========================================================");
    $display(" SUITE B — PIPELINE ENABLE (en) STALL TEST");
    $display(" STALL_TESTS=%0d  STALL_FRAME_IDX=%0d  STALL_CYCLES=%0d",
             STALL_TESTS, STALL_FRAME_IDX, STALL_CYCLES);
    $display("========================================================");

    begin : suite_b_report
        integer sb_pass, sb_fail;
        integer sb_t;
        real sb_exp_r, sb_exp_i, sb_err_r, sb_err_i;

        sb_pass = 0;
        sb_fail = 0;

        // --- Check 1: no valid_out during stall window ---
        $display("");
        $display("  CHECK 1: no valid_out during stall window (%0d cycles)",
                 STALL_CYCLES);
        if (stall_spurious_vout == 0) begin
            $display("  Spurious valid_out during stall: 0  PASS");
            sb_pass = sb_pass + 1;
        end else begin
            $display("  Spurious valid_out during stall: %0d  FAIL",
                     stall_spurious_vout);
            sb_fail = sb_fail + 1;
        end

        // --- Check 2: per-frame latency ---
        //
        // Expected latency rules:
        //   Frames 0 .. STALL_FRAME_IDX   : in pipeline during stall.
        //     Their outputs are delayed by STALL_CYCLES compared to the
        //     unstalled baseline latency (PIPE_LAT).
        //     expected_lat = PIPE_LAT + STALL_CYCLES
        //
        //   Frames STALL_FRAME_IDX+1 .. STALL_TESTS-2:
        //     Injected after the stall.  Normal latency = PIPE_LAT.
        //
        //   Frame STALL_TESTS-1 (sentinel frame):
        //     Uses the SENTINEL coef set, loaded one cycle ahead of its
        //     valid_in (Phase 3's last iteration). Normal PIPE_LAT.
        //
        // Note: because the stall is inserted after STALL_FRAME_IDX's
        // valid_in posedge, STALL_FRAME_IDX+1 .. STALL_FRAME_IDX + PIPE_LAT
        // frames were also in the pipeline at stall time and therefore also
        // see +STALL_CYCLES latency, as long as they were injected before
        // the stall.  In this test only STALL_FRAME_IDX frames are injected
        // before the stall (indices 0..STALL_FRAME_IDX), so only those
        // STALL_FRAME_IDX+1 frames carry the +STALL_CYCLES penalty.
        $display("");
        $display("  CHECK 2: per-frame latency");
        $display("  %-6s  %-12s  %-12s  %-10s  %-s",
                 "Frame", "vin_cycle", "vout_cycle", "Latency", "Expected");
        $display("  -------------------------------------------------------");

        for (sb_t = 0; sb_t < STALL_TESTS; sb_t = sb_t + 1) begin : lat_check
            integer meas_lat, exp_lat;
            meas_lat = svout_cycle[sb_t] - vin_cycle[NUM_TESTS + sb_t];
            // Frames injected before stall (0..STALL_FRAME_IDX) see
            // extra STALL_CYCLES latency.
            exp_lat = (sb_t <= STALL_FRAME_IDX)
                      ? PIPE_LAT + STALL_CYCLES
                      : PIPE_LAT;
            $display("  %-6d  %-12d  %-12d  %-10d  %0d%s",
                sb_t,
                vin_cycle[NUM_TESTS + sb_t],
                svout_cycle[sb_t],
                meas_lat,
                exp_lat,
                (meas_lat == exp_lat) ? "  OK" : "  *** WRONG ***");
            if (meas_lat == exp_lat) sb_pass = sb_pass + 1;
            else                     sb_fail = sb_fail + 1;
        end

        // --- Check 3: functional correctness for non-sentinel frames ---
        $display("");
        $display("  CHECK 3: functional output (non-sentinel frames 0..%0d)",
                 STALL_TESTS - 2);
        $display("  %-5s  %-30s  %-s", "Frame.Row", "Output (real, imag)", "Status");

        for (sb_t = 0; sb_t < STALL_TESTS - 1; sb_t = sb_t + 1) begin
            for (row = 0; row < ROWS; row = row + 1) begin
                sb_exp_r = $itor(z_r_gold[sb_t][row]) / SCALE;
                sb_exp_i = $itor(z_i_gold[sb_t][row]) / SCALE;
                sb_err_r = sgot_r[sb_t][row] - sb_exp_r;
                sb_err_i = sgot_i[sb_t][row] - sb_exp_i;
                if (sb_err_r < 0.0) sb_err_r = -sb_err_r;
                if (sb_err_i < 0.0) sb_err_i = -sb_err_i;
                if ((sb_err_r > TOL) || (sb_err_i > TOL)) begin
                    $display("  %-3d.%-3d  got(%9.6f, %9.6f)  exp(%9.6f, %9.6f)  FAIL",
                        sb_t, row, sgot_r[sb_t][row], sgot_i[sb_t][row],
                        sb_exp_r, sb_exp_i);
                    sb_fail = sb_fail + 1;
                end else begin
                    sb_pass = sb_pass + 1;
                end
            end
        end

        // --- Check 4: hh_load during stall updates coef registers directly ---
        //
        // Verified by stall_injector_proc via hierarchical reference
        // (dut.coef_real / dut.coef_imag) immediately after the stall
        // window, before Phase 3's overlap scheme begins overwriting the
        // coefficient bank. Results were accumulated into check4a_pass/fail.
        $display("");
        $display("  CHECK 4: hh_load during stall (en=0) updates coef_real/coef_imag");
        $display("  (verified via dut.coef_real/coef_imag == widened SENTINEL_COEF, all %0dx%0d elements)",
                 ROWS, COLS);
        if (check4a_fail == 0) begin
            $display("  coef register check: PASS=%0d FAIL=%0d  PASS", check4a_pass, check4a_fail);
        end else begin
            $display("  coef register check: PASS=%0d FAIL=%0d  FAIL", check4a_pass, check4a_fail);
        end
        sb_pass = sb_pass + check4a_pass;
        sb_fail = sb_fail + check4a_fail;

        // --- Check 5: sentinel frame confirms a coef load is correctly used ---
        //
        // The sentinel frame (index STALL_TESTS-1) was processed using the
        // SENTINEL coef set, loaded via hh_load one cycle ahead of its
        // valid_in during Phase 3's last iteration (the normal hh_load
        // timing constraint, exercised with sentinel values for an easy
        // analytical golden). Its output must match sentinel_gold.
        $display("");
        $display("  CHECK 5: sentinel frame (index %0d) -- coef load one cycle ahead of valid_in",
                 STALL_TESTS - 1);
        $display("  (coef: all rows/cols = SENTINEL_COEF=%0d, y: all cols = SENTINEL_Y=%0d)",
                 $signed(SENTINEL_COEF), $signed(SENTINEL_Y));
        $display("  %-5s  %-30s  %-s", "Row", "Output (real, imag)", "Status");

        begin : sentinel_check
            integer sent_idx;
            sent_idx = STALL_TESTS - 1;
            for (row = 0; row < ROWS; row = row + 1) begin
                sb_err_r = sgot_r[sent_idx][row] - sentinel_gold_r[row];
                sb_err_i = sgot_i[sent_idx][row] - sentinel_gold_i[row];
                if (sb_err_r < 0.0) sb_err_r = -sb_err_r;
                if (sb_err_i < 0.0) sb_err_i = -sb_err_i;
                if ((sb_err_r > TOL) || (sb_err_i > TOL)) begin
                    $display("  %-5d  got(%9.6f, %9.6f)  exp(%9.6f, %9.6f)  FAIL err=(%.5f,%.5f)",
                        row, sgot_r[sent_idx][row], sgot_i[sent_idx][row],
                        sentinel_gold_r[row], sentinel_gold_i[row],
                        sb_err_r, sb_err_i);
                    sb_fail = sb_fail + 1;
                end else begin
                    $display("  %-5d  (%9.6f, %9.6f)          PASS",
                        row, sgot_r[sent_idx][row], sgot_i[sent_idx][row]);
                    sb_pass = sb_pass + 1;
                end
            end
        end

        $display("");
        $display("========================================================");
        $display("  SUITE B — SUMMARY");
        $display("  PASS = %0d", sb_pass);
        $display("  FAIL = %0d", sb_fail);
        $display("========================================================");
        if (sb_fail == 0) $display("  *** SUITE B ALL PASSED ***");
        else              $display("  *** SUITE B FAILURES DETECTED ***");

        fail_cnt = fail_cnt + sb_fail;
    end

    // =======================================================================
    // GLOBAL SUMMARY
    // =======================================================================
    $display("");
    $display("========================================================");
    $display("  GLOBAL SUMMARY (Suite A + Suite B)");
    $display("  PASS = %0d", pass_cnt);
    $display("  FAIL = %0d", fail_cnt);
    $display("========================================================");
    if (fail_cnt == 0) $display("  *** ALL TESTS PASSED ***");
    else               $display("  *** SOME TESTS FAILED ***");
    $display("========================================================");

    $fclose(fid_hh_real); $fclose(fid_hh_imag);
    $fclose(fid_y_real);  $fclose(fid_y_imag);
    $fclose(fid_z_real);  $fclose(fid_z_imag);
    $finish;
end


// ===========================================================================
// PROCESS 2 — SUITE A INJECTOR  (back-to-back golden burst, en=1 throughout)
// ===========================================================================
integer inj_test, inj_row, inj_col;

initial begin : injector_proc
    wait(vectors_ready);

    $display(">>> [SuiteA] INJECTOR start  (pre-load frame 0 H^H)");

    // Pre-load cycle: register frame 0 coefs, no valid_in
    @(negedge clk);
    for (inj_row = 0; inj_row < ROWS; inj_row = inj_row + 1)
        for (inj_col = 0; inj_col < COLS; inj_col = inj_col + 1) begin
            hh_real[inj_row][inj_col] = hh_r_mem[0][inj_row][inj_col];
            hh_imag[inj_row][inj_col] = hh_i_mem[0][inj_row][inj_col];
        end
    hh_load  = 1'b1;
    valid_in = 1'b0;
    @(posedge clk);   // coefs[0] now registered

    $display(">>> [SuiteA] INJECTOR firing %0d frames...", NUM_TESTS);
    $display("");
    $display("  %-6s  %-12s  %-s",
             "Frame", "vin_cycle", "Pipeline occupancy");
    $display("  -------------------------------------------------------");

    for (inj_test = 0; inj_test < NUM_TESTS; inj_test = inj_test + 1) begin
        @(negedge clk);

        // Drive y for this frame
        for (inj_col = 0; inj_col < COLS; inj_col = inj_col + 1) begin
            y_real[inj_col] = y_r_mem[inj_test][inj_col];
            y_imag[inj_col] = y_i_mem[inj_test][inj_col];
        end
        valid_in = 1'b1;

        // Overlap: pre-load next frame's coefs on the same negedge
        if (inj_test + 1 < NUM_TESTS) begin
            for (inj_row = 0; inj_row < ROWS; inj_row = inj_row + 1)
                for (inj_col = 0; inj_col < COLS; inj_col = inj_col + 1) begin
                    hh_real[inj_row][inj_col] = hh_r_mem[inj_test+1][inj_row][inj_col];
                    hh_imag[inj_row][inj_col] = hh_i_mem[inj_test+1][inj_row][inj_col];
                end
            hh_load = 1'b1;
        end else begin
            hh_load = 1'b0;
        end

        @(posedge clk);
        vin_cycle[inj_test] = cycle_counter;

        begin : fill_disp
            integer stage, sf;
            sf = (inj_test + 1 < PIPE_LAT) ? (inj_test + 1) : PIPE_LAT;
            $write("  %-6d  %-12d  [", inj_test, vin_cycle[inj_test]);
            for (stage = 0; stage < PIPE_LAT; stage = stage + 1) begin
                $write("%s", (stage < sf) ? "##" : "  ");
                if (stage < PIPE_LAT - 1) $write("|");
            end
            if (inj_test + 1 >= PIPE_LAT)
                $display("]  PIPELINE FULL - 1 output/cycle");
            else
                $display("]  filling (%0d/%0d)", sf, PIPE_LAT);
        end
    end

    // De-assert after last frame
    @(negedge clk);
    valid_in = 1'b0;
    hh_load  = 1'b0;
    for (inj_col = 0; inj_col < COLS; inj_col = inj_col + 1) begin
        y_real[inj_col] = '0;
        y_imag[inj_col] = '0;
    end

    $display("");
    $display(">>> [SuiteA] INJECTOR done. vin[0]=%0d  vin[%0d]=%0d",
             vin_cycle[0], NUM_TESTS-1, vin_cycle[NUM_TESTS-1]);
end


// ===========================================================================
// PROCESS 3 — SUITE A COLLECTOR  (concurrent with Suite A injector)
// ===========================================================================
integer col_idx, col_row;

initial begin : collector_proc
    wait(vectors_ready);

    col_idx = 0;

    while (col_idx < NUM_TESTS) begin
        @(posedge clk);
        if (valid_out === 1'b1) begin
            vout_cycle[col_idx] = cycle_counter;
            for (col_row = 0; col_row < ROWS; col_row = col_row + 1) begin
                got_r[col_idx][col_row] =
                    $itor($signed(yhat_real[col_row])) / SCALE;
                got_i[col_idx][col_row] =
                    $itor($signed(yhat_imag[col_row])) / SCALE;
            end
            col_idx = col_idx + 1;
        end
    end

    $display(">>> [SuiteA] COLLECTOR done. vout[0]=%0d  vout[%0d]=%0d",
             vout_cycle[0], NUM_TESTS-1, vout_cycle[NUM_TESTS-1]);
    collect_done = 1'b1;
end


// ===========================================================================
// PROCESS 4 — SUITE B STALL INJECTOR
// ===========================================================================
// Strategy
// --------
//  Phase 1 – Pre-stall frames (indices 0 .. STALL_FRAME_IDX):
//    Same overlap scheme as Suite A.  en=1 throughout.
//    After the last pre-stall frame's posedge, drop en on the next negedge.
//
//  Phase 2 – Stall window (STALL_CYCLES cycles with en=0):
//    Hold valid_in=0, en=0.
//    On the FIRST negedge of the stall, assert hh_load with the SENTINEL
//    coef set.  This verifies that hh_load is not gated by en.
//    On subsequent stall negedges, deassert hh_load.
//    Immediately after the stall window, CHECK 4 reads coef_real/coef_imag
//    directly via hierarchical reference and confirms they equal the
//    widened SENTINEL_COEF -- this proves hh_load took effect during en=0,
//    independent of anything downstream.
//
//  Phase 3 – Post-stall frames (indices STALL_FRAME_IDX+1 .. STALL_TESTS-2):
//    Re-assert en.  Use hh_r_mem/y_r_mem just like Suite A.
//    Same overlap scheme; each frame uses coefs from the previous cycle's
//    hh_load.  The coefficient bank only holds ONE set at a time, so the
//    sentinel set loaded in Phase 2 is necessarily overwritten by this
//    overlap scheme -- CHECK 4 above is what verifies the stall-time load,
//    not persistence through Phase 3.
//
//  Phase 4 – Sentinel frame (index STALL_TESTS-1):
//    On the LAST iteration of the Phase 3 loop (sinj_test == STALL_TESTS-2,
//    i.e. frame 6's cycle), instead of overlap-loading frame 7's coefs (frame
//    7 doesn't exist in hh_r_mem), load the SENTINEL coef set via hh_load.
//    This is registered one cycle ahead of the sentinel frame's valid_in --
//    exactly the documented hh_load timing constraint -- so the sentinel
//    frame uses SENTINEL_COEF with SENTINEL_Y, giving the easily-verified
//    analytical golden result computed in sentinel_gold_calc.
//
// vin_cycle for stall frames is stored in vin_cycle[NUM_TESTS .. NUM_TESTS+STALL_TESTS-1]
// to keep Suite A's vin_cycle array intact.
// ===========================================================================
integer sinj_test, sinj_row, sinj_col, stall_cy;

initial begin : stall_injector_proc
    wait(stall_vectors_ready);

    // Wait until Suite A injector has fully released the DUT ports
    // (Suite A injector deasserts valid_in and hh_load after its last frame).
    // We wait for collect_done as a proxy: by that point, Suite A injector
    // finished driving at least PIPE_LAT cycles ago.
    wait(collect_done);

    $display("");
    $display(">>> [SuiteB] STALL INJECTOR start");
    $display("    Stall after frame %0d, for %0d cycles, then sentinel frame",
             STALL_FRAME_IDX, STALL_CYCLES);

    // Reset the DUT cleanly before Suite B
    @(negedge clk);
    en       = 1'b1;
    valid_in = 1'b0;
    hh_load  = 1'b0;
    for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
        y_real[sinj_col] = '0;
        y_imag[sinj_col] = '0;
    end
    for (sinj_row = 0; sinj_row < ROWS; sinj_row = sinj_row + 1)
        for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
            hh_real[sinj_row][sinj_col] = '0;
            hh_imag[sinj_row][sinj_col] = '0;
        end

    // Assert rst_n briefly to flush any residual state from Suite A
    rst_n = 1'b0;
    repeat(2) @(posedge clk);
    rst_n = 1'b1;
    repeat(4) @(posedge clk);

    // ------------------------------------------------------------------
    // Phase 1: pre-stall frames 0 .. STALL_FRAME_IDX
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] Phase 1: pre-loading frame 0 coefs");

    // Pre-load frame 0 coefs (same pattern as Suite A)
    @(negedge clk);
    for (sinj_row = 0; sinj_row < ROWS; sinj_row = sinj_row + 1)
        for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
            hh_real[sinj_row][sinj_col] = hh_r_mem[0][sinj_row][sinj_col];
            hh_imag[sinj_row][sinj_col] = hh_i_mem[0][sinj_row][sinj_col];
        end
    hh_load  = 1'b1;
    valid_in = 1'b0;
    en       = 1'b1;
    @(posedge clk);

    $display(">>> [SuiteB] Phase 1: firing %0d pre-stall frames",
             STALL_FRAME_IDX + 1);

    for (sinj_test = 0; sinj_test <= STALL_FRAME_IDX; sinj_test = sinj_test + 1) begin
        @(negedge clk);

        for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
            y_real[sinj_col] = y_r_mem[sinj_test][sinj_col];
            y_imag[sinj_col] = y_i_mem[sinj_test][sinj_col];
        end
        valid_in = 1'b1;
        en       = 1'b1;

        // Overlap next coef — but only up to STALL_FRAME_IDX-1; on the last
        // pre-stall frame we do NOT pre-load the next coef here; the sentinel
        // coef is loaded during the stall instead.
        if (sinj_test + 1 <= STALL_FRAME_IDX) begin
            for (sinj_row = 0; sinj_row < ROWS; sinj_row = sinj_row + 1)
                for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
                    hh_real[sinj_row][sinj_col] = hh_r_mem[sinj_test+1][sinj_row][sinj_col];
                    hh_imag[sinj_row][sinj_col] = hh_i_mem[sinj_test+1][sinj_row][sinj_col];
                end
            hh_load = 1'b1;
        end else begin
            // Last pre-stall frame: drop hh_load; sentinel coef comes during stall
            hh_load = 1'b0;
        end

        @(posedge clk);
        vin_cycle[NUM_TESTS + sinj_test] = cycle_counter;
        $display("    [SuiteB] pre-stall frame %0d  vin=%0d",
                 sinj_test, vin_cycle[NUM_TESTS + sinj_test]);
    end

    // ------------------------------------------------------------------
    // Phase 2: stall window — de-assert en for STALL_CYCLES cycles.
    //   On the FIRST negedge load the sentinel coef via hh_load.
    //   This is the key check: hh_load must work regardless of en.
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] Phase 2: asserting stall (en=0) for %0d cycles",
             STALL_CYCLES);
    $display("    Loading SENTINEL coef via hh_load during stall");

    stall_window_active = 1'b1;

    for (stall_cy = 0; stall_cy < STALL_CYCLES; stall_cy = stall_cy + 1) begin
        @(negedge clk);
        en       = 1'b0;     // pipeline frozen
        valid_in = 1'b0;

        if (stall_cy == 0) begin
            // Load sentinel coefs on the first stall cycle
            for (sinj_row = 0; sinj_row < ROWS; sinj_row = sinj_row + 1)
                for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
                    hh_real[sinj_row][sinj_col] = SENTINEL_COEF;
                    hh_imag[sinj_row][sinj_col] = '0;
                end
            hh_load = 1'b1;
            $display("    [SuiteB] stall cycle %0d: hh_load=1 (sentinel coef)",
                     stall_cy);
        end else begin
            hh_load = 1'b0;
            $display("    [SuiteB] stall cycle %0d: en=0 valid_out must be 0",
                     stall_cy);
        end
        @(posedge clk);
        // stall_collector_proc monitors valid_out during this window
    end

    stall_window_active = 1'b0;

    // ------------------------------------------------------------------
    // CHECK 4: directly verify the coefficient registers via hierarchical
    // reference. hh_load fired during stall_cy==0 (en=0); coef_real/imag
    // should now hold the widened SENTINEL_COEF / 0 for every (row,col).
    // hh_load has been 0 since, so these values are still stable here,
    // one cycle before Phase 3's overlap scheme begins overwriting them.
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] CHECK 4: verifying coef_real/coef_imag == SENTINEL_COEF_W via dut.coef_*");
    for (sinj_row = 0; sinj_row < ROWS; sinj_row = sinj_row + 1) begin
        for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
            if (dut.coef_real[sinj_row][sinj_col] !== SENTINEL_COEF_W ||
                dut.coef_imag[sinj_row][sinj_col] !== '0) begin
                $display("    [SuiteB] CHECK4 MISMATCH at coef[%0d][%0d]: got=(%0d,%0d) exp=(%0d,%0d)  FAIL",
                    sinj_row, sinj_col,
                    dut.coef_real[sinj_row][sinj_col], dut.coef_imag[sinj_row][sinj_col],
                    SENTINEL_COEF_W, 0);
                check4a_fail = check4a_fail + 1;
            end else begin
                check4a_pass = check4a_pass + 1;
            end
        end
    end
    $display("    [SuiteB] CHECK4 coef register check: PASS=%0d FAIL=%0d",
             check4a_pass, check4a_fail);


    // ------------------------------------------------------------------
    // Phase 3: post-stall frames STALL_FRAME_IDX+1 .. STALL_TESTS-2.
    //   Coefs for these frames come from the overlap hh_load of the
    //   previous frame (same scheme as Suite A).
    //   Re-assert en on the first post-stall negedge.
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] Phase 3: post-stall frames %0d..%0d",
             STALL_FRAME_IDX + 1, STALL_TESTS - 2);

    // Pre-load frame STALL_FRAME_IDX+1 coefs before its valid_in
    @(negedge clk);
    en       = 1'b1;
    valid_in = 1'b0;
    hh_load  = 1'b0;
    // Note: we do NOT load coefs here yet; the overlap scheme handles it
    // inside the loop below.  We need one extra pre-load before the loop.
    if (STALL_FRAME_IDX + 1 <= STALL_TESTS - 2) begin
        for (sinj_row = 0; sinj_row < ROWS; sinj_row = sinj_row + 1)
            for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
                hh_real[sinj_row][sinj_col] =
                    hh_r_mem[STALL_FRAME_IDX+1][sinj_row][sinj_col];
                hh_imag[sinj_row][sinj_col] =
                    hh_i_mem[STALL_FRAME_IDX+1][sinj_row][sinj_col];
            end
        hh_load = 1'b1;
    end
    @(posedge clk);

    for (sinj_test = STALL_FRAME_IDX + 1;
         sinj_test <= STALL_TESTS - 2;
         sinj_test = sinj_test + 1) begin

        @(negedge clk);
        en = 1'b1;

        for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
            y_real[sinj_col] = y_r_mem[sinj_test][sinj_col];
            y_imag[sinj_col] = y_i_mem[sinj_test][sinj_col];
        end
        valid_in = 1'b1;

        // Overlap next coef. For sinj_test < STALL_TESTS-2, the next frame
        // is a normal frame -- load its real coefficient set. For the last
        // iteration (sinj_test == STALL_TESTS-2, frame 6's cycle), the
        // "next frame" is the sentinel (index STALL_TESTS-1) -- load the
        // SENTINEL coef set here so it is registered one cycle ahead of the
        // sentinel frame's valid_in, per the documented hh_load timing
        // constraint.
        if (sinj_test + 1 <= STALL_TESTS - 2) begin
            for (sinj_row = 0; sinj_row < ROWS; sinj_row = sinj_row + 1)
                for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
                    hh_real[sinj_row][sinj_col] =
                        hh_r_mem[sinj_test+1][sinj_row][sinj_col];
                    hh_imag[sinj_row][sinj_col] =
                        hh_i_mem[sinj_test+1][sinj_row][sinj_col];
                end
            hh_load = 1'b1;
        end else begin
            // Last post-stall frame before the sentinel: load SENTINEL_COEF
            // for the sentinel frame's use.
            for (sinj_row = 0; sinj_row < ROWS; sinj_row = sinj_row + 1)
                for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
                    hh_real[sinj_row][sinj_col] = SENTINEL_COEF;
                    hh_imag[sinj_row][sinj_col] = '0;
                end
            hh_load = 1'b1;
        end

        @(posedge clk);
        vin_cycle[NUM_TESTS + sinj_test] = cycle_counter;
        $display("    [SuiteB] post-stall frame %0d  vin=%0d",
                 sinj_test, vin_cycle[NUM_TESTS + sinj_test]);
    end

    // ------------------------------------------------------------------
    // Phase 4: sentinel frame (index STALL_TESTS-1).
    //   Uses the SENTINEL coef set loaded during Phase 3's last iteration
    //   (one cycle ago, per the hh_load timing constraint).
    //   y is all-SENTINEL_Y (real only) to match the gold calculation.
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] Phase 4: sentinel frame (index %0d)", STALL_TESTS-1);
    @(negedge clk);
    en = 1'b1;
    for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
        y_real[sinj_col] = SENTINEL_Y;
        y_imag[sinj_col] = '0;
    end
    valid_in = 1'b1;
    hh_load  = 1'b0;   // sentinel coef already registered by Phase 3's last iteration
    @(posedge clk);
    vin_cycle[NUM_TESTS + STALL_TESTS - 1] = cycle_counter;
    $display("    [SuiteB] sentinel frame  vin=%0d",
             vin_cycle[NUM_TESTS + STALL_TESTS - 1]);

    // De-assert
    @(negedge clk);
    valid_in = 1'b0;
    hh_load  = 1'b0;
    en       = 1'b1;
    for (sinj_col = 0; sinj_col < COLS; sinj_col = sinj_col + 1) begin
        y_real[sinj_col] = '0;
        y_imag[sinj_col] = '0;
    end

    $display(">>> [SuiteB] STALL INJECTOR done");
end


// ===========================================================================
// PROCESS 5 — SUITE B STALL COLLECTOR
// ===========================================================================
// Two responsibilities:
//   (a) During the stall window, check that valid_out never asserts.
//   (b) After the stall, collect STALL_TESTS outputs from valid_out.
//
// Timing:
//   stall_window_active is driven 1'b1 by stall_injector_proc for exactly
//   the STALL_CYCLES negedge-to-posedge intervals where en=0 (Phase 2),
//   and 1'b0 otherwise. Waiting on this flag (rather than polling vin_cycle,
//   which is X until first written and so `== 0` never becomes true) gives
//   an unambiguous, correctly-timed start for the stall-window monitor.
// ===========================================================================
integer sc_idx, sc_row;

initial begin : stall_collector_proc
    wait(stall_vectors_ready);

    // Wait until Suite A completes fully before watching valid_out,
    // to avoid mis-capturing Suite A's outputs.
    wait(collect_done);

    // Wait for the stall injector to enter Phase 2 (en=0 window).
    wait(stall_window_active);
    $display(">>> [SuiteB] COLLECTOR: stall window active, monitoring %0d cycles",
             STALL_CYCLES);

    // -----------------------------------------------------------------------
    // Monitor stall window: STALL_CYCLES posedges with en=0.
    // valid_out must be 0 on every posedge in this window.
    // -----------------------------------------------------------------------
    repeat (STALL_CYCLES) begin
        @(posedge clk);
        if (valid_out === 1'b1) begin
            $display("  [SuiteB] SPURIOUS valid_out during stall at cycle %0d  FAIL",
                     cycle_counter);
            stall_spurious_vout = stall_spurious_vout + 1;
        end
    end
    $display(">>> [SuiteB] COLLECTOR: stall window ended, spurious_vout=%0d",
             stall_spurious_vout);

    // -----------------------------------------------------------------------
    // Collect STALL_TESTS outputs after the stall.
    // -----------------------------------------------------------------------
    sc_idx = 0;
    while (sc_idx < STALL_TESTS) begin
        @(posedge clk);
        if (valid_out === 1'b1) begin
            svout_cycle[sc_idx] = cycle_counter;
            for (sc_row = 0; sc_row < ROWS; sc_row = sc_row + 1) begin
                sgot_r[sc_idx][sc_row] =
                    $itor($signed(yhat_real[sc_row])) / SCALE;
                sgot_i[sc_idx][sc_row] =
                    $itor($signed(yhat_imag[sc_row])) / SCALE;
            end
            $display("    [SuiteB] collected output frame %0d at cycle %0d",
                     sc_idx, svout_cycle[sc_idx]);
            sc_idx = sc_idx + 1;
        end
    end

    $display(">>> [SuiteB] COLLECTOR done");
    stall_collect_done = 1'b1;
end


// ===========================================================================
// Global timeout guard
// ===========================================================================
initial begin : timeout_proc
    #50_000_000;
    $display("GLOBAL TIMEOUT — simulation exceeded 50 ms wall limit");
    $finish;
end

endmodule
// =============================================================================
// End of tb_matched_filter_pipe.sv
// =============================================================================