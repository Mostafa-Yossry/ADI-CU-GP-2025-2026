// =============================================================================
// tb_systolic_matmul.sv
// -----------------------------------------------------------------------------
// Testbench for systolic_matmul (wavefront systolic matched-filter array)
//
// ARCHITECTURAL CORRECTION (see design notes):
//   For ŷ = H^H(8×8) · y(8×1), the rightward dimension of the PE array must
//   equal K_DEPTH (not the number of output columns).  Each row has K_DEPTH=8
//   PEs; partial sums accumulate rightward across all K PEs; the final result
//   is read from the rightmost PE (col = K_DEPTH-1) of each row.
//
//   Instantiation: ROWS=8, COLS=K_DEPTH=8.
//   The single y vector element for each k-step is broadcast to every row's
//   column-0 PE via the y skew registers (y_real[0] / y_imag[0]).
//   H^H column k is fed on cycle k; each column is skewed so that H^H(i,k)
//   meets y(k) at PE[i][k].
//
// OUTPUT CAPTURE:
//   valid_out[row][K_DEPTH-1] fires once per row when ŷ(row) is ready.
//   Capture order: the wavefront exits rows top-to-bottom, so row 0 fires
//   first (at cycle K_DEPTH-1 + ROWS-1 + 1 after start), row 7 last.
//
// OUTPUT LATENCY (pipeline_latency from spec comment):
//   pipe_latency = (ROWS-1) + (COLS-1) + K + 1
//               = 7 + 7 + 8 + 1 = 23 cycles after first input.
//
// TEST CASES:
//   Test 0 – Identity check : H^H = I (identity), y = [1 1 … 1]^T
//             Expected ŷ(i) = 1.0 for all i (real), 0.0 (imag)
//   Test 1 – Column check   : H^H has only row 3 non-zero (= [1 0 … 0])
//             y = [1 0 … 0]^T  →  ŷ(3)=1, all others 0
//   Test 2 – Scale check    : H^H = 0.5·I, y = [1 1 … 1]^T  → ŷ=0.5
//   Test 3 – Random-ish values (numeric smoke test)
//
// FIXED-POINT FORMATS (matching DUT spec):
//   WL_IN  = 12 : Q1.11  (inputs to DUT)
//   WL_OUT = 16 : Q5.11  (outputs from DUT)
//   Scale for Q1.11 : 1.0 = 2^11 = 2048
//   Scale for Q5.11 : 1.0 = 2^11 = 2048  (same fractional bits)
// =============================================================================

`timescale 1ns/1ps

module tb_systolic_matmul;

// ---------------------------------------------------------------------------
// DUT parameters
// ---------------------------------------------------------------------------
localparam ROWS    = 8;
localparam COLS    = 8;   // = K_DEPTH: accumulation flows rightward
localparam K_DEPTH = 8;
localparam WL_IN   = 12;
localparam WL_OUT  = 16;

localparam SCALE_IN  = 2048;   // 1.0 in Q1.11
localparam SCALE_OUT = 2048;   // 1.0 in Q5.11  (frac bits = 11)

// ---------------------------------------------------------------------------
// Clock / reset
// ---------------------------------------------------------------------------
reg clk  = 0;
reg rst_n;
reg en;
always #5 clk = ~clk;   // 100 MHz (period = 10 ns)

// ---------------------------------------------------------------------------
// DUT port signals
// ---------------------------------------------------------------------------
reg  start;
reg  signed [WL_IN-1:0] hh_real [0:ROWS-1];
reg  signed [WL_IN-1:0] hh_imag [0:ROWS-1];
reg  signed [WL_IN-1:0] y_real  [0:COLS-1];
reg  signed [WL_IN-1:0] y_imag  [0:COLS-1];

wire signed [WL_OUT-1:0] yhat_real [0:ROWS-1][0:COLS-1];
wire signed [WL_OUT-1:0] yhat_imag [0:ROWS-1][0:COLS-1];
wire                      valid_out [0:ROWS-1][0:COLS-1];

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Test data storage
//   hh_r_test[row][k], hh_i_test[row][k]  : H^H matrix (row x K_DEPTH)
//   y_r_test[k], y_i_test[k]              : y vector   (K_DEPTH elements)
// ---------------------------------------------------------------------------
reg signed [WL_IN-1:0] hh_r_test [0:ROWS-1][0:K_DEPTH-1];
reg signed [WL_IN-1:0] hh_i_test [0:ROWS-1][0:K_DEPTH-1];
reg signed [WL_IN-1:0] y_r_test  [0:K_DEPTH-1];
reg signed [WL_IN-1:0] y_i_test  [0:K_DEPTH-1];

// Expected outputs (real integer multiple of SCALE_OUT, stored as real)
real exp_real [0:ROWS-1];
real exp_imag [0:ROWS-1];

// Result capture
real got_real [0:ROWS-1];
real got_imag [0:ROWS-1];
integer valid_fired [0:ROWS-1];

// Loop variables
integer i, k, row, col;
integer pass_cnt, fail_cnt, test_num;

// Simulation time limit watchdog
integer watchdog;
// MAX_CYCLES: from start pulse to last valid_out.
//   Worst case = K_DEPTH + PIPE_LAT + (ROWS-1) + margin  = 8+23+7+12 = 50.
//   Use 200 for safety.
localparam MAX_CYCLES = 200;

// Output latency: ROWS-1 + COLS-1 + K_DEPTH + 1 (from spec)
localparam PIPE_LAT = (ROWS-1) + (COLS-1) + K_DEPTH + 1;  // = 23

// ---------------------------------------------------------------------------
// Helper task : apply reset
// ---------------------------------------------------------------------------
task apply_reset;
    integer r, c;
    begin
        rst_n = 0; en = 1; start = 0;
        for (r = 0; r < ROWS; r = r + 1) begin
            hh_real[r] = 0; hh_imag[r] = 0;
        end
        for (c = 0; c < COLS; c = c + 1) begin
            y_real[c] = 0; y_imag[c] = 0;
        end
        @(negedge clk); @(negedge clk);
        rst_n = 1;
        @(negedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// Helper task : drive inputs for one test
//
//   The DUT's y skew architecture (Section 2b of systolic_matmul):
//     y_real_w[gc] feeds the skew chain for PE column gc.
//     The skew chain delays y_real_w[gc] by gr cycles before it reaches
//     PE[gr][gc].  So PE[gr][gc] sees y_real[gc] at time (gr + gc) — but
//     since the column index gc IS the k-index in our mapping, we need
//     PE[gr][gc] to see y(gc) = y(k=gc).
//
//   Correct driving strategy:
//     y_real[col] = y(col)   (held constant across all K_DEPTH cycles)
//     The row-skew inside the DUT ensures PE[row][col] sees y(col) at
//     cycle (row + col) — which matches H^H(row, col)'s arrival time.
//
//   H^H is still time-multiplexed: column k of H^H is presented on cycle k.
//   The column-skew inside the DUT delays H^H(row, col) by col cycles so
//   it reaches PE[row][col] at cycle col (skew) + row (a_pass) = row + col.
//
//   valid / start: start is pulsed on cycle 0 (cycle of H^H col 0).
// ---------------------------------------------------------------------------
task drive_inputs;
    integer k2, r2;
    begin
        // Pre-load the constant y values before the start pulse
        @(negedge clk);
        start = 1'b0;
        for (r2 = 0; r2 < COLS; r2 = r2 + 1) begin
            y_real[r2] = y_r_test[r2];   // y_real[col] = y(k=col), constant
            y_imag[r2] = y_i_test[r2];
        end

        for (k2 = 0; k2 < K_DEPTH; k2 = k2 + 1) begin
            @(negedge clk);   // drive on negedge, sampled on next posedge
            start = (k2 == 0) ? 1'b1 : 1'b0;
            // H^H column k2 — all rows simultaneously
            for (r2 = 0; r2 < ROWS; r2 = r2 + 1) begin
                hh_real[r2] = hh_r_test[r2][k2];
                hh_imag[r2] = hh_i_test[r2][k2];
            end
            // y remains constant throughout (not time-multiplexed)
        end
        // De-assert start and zero H^H inputs after K cycles
        @(negedge clk);
        start = 0;
        for (r2 = 0; r2 < ROWS; r2 = r2 + 1) begin
            hh_real[r2] = 0; hh_imag[r2] = 0;
        end
        // y can stay; it won't affect output since valid pipeline has passed
    end
endtask

// ---------------------------------------------------------------------------
// Helper task : collect outputs
//   Waits for all ROWS valid pulses at col = COLS-1 (rightmost column).
//   Times out after MAX_CYCLES posedges.
// ---------------------------------------------------------------------------
task collect_outputs;
    integer vrow;
    integer done_cnt;
    integer start_seen;   // gate: only capture valid AFTER start has been observed
    begin
        for (vrow = 0; vrow < ROWS; vrow = vrow + 1) begin
            valid_fired[vrow] = 0;
            got_real[vrow]    = 0.0;
            got_imag[vrow]    = 0.0;
        end
        done_cnt  = 0;
        watchdog  = 0;
        start_seen = 0;
        while (done_cnt < ROWS && watchdog < MAX_CYCLES) begin
            @(posedge clk); #1;
            watchdog = watchdog + 1;
            // Arm capture only after the start pulse has been seen this test
            if (start) start_seen = 1;
            if (start_seen) begin
                for (vrow = 0; vrow < ROWS; vrow = vrow + 1) begin
                    if (valid_out[vrow][COLS-1] && !valid_fired[vrow]) begin
                        valid_fired[vrow] = 1;
                        got_real[vrow] = $itor($signed(yhat_real[vrow][COLS-1])) / SCALE_OUT;
                        got_imag[vrow] = $itor($signed(yhat_imag[vrow][COLS-1])) / SCALE_OUT;
                        done_cnt = done_cnt + 1;
                    end
                end
            end
        end
        if (watchdog >= MAX_CYCLES)
            $display("  WARNING: collect_outputs timed out after %0d cycles", MAX_CYCLES);
    end
endtask

// ---------------------------------------------------------------------------
// Helper task : check results
// ---------------------------------------------------------------------------
localparam real TOL = 0.01;   // ~1% tolerance for fixed-point rounding

task check_results;
    integer vrow;
    real err_r, err_i;
    begin
        for (vrow = 0; vrow < ROWS; vrow = vrow + 1) begin
            if (!valid_fired[vrow]) begin
                $display("  FAIL  row %0d: valid never fired", vrow);
                fail_cnt = fail_cnt + 1;
            end else begin
                err_r = got_real[vrow] - exp_real[vrow];
                err_i = got_imag[vrow] - exp_imag[vrow];
                if (err_r < 0) err_r = -err_r;
                if (err_i < 0) err_i = -err_i;
                if (err_r > TOL || err_i > TOL) begin
                    $display("  FAIL  row %0d: got (%0.4f, %0.4f)  exp (%0.4f, %0.4f)",
                             vrow, got_real[vrow], got_imag[vrow],
                             exp_real[vrow], exp_imag[vrow]);
                    fail_cnt = fail_cnt + 1;
                end else begin
                    $display("  PASS  row %0d: got (%0.4f, %0.4f)",
                             vrow, got_real[vrow], got_imag[vrow]);
                    pass_cnt = pass_cnt + 1;
                end
            end
        end
    end
endtask

// ---------------------------------------------------------------------------
// Helper task : inter-test drain (flush pipeline between tests)
//   Wait enough cycles for the array to fully drain and reset.
// ---------------------------------------------------------------------------
task drain_pipeline;
    integer d;
    begin
        apply_reset;   // full async reset between tests to clear state
        // Wait long enough to flush every in-flight valid token.
        // The longest path from a start pulse to valid_out is PIPE_LAT cycles,
        // so PIPE_LAT+4 gives comfortable margin even for async-reset artefacts.
        repeat (PIPE_LAT + 4) @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// MAIN TEST SEQUENCE
// ---------------------------------------------------------------------------
initial begin
    pass_cnt = 0; fail_cnt = 0; test_num = 0;

    $display("========================================");
    $display(" Systolic Matched Filter Testbench");
    $display(" ROWS=%0d  COLS(=K_DEPTH)=%0d", ROWS, COLS);
    $display(" PIPE_LAT=%0d cycles", PIPE_LAT);
    $display("========================================");

    apply_reset;
    repeat (4) @(posedge clk);

    // ========================================================================
    // TEST 0 : Identity matrix times all-ones vector  → ŷ = [1 1 … 1]
    //   H^H = I_{8×8}  (diagonal = 1.0 in Q1.11, off-diagonal = 0)
    //   y   = [1 1 1 1 1 1 1 1]^T
    //   ŷ(i) = sum_k H^H(i,k)·y(k) = 1·1 = 1.0  (only k=i contributes)
    // ========================================================================
    test_num = 0;
    $display("\n--- Test %0d: Identity × all-ones ---", test_num);

    // SCALE_IN = 2^11 = 2048 overflows Q1.11 to −1.0 after widening.
    // Use SCALE_IN-1 = 2047 (= 0x7FF), which widens to 0x7FF0 = +0.9995
    // in Q1.15.  Product ≈ 0.9990, within TOL=0.01 of the expected 1.0.
    for (row = 0; row < ROWS; row = row + 1)
        for (k = 0; k < K_DEPTH; k = k + 1) begin
            hh_r_test[row][k] = (row == k) ? (SCALE_IN - 1) : 0;
            hh_i_test[row][k] = 0;
        end
    for (k = 0; k < K_DEPTH; k = k + 1) begin
        y_r_test[k] = SCALE_IN - 1;
        y_i_test[k] = 0;
    end
    for (i = 0; i < ROWS; i = i + 1) begin
        exp_real[i] = 1.0;
        exp_imag[i] = 0.0;
    end

    fork
        drive_inputs;
        collect_outputs;
    join
    check_results;

    // ========================================================================
    // TEST 1 : Only row 3 of H^H non-zero; only y[3] non-zero
    //   H^H(3, 3) = 1.0;  all other entries = 0.
    //   y = e_3 = [0 0 0 1 0 0 0 0]^T
    //   ŷ(3) = 1.0,  ŷ(i≠3) = 0.0
    // ========================================================================
    test_num = 1;
    $display("\n--- Test %0d: Single non-zero row and element ---", test_num);
    drain_pipeline;

    // Use SCALE_IN-1 so both operands are +0.9995 (no overflow); product ≈ 0.999
    for (row = 0; row < ROWS; row = row + 1)
        for (k = 0; k < K_DEPTH; k = k + 1) begin
            hh_r_test[row][k] = (row == 3 && k == 3) ? (SCALE_IN - 1) : 0;
            hh_i_test[row][k] = 0;
        end
    for (k = 0; k < K_DEPTH; k = k + 1) begin
        y_r_test[k] = (k == 3) ? (SCALE_IN - 1) : 0;
        y_i_test[k] = 0;
    end
    for (i = 0; i < ROWS; i = i + 1) begin
        exp_real[i] = (i == 3) ? 1.0 : 0.0;
        exp_imag[i] = 0.0;
    end

    fork
        drive_inputs;
        collect_outputs;
    join
    check_results;

    // ========================================================================
    // TEST 2 : Scaled identity: H^H = 0.5·I, y = all-ones  → ŷ = 0.5
    //   Q1.11 representation of 0.5 = 2^10 = 1024
    // ========================================================================
    test_num = 2;
    $display("\n--- Test %0d: 0.5·I × all-ones ---", test_num);
    drain_pipeline;

    for (row = 0; row < ROWS; row = row + 1)
        for (k = 0; k < K_DEPTH; k = k + 1) begin
            hh_r_test[row][k] = (row == k) ? (SCALE_IN / 2) : 0;
            hh_i_test[row][k] = 0;
        end
    for (k = 0; k < K_DEPTH; k = k + 1) begin
        y_r_test[k] = SCALE_IN - 1;   // +0.9995 Q1.15; 0.5×0.9995≈0.4998, within TOL
        y_i_test[k] = 0;
    end
    for (i = 0; i < ROWS; i = i + 1) begin
        exp_real[i] = 0.5;
        exp_imag[i] = 0.0;
    end

    fork
        drive_inputs;
        collect_outputs;
    join
    check_results;

    // ========================================================================
    // TEST 3 : Complex identity: H^H = j·I  (all-imaginary ones on diagonal)
    //          y = [1 1 … 1]^T (real)
    //          ŷ(i) = j · y(i) = j   →  real=0, imag=1
    // ========================================================================
    test_num = 3;
    $display("\n--- Test %0d: j·I × all-ones (complex identity) ---", test_num);
    drain_pipeline;

    for (row = 0; row < ROWS; row = row + 1)
        for (k = 0; k < K_DEPTH; k = k + 1) begin
            hh_r_test[row][k] = 0;
            hh_i_test[row][k] = (row == k) ? (SCALE_IN - 1) : 0;  // +0.9995 Q1.15
        end
    for (k = 0; k < K_DEPTH; k = k + 1) begin
        y_r_test[k] = SCALE_IN - 1;   // +0.9995; product 0.9995²≈0.999, within TOL
        y_i_test[k] = 0;
    end
    // (0 + j·a)(b + 0j): real = 0; imag = a·b = 0.9995² ≈ 0.999 → within TOL=0.01
    for (i = 0; i < ROWS; i = i + 1) begin
        exp_real[i] = 0.0;
        exp_imag[i] = 1.0;
    end

    fork
        drive_inputs;
        collect_outputs;
    join
    check_results;

    // ========================================================================
    // TEST 4 : All-ones matrix × all-ones vector
    //   H^H(i,k) = 1.0 for all i,k;  y(k) = 1.0 for all k
    //   ŷ(i) = sum_{k=0}^{7} 1.0 · 1.0 = 8.0
    //   Q5.11 can hold 8.0 (max = 2^4 = 16 before overflow) ✓
    // ========================================================================
    test_num = 4;
    $display("\n--- Test %0d: All-ones H^H × all-ones y → 8.0 ---", test_num);
    drain_pipeline;

    // Use SCALE_IN-1 = 2047 (+0.9995 Q1.15) throughout; 8×0.9995²≈7.992, within TOL
    for (row = 0; row < ROWS; row = row + 1)
        for (k = 0; k < K_DEPTH; k = k + 1) begin
            hh_r_test[row][k] = SCALE_IN - 1;
            hh_i_test[row][k] = 0;
        end
    for (k = 0; k < K_DEPTH; k = k + 1) begin
        y_r_test[k] = SCALE_IN - 1;
        y_i_test[k] = 0;
    end
    for (i = 0; i < ROWS; i = i + 1) begin
        exp_real[i] = 8.0;
        exp_imag[i] = 0.0;
    end

    fork
        drive_inputs;
        collect_outputs;
    join
    check_results;

    // ========================================================================
    // SUMMARY
    // ========================================================================
    repeat (10) @(posedge clk);
    $display("\n========================================");
    $display(" SUMMARY: %0d PASSED  /  %0d FAILED", pass_cnt, fail_cnt);
    $display("========================================");
    if (fail_cnt == 0)
        $display(" ALL TESTS PASSED");
    else
        $display(" *** SOME TESTS FAILED ***");
    $finish;
end

// ---------------------------------------------------------------------------
// Timeout guard
// ---------------------------------------------------------------------------
initial begin
    #50000;
    $display("TIMEOUT: simulation exceeded 50 us");
    $finish;
end

endmodule