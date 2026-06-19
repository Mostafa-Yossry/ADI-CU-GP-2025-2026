// =============================================================================
// tb_systolic_matmul_vectors.sv
// -----------------------------------------------------------------------------
// File-based verification testbench for the TRUE 2D WAVEFRONT systolic array.
//
// DUT: systolic_matmul.sv (true 2D wavefront, per-row A skew, spatial B)
//
// Computes:  ŷ = H^H · y   (matched filter, 8×8 complex fixed-point)
//
// ─── INPUT PROTOCOL (unchanged from old testbench) ───────────────────────────
//
//   H^H is TIME-MULTIPLEXED on ROWS parallel ports:
//     Cycle k:  hh_real[r] = H^H[r][k]  for r = 0..ROWS-1
//     start = 1 on cycle 0, 0 thereafter.
//
//   y is SPATIAL — all K elements presented simultaneously and held constant:
//     y_real[c] = y(k=c)   for c = 0..COLS-1
//     Loaded one negedge before start fires, held for entire transaction.
//
// ─── ARCHITECTURE NOTES (why the protocol is unchanged) ──────────────────────
//
//   A (H^H): Each row gr has its own gr-stage delay chain (skew_a_r[gr]).
//            hh_real_w[gr] at cycle k holds H^H[gr][k]; after gr delay stages
//            it arrives at every PE in row gr on cycle k+gr = gr+gc when k=gc.
//            Port protocol identical to old design.
//
//   B (y):   Each PE[gr][gc] is fed from b_left_r[gr][gc] = skew_y_r[gc][gr],
//            which delays y_real_w[gc] (constant) by gr stages — same spatial
//            mapping as before.  b_pass is registered inside each PE but its
//            output is not used for inter-PE B routing in this mapping.
//
//   valid:   2D skew (skew_valid + skew_valid2) unchanged.
//
// ─── OUTPUT CAPTURE ──────────────────────────────────────────────────────────
//
//   Result for row gr is at yhat_real[gr][COLS-1] when valid_out[gr][COLS-1]=1.
//   Each row fires its valid exactly once, at cycle (gr + COLS-1 + 1).
//   Row 7 fires last at cycle 7+7+1 = 15 after start; total from cycle 0: 23.
//
// ─── PIPE LATENCY ────────────────────────────────────────────────────────────
//
//   PIPE_LAT = (ROWS-1) + (COLS-1) + K_DEPTH + 1 = 7+7+8+1 = 23 cycles
//
// ─── VECTOR FILE FORMAT ──────────────────────────────────────────────────────
//
//   hh_real.txt / hh_imag.txt :
//     64 integers per test, Q1.11 (12-bit signed, range −2048..2047).
//     Ordered k-outer, row-inner:
//       k=0,row=0 ; k=0,row=1 ; … ; k=0,row=7
//       k=1,row=0 ; …
//       k=7,row=7
//
//   y_real.txt / y_imag.txt :
//     8 integers per test, Q1.11.
//     Ordered k=0..7.
//
//   z_real_golden.txt / z_imag_golden.txt :
//     8 integers per test, Q5.11 (16-bit signed, already scaled by 2048).
//     Ordered row=0..7.
//
// =============================================================================

`timescale 1ns/1ps

module tb_systolic_matmul_vectors;

// ============================================================================
// PARAMETERS
// ============================================================================

localparam ROWS    = 8;
localparam COLS    = 8;      // accumulation dimension = K_DEPTH
localparam K_DEPTH = 8;

localparam WL_IN   = 12;
localparam WL_OUT  = 16;

// Q5.11: divide raw integer output by 2^11 to get floating-point value
localparam real SCALE_OUT = 2048.0;

// Total pipeline latency in clock cycles
localparam PIPE_LAT = (ROWS-1) + (COLS-1) + K_DEPTH + 1;  // = 23

localparam NUM_TESTS  = 100;

// Watchdog: valid fires at most PIPE_LAT cycles after start.
// Add generous margin for testbench overhead (negedge/posedge interleaving).
localparam MAX_CYCLES = PIPE_LAT + 20;  // = 43

localparam real TOL = 0.01;   // ~1 % — covers Q1.11 quantisation error

// ============================================================================
// CLOCK
// ============================================================================

reg clk = 0;
always #5 clk = ~clk;   // 100 MHz, 10 ns period

// ============================================================================
// DUT CONTROL SIGNALS
// ============================================================================

reg rst_n;
reg en;
reg start;

// ============================================================================
// DUT I/O
// ============================================================================

reg  signed [WL_IN-1:0]  hh_real [0:ROWS-1];
reg  signed [WL_IN-1:0]  hh_imag [0:ROWS-1];

reg  signed [WL_IN-1:0]  y_real  [0:COLS-1];
reg  signed [WL_IN-1:0]  y_imag  [0:COLS-1];

wire signed [WL_OUT-1:0] yhat_real [0:ROWS-1][0:COLS-1];
wire signed [WL_OUT-1:0] yhat_imag [0:ROWS-1][0:COLS-1];

wire valid_out [0:ROWS-1][0:COLS-1];

// ============================================================================
// DUT INSTANTIATION
// ============================================================================

systolic_matmul #(
    .ROWS    (ROWS),
    .COLS    (COLS),
    .K_DEPTH (K_DEPTH),
    .WL_IN   (WL_IN),
    .WL_INT  (16),
    .WL_OUT  (WL_OUT)
) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .en       (en),
    .start    (start),
    .hh_real  (hh_real),
    .hh_imag  (hh_imag),
    .y_real   (y_real),
    .y_imag   (y_imag),
    .yhat_real(yhat_real),
    .yhat_imag(yhat_imag),
    .valid_out(valid_out)
);

// ============================================================================
// FILE HANDLES
// ============================================================================

integer fid_hh_real, fid_hh_imag;
integer fid_y_real,  fid_y_imag;
integer fid_z_real,  fid_z_imag;

// ============================================================================
// TEST VECTOR STORAGE
// ============================================================================

// H^H: [row][k] — loaded k-outer row-inner, accessed row-outer k-inner when driving
integer hh_r_mem [0:ROWS-1][0:K_DEPTH-1];
integer hh_i_mem [0:ROWS-1][0:K_DEPTH-1];

// y: [k=0..K_DEPTH-1]
integer y_r_mem  [0:K_DEPTH-1];
integer y_i_mem  [0:K_DEPTH-1];

// Golden output: [row=0..ROWS-1], Q5.11 integer
integer z_r_golden [0:ROWS-1];
integer z_i_golden [0:ROWS-1];

// ============================================================================
// CAPTURE BUFFERS
// ============================================================================

real    got_r       [0:ROWS-1];
real    got_i       [0:ROWS-1];
integer valid_seen  [0:ROWS-1];

// ============================================================================
// BOOKKEEPING
// ============================================================================

integer test;
integer row;
integer k;
integer r;
integer tmp;
integer status;
integer pass_cnt;
integer fail_cnt;
integer done_cnt;
integer watchdog;
real    exp_r, exp_i;
real    err_r, err_i;

// ============================================================================
// TASK: apply_reset
//   Asserts async reset for 2 posedges, deasserts, then waits 1 more posedge
//   to ensure all flip-flops have settled before the next operation.
//   Zeroes all DUT inputs during reset so no spurious data enters.
// ============================================================================

task apply_reset;
    integer rc;
    begin
        rst_n = 0;
        en    = 1;
        start = 0;
        for (rc = 0; rc < ROWS; rc = rc + 1) begin
            hh_real[rc] = 0;
            hh_imag[rc] = 0;
        end
        for (rc = 0; rc < COLS; rc = rc + 1) begin
            y_real[rc] = 0;
            y_imag[rc] = 0;
        end
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    end
endtask

// ============================================================================
// TASK: load_test_vectors
//   Reads one test's worth of data from the open file handles into local arrays.
//   File ordering: H^H is k-outer/row-inner (64 values), y is k=0..7 (8 values),
//   z_golden is row=0..7 (8 Q5.11 integers).
// ============================================================================

task load_test_vectors;
    begin
        // H^H — k outer, row inner
        for (k = 0; k < K_DEPTH; k = k + 1) begin
            for (row = 0; row < ROWS; row = row + 1) begin
                status = $fscanf(fid_hh_real, "%d\n", tmp);
                hh_r_mem[row][k] = tmp;
                status = $fscanf(fid_hh_imag, "%d\n", tmp);
                hh_i_mem[row][k] = tmp;
            end
        end

        // y — k = 0..K_DEPTH-1
        for (k = 0; k < K_DEPTH; k = k + 1) begin
            status = $fscanf(fid_y_real, "%d\n", tmp);
            y_r_mem[k] = tmp;
            status = $fscanf(fid_y_imag, "%d\n", tmp);
            y_i_mem[k] = tmp;
        end

        // Golden z — row = 0..ROWS-1, Q5.11 integers
        for (row = 0; row < ROWS; row = row + 1) begin
            status = $fscanf(fid_z_real, "%d\n", tmp);
            z_r_golden[row] = tmp;
            status = $fscanf(fid_z_imag, "%d\n", tmp);
            z_i_golden[row] = tmp;
        end
    end
endtask

// ============================================================================
// TASK: drive_inputs
//   Drives one complete H^H×y transaction onto the DUT.
//
//   Protocol:
//     1. Pre-load all y elements (spatial, constant) one negedge before start.
//        y_real[c] = y(k=c) for c = 0..COLS-1.  Held for entire K_DEPTH cycles.
//     2. For k = 0..K_DEPTH-1:  drive H^H column k on negedge, start=1 on k=0.
//        DUT samples on next posedge.
//     3. De-assert start and zero H^H inputs on the cycle after the last column.
//
//   Timing: driven on negedge → sampled by DUT on following posedge.
//   This is identical to the old testbench protocol.
// ============================================================================

task drive_inputs;
    begin
        // Step 1: pre-load y (spatial, one negedge before start)
        @(negedge clk);
        for (r = 0; r < COLS; r = r + 1) begin
            y_real[r] = y_r_mem[r];
            y_imag[r] = y_i_mem[r];
        end

        // Step 2: stream K_DEPTH columns of H^H, start=1 on first
        for (k = 0; k < K_DEPTH; k = k + 1) begin
            @(negedge clk);
            start = (k == 0) ? 1'b1 : 1'b0;
            for (r = 0; r < ROWS; r = r + 1) begin
                hh_real[r] = hh_r_mem[r][k];
                hh_imag[r] = hh_i_mem[r][k];
            end
        end

        // Step 3: de-assert and zero
        @(negedge clk);
        start = 0;
        for (r = 0; r < ROWS; r = r + 1) begin
            hh_real[r] = 0;
            hh_imag[r] = 0;
        end
        // y can stay — valid pipeline has already passed and will not be
        // affected; it will be overwritten or zeroed before the next test.
    end
endtask

// ============================================================================
// TASK: collect_outputs
//   Polls valid_out[row][COLS-1] on every posedge+#1 and latches yhat when
//   the first (and only) valid pulse fires for each row.
//   Times out after MAX_CYCLES posedges with an error count penalty.
//
//   valid_out[row][COLS-1] fires at cycle (row + COLS-1 + 1) from start.
//   Row 0 fires at cycle COLS = 8; row 7 fires at cycle COLS+6 = 14.
//   The watchdog limit (PIPE_LAT+20 = 43) is well above the maximum (14).
// ============================================================================

task collect_outputs;
    begin
        for (row = 0; row < ROWS; row = row + 1) begin
            valid_seen[row] = 0;
            got_r[row]      = 0.0;
            got_i[row]      = 0.0;
        end
        done_cnt = 0;
        watchdog = 0;

        while ((done_cnt < ROWS) && (watchdog < MAX_CYCLES)) begin
            @(posedge clk);
            #1;   // let NBA assignments settle before reading outputs
            watchdog = watchdog + 1;

            for (row = 0; row < ROWS; row = row + 1) begin
                if (valid_out[row][COLS-1] && !valid_seen[row]) begin
                    valid_seen[row] = 1;
                    got_r[row] = $itor($signed(yhat_real[row][COLS-1])) / SCALE_OUT;
                    got_i[row] = $itor($signed(yhat_imag[row][COLS-1])) / SCALE_OUT;
                    done_cnt = done_cnt + 1;
                end
            end
        end

        if (watchdog >= MAX_CYCLES) begin
            $display("  TIMEOUT test=%0d after %0d cycles", test, MAX_CYCLES);
            fail_cnt = fail_cnt + ROWS;
        end
    end
endtask

// ============================================================================
// TASK: check_results
//   Compares captured outputs against golden reference.
//   Golden values are Q5.11 integers (pre-scaled by 2048 by MATLAB).
//   Dividing by SCALE_OUT converts to floating-point for error comparison.
// ============================================================================

task check_results;
    begin
        for (row = 0; row < ROWS; row = row + 1) begin
            exp_r = $itor(z_r_golden[row]) / SCALE_OUT;
            exp_i = $itor(z_i_golden[row]) / SCALE_OUT;

            err_r = got_r[row] - exp_r;
            err_i = got_i[row] - exp_i;
            if (err_r < 0.0) err_r = -err_r;
            if (err_i < 0.0) err_i = -err_i;

            if ((err_r > TOL) || (err_i > TOL)) begin
                $display("  FAIL test=%0d row=%0d  got=(%0.5f,%0.5f)  exp=(%0.5f,%0.5f)",
                         test, row, got_r[row], got_i[row], exp_r, exp_i);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("  PASS test=%0d row=%0d  got=(%0.5f,%0.5f)",
                         test, row, got_r[row], got_i[row]);
                pass_cnt = pass_cnt + 1;
            end
        end
    end
endtask

// ============================================================================
// MAIN TEST SEQUENCE
// ============================================================================

initial begin

    pass_cnt = 0;
    fail_cnt = 0;

    // --- Open vector files ---------------------------------------------------
    fid_hh_real = $fopen("rtl_vectors_Z_Q1_11/hh_real.txt", "r");
    fid_hh_imag = $fopen("rtl_vectors_Z_Q1_11/hh_imag.txt", "r");
    fid_y_real  = $fopen("rtl_vectors_Z_Q1_11/y_real.txt",  "r");
    fid_y_imag  = $fopen("rtl_vectors_Z_Q1_11/y_imag.txt",  "r");
    fid_z_real  = $fopen("rtl_vectors_Z_Q1_11/z_real_golden.txt", "r");
    fid_z_imag  = $fopen("rtl_vectors_Z_Q1_11/z_imag_golden.txt", "r");

    if (!fid_hh_real || !fid_hh_imag ||
        !fid_y_real  || !fid_y_imag  ||
        !fid_z_real  || !fid_z_imag) begin
        $display("ERROR: could not open one or more vector files.");
        $display("       Expected directory: rtl_vectors_Z_Q1_11/");
        $finish;
    end

    $display("========================================");
    $display(" SYSTOLIC ARRAY VECTOR TESTBENCH");
    $display(" ROWS=%0d  COLS=%0d  K=%0d  PIPE_LAT=%0d",
             ROWS, COLS, K_DEPTH, PIPE_LAT);
    $display(" NUM_TESTS=%0d  TOL=%0.4f", NUM_TESTS, TOL);
    $display("========================================");

    // --- Initial reset -------------------------------------------------------
    apply_reset();

    // --- Test loop -----------------------------------------------------------
    for (test = 0; test < NUM_TESTS; test = test + 1) begin

        $display("");
        $display("--- Test %0d ---", test);

        load_test_vectors();

        fork
            drive_inputs();
            collect_outputs();
        join

        check_results();

        // Reset and drain between tests.
        // repeat(PIPE_LAT) ensures no valid tokens from this test are still
        // in flight when collect_outputs for the next test starts watching.
        apply_reset();
        repeat (PIPE_LAT) @(posedge clk);

    end

    // --- Summary -------------------------------------------------------------
    $display("");
    $display("========================================");
    $display(" SUMMARY");
    $display(" PASS = %0d / %0d", pass_cnt, pass_cnt + fail_cnt);
    $display(" FAIL = %0d / %0d", fail_cnt, pass_cnt + fail_cnt);
    $display("========================================");

    if (fail_cnt == 0)
        $display(" ALL TESTS PASSED");
    else
        $display(" SOME TESTS FAILED");

    $fclose(fid_hh_real);  $fclose(fid_hh_imag);
    $fclose(fid_y_real);   $fclose(fid_y_imag);
    $fclose(fid_z_real);   $fclose(fid_z_imag);

    $finish;

end

// ============================================================================
// GLOBAL TIMEOUT (safety net)
// ============================================================================

initial begin
    // NUM_TESTS × (PIPE_LAT + drain) cycles, generous margin
    #(NUM_TESTS * (PIPE_LAT + 50) * 10 + 10000);
    $display("GLOBAL TIMEOUT — simulation hung");
    $finish;
end

endmodule