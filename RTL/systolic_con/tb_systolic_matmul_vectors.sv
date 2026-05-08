// =============================================================================
// tb_systolic_matmul_vectors.sv
// -----------------------------------------------------------------------------
// File-based RTL verification testbench
//
// Uses MATLAB-generated vector files:
//
//   hh_real.txt
//   hh_imag.txt
//   y_real.txt
//   y_imag.txt
//   z_real_golden.txt
//   z_imag_golden.txt
//
// Verifies:
//   Z = H^H * Y   (8x8 H^H, 8x1 Y -> 8x1 Z)
//
// DUT formats:
//   Inputs  : Q1.11  (12-bit)
//   Outputs : Q5.11  (16-bit)
//
// -----------------------------------------------------------------------------
// FIX LOG (vs original testbench)
//
// FIX 1 : COLS changed from 8 to 1.
//         Z = H^H * Y is an 8x1 result. COLS=8 would instantiate a full
//         8x8 PE array and produce the wrong computation entirely.
//
// FIX 2 : y_real/imag port width now [0:COLS-1] = [0:0].
//         With COLS=1 only y_real[0]/y_imag[0] exist. The drive loop
//         is guarded by the corrected COLS parameter automatically.
//         Y is a vector (K_DEPTH x 1); y_real[0] is driven with Y[k]
//         each cycle — NOT y_real[0..7] simultaneously.
//
// FIX 3 : collect_outputs reads column index 0 (COLS-1 = 0), not 7.
//         yhat_real[row][0] and valid_out[row][0] are the only valid
//         output column in the COLS=1 configuration.
//
// FIX 4 : PIPE_LAT corrected for COLS=1.
//         Formula: (ROWS-1) + (COLS-1) + K_DEPTH + 1
//         = 7 + 0 + 8 + 1 = 16 cycles  (was 23 with COLS=8).
//
// FIX 5 : Golden Z scaling corrected.
//         Golden files were generated with MULTIPLICATION_TYPES(
//         'fixed_point_Z_8x8', 12) -> output type T.Q1_11 = Q5.7
//         (FL=7, WL=12). Stored integers must be divided by 2^7=128
//         to recover the real value.
//         RTL output is Q5.11 (FL=11, WL=16) -> divide by 2^11=2048.
//         Both sides now divided by their correct scale before compare.
//
// FIX 6 : collect_outputs now captures the LAST valid pulse per row,
//         not the first. valid_in fires K_DEPTH=8 times per row; the
//         PE accumulates across all K pulses. The fully-accumulated
//         result is present only on the final valid_out pulse.
//         Strategy: keep overwriting got_r/got_i on every valid pulse
//         so the last one wins (valid_seen tracks count, not a flag).
//
// -----------------------------------------------------------------------------
// FILE FORMAT
//
// hh_real / hh_imag:
//   64 values per test, ordered as:
//      k=0,row=0 ... k=0,row=7
//      k=1,row=0 ... k=1,row=7
//      ...
//      k=7,row=0 ... k=7,row=7
//
// y_real / y_imag:
//   8 values per test (one per k cycle)
//
// z_real_golden / z_imag_golden:
//   8 values per test (one per output row), Q5.7 stored integers
//
// -----------------------------------------------------------------------------
// PIPELINE LATENCY  (COLS=1)
//
//   pipe_latency = (ROWS-1) + (COLS-1) + K_DEPTH + 1
//               = 7 + 0 + 8 + 1 = 16 cycles
//
// =============================================================================

`timescale 1ns/1ps

module tb_systolic_matmul_vectors;

////////////////////////////////////////////////////////////////////////////////
// PARAMETERS
////////////////////////////////////////////////////////////////////////////////

localparam ROWS    = 8;
localparam COLS    = 1;          // FIX 1: was 8; Z=H^H*Y is 8x1
localparam K_DEPTH = 8;

localparam WL_IN   = 12;
localparam WL_OUT  = 16;

// FIX 5: separate scales for RTL output (Q5.11) and golden (Q5.7)
localparam real SCALE_RTL    = 2048.0;   // 2^11  : RTL output  Q5.11
localparam real SCALE_GOLDEN = 128.0;    // 2^7   : golden file Q5.7 (WL=12)

// FIX 4: pipeline latency for COLS=1 = 7+0+8+1 = 16  (was 23)
localparam PIPE_LAT = (ROWS-1) + (COLS-1) + K_DEPTH + 1;

localparam NUM_TESTS  = 100;
localparam MAX_CYCLES = 200;

// FIX 5: tolerance in real-value units (after scaling)
// 1 LSB of Q5.11 = 1/2048 ~ 0.000488; use 0.001 (2 LSBs) for margin
localparam real TOL = 0.001;

////////////////////////////////////////////////////////////////////////////////
// CLOCK / RESET
////////////////////////////////////////////////////////////////////////////////

reg clk = 0;
always #5 clk = ~clk;

reg rst_n;
reg en;
reg start;

////////////////////////////////////////////////////////////////////////////////
// DUT INTERFACE
////////////////////////////////////////////////////////////////////////////////

reg signed [WL_IN-1:0] hh_real [0:ROWS-1];
reg signed [WL_IN-1:0] hh_imag [0:ROWS-1];

// FIX 2: width is [0:COLS-1] = [0:0]; only y_real[0]/y_imag[0] driven
reg signed [WL_IN-1:0] y_real [0:COLS-1];
reg signed [WL_IN-1:0] y_imag [0:COLS-1];

wire signed [WL_OUT-1:0] yhat_real [0:ROWS-1][0:COLS-1];
wire signed [WL_OUT-1:0] yhat_imag [0:ROWS-1][0:COLS-1];

wire valid_out [0:ROWS-1][0:COLS-1];

////////////////////////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////////////////////////

systolic_matmul #(
    .ROWS    (ROWS),
    .COLS    (COLS),          // FIX 1
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

////////////////////////////////////////////////////////////////////////////////
// FILE HANDLES
////////////////////////////////////////////////////////////////////////////////

integer fid_hh_real;
integer fid_hh_imag;

integer fid_y_real;
integer fid_y_imag;

integer fid_z_real;
integer fid_z_imag;

////////////////////////////////////////////////////////////////////////////////
// STORAGE
////////////////////////////////////////////////////////////////////////////////

integer hh_r_mem [0:ROWS-1][0:K_DEPTH-1];
integer hh_i_mem [0:ROWS-1][0:K_DEPTH-1];

// FIX 2: y memory is K_DEPTH deep, 1 element per cycle (not COLS wide)
integer y_r_mem [0:K_DEPTH-1];
integer y_i_mem [0:K_DEPTH-1];

integer z_r_golden [0:ROWS-1];
integer z_i_golden [0:ROWS-1];

real got_r [0:ROWS-1];
real got_i [0:ROWS-1];

// FIX 6: count valid pulses per row (not a seen-flag) to get last value
integer valid_count [0:ROWS-1];

integer status;

////////////////////////////////////////////////////////////////////////////////
// VARIABLES
////////////////////////////////////////////////////////////////////////////////

integer test;
integer row;
integer k;
integer r;
integer tmp;

integer pass_cnt;
integer fail_cnt;

integer done_cnt;
integer watchdog;

real exp_r;
real exp_i;

real err_r;
real err_i;

////////////////////////////////////////////////////////////////////////////////
// RESET TASK
////////////////////////////////////////////////////////////////////////////////

task apply_reset;
begin

    rst_n = 0;
    en    = 1;
    start = 0;

    // Zero all inputs during reset
    for (r = 0; r < ROWS; r = r + 1) begin
        hh_real[r] = 0;
        hh_imag[r] = 0;
    end
    // FIX 2: only COLS=1 entry
    y_real[0] = 0;
    y_imag[0] = 0;

    @(posedge clk);
    @(posedge clk);

    rst_n = 1;

    @(posedge clk);

end
endtask

////////////////////////////////////////////////////////////////////////////////
// LOAD TEST VECTORS
////////////////////////////////////////////////////////////////////////////////

task load_test_vectors;
begin

    // ------------------------------------------------------------------------
    // HH: 64 values per test, outer=k inner=row
    // ------------------------------------------------------------------------
    for (k = 0; k < K_DEPTH; k = k + 1) begin
        for (row = 0; row < ROWS; row = row + 1) begin

            status = $fscanf(fid_hh_real, "%d\n", tmp);
            hh_r_mem[row][k] = tmp;

            status = $fscanf(fid_hh_imag, "%d\n", tmp);
            hh_i_mem[row][k] = tmp;

        end
    end

    // ------------------------------------------------------------------------
    // Y: 8 values per test, one per k cycle
    // ------------------------------------------------------------------------
    for (k = 0; k < K_DEPTH; k = k + 1) begin

        status = $fscanf(fid_y_real, "%d\n", tmp);
        y_r_mem[k] = tmp;

        status = $fscanf(fid_y_imag, "%d\n", tmp);
        y_i_mem[k] = tmp;

    end

    // ------------------------------------------------------------------------
    // GOLDEN Z: 8 values per test, one per output row
    // ------------------------------------------------------------------------
    for (row = 0; row < ROWS; row = row + 1) begin

        status = $fscanf(fid_z_real, "%d\n", tmp);
        z_r_golden[row] = tmp;

        status = $fscanf(fid_z_imag, "%d\n", tmp);
        z_i_golden[row] = tmp;

    end

end
endtask

////////////////////////////////////////////////////////////////////////////////
// DRIVE INPUTS
//
// FIX 2: y_real[0] is driven with Y[k] each cycle (time-multiplexed),
//        NOT all 8 y elements simultaneously.
//        H^H column k is presented on hh_real[0..7] each cycle.
////////////////////////////////////////////////////////////////////////////////

task drive_inputs;
begin

    // ------------------------------------------------------------------------
    // Stream H^H columns and Y elements together, one column per cycle
    // ------------------------------------------------------------------------
    for (k = 0; k < K_DEPTH; k = k + 1) begin

        @(negedge clk);

        start = (k == 0) ? 1'b1 : 1'b0;

        // Drive all rows of H^H column k
        for (r = 0; r < ROWS; r = r + 1) begin
            hh_real[r] = hh_r_mem[r][k];
            hh_imag[r] = hh_i_mem[r][k];
        end

        // FIX 2: drive y_real[0] with Y[k] — only one port in COLS=1
        y_real[0] = y_r_mem[k];
        y_imag[0] = y_i_mem[k];

    end

    // De-assert start and zero inputs after last column
    @(negedge clk);

    start = 0;

    for (r = 0; r < ROWS; r = r + 1) begin
        hh_real[r] = 0;
        hh_imag[r] = 0;
    end

    y_real[0] = 0;
    y_imag[0] = 0;

end
endtask

////////////////////////////////////////////////////////////////////////////////
// COLLECT OUTPUTS
//
// FIX 3: read from column index 0 (COLS-1 = 0), not column 7
// FIX 6: capture LAST valid pulse per row (overwrite on every pulse);
//        done_cnt increments only when a row's count reaches K_DEPTH
////////////////////////////////////////////////////////////////////////////////

task collect_outputs;
begin

    for (row = 0; row < ROWS; row = row + 1) begin
        valid_count[row] = 0;
        got_r[row]       = 0.0;
        got_i[row]       = 0.0;
    end

    done_cnt = 0;
    watchdog = 0;

    while ((done_cnt < ROWS) && (watchdog < MAX_CYCLES)) begin

        @(posedge clk);
        #1;

        watchdog = watchdog + 1;

        for (row = 0; row < ROWS; row = row + 1) begin

            // FIX 3: column index is 0
            if (valid_out[row][0]) begin

                // Always overwrite — last pulse carries the fully-accumulated result
                got_r[row] = $itor($signed(yhat_real[row][0])) / SCALE_RTL;
                got_i[row] = $itor($signed(yhat_imag[row][0])) / SCALE_RTL;

                valid_count[row] = valid_count[row] + 1;

                // done when all K_DEPTH accumulation pulses have been seen
                // (the last one holds the correct fully-accumulated result)
                if (valid_count[row] == K_DEPTH)
                    done_cnt = done_cnt + 1;

            end

        end

    end

    if (watchdog >= MAX_CYCLES) begin
        $display("TIMEOUT waiting for outputs at test %0d (done_cnt=%0d)", test, done_cnt);
        // Mark any uncompleted rows as failed
        for (row = 0; row < ROWS; row = row + 1) begin
            if (valid_count[row] < K_DEPTH)
                fail_cnt = fail_cnt + 1;
        end
    end

end
endtask

////////////////////////////////////////////////////////////////////////////////
// CHECK RESULTS
//
// FIX 5: golden is Q5.7 (FL=7) stored integer -> divide by SCALE_GOLDEN=128
//        RTL   is Q5.11 (FL=11) -> already divided by SCALE_RTL=2048 above
////////////////////////////////////////////////////////////////////////////////

task check_results;
begin

    for (row = 0; row < ROWS; row = row + 1) begin

        // FIX 5: golden stored as Q5.7 12-bit integer, scale = 2^7 = 128
        exp_r = $itor(z_r_golden[row]) / SCALE_GOLDEN;
        exp_i = $itor(z_i_golden[row]) / SCALE_GOLDEN;

        err_r = got_r[row] - exp_r;
        err_i = got_i[row] - exp_i;

        if (err_r < 0.0) err_r = -err_r;
        if (err_i < 0.0) err_i = -err_i;

        if ((err_r > TOL) || (err_i > TOL)) begin

            $display(
                "FAIL test=%0d row=%0d  got=(%0.5f,%0.5f) exp=(%0.5f,%0.5f) err=(%0.5f,%0.5f)",
                test, row,
                got_r[row], got_i[row],
                exp_r, exp_i,
                err_r, err_i
            );

            fail_cnt = fail_cnt + 1;

        end else begin

            $display(
                "PASS test=%0d row=%0d  got=(%0.5f,%0.5f) exp=(%0.5f,%0.5f)",
                test, row,
                got_r[row], got_i[row],
                exp_r, exp_i
            );

            pass_cnt = pass_cnt + 1;

        end

    end

end
endtask

////////////////////////////////////////////////////////////////////////////////
// MAIN
////////////////////////////////////////////////////////////////////////////////

initial begin

    pass_cnt = 0;
    fail_cnt = 0;

    // ------------------------------------------------------------------------
    // OPEN FILES
    // ------------------------------------------------------------------------

    fid_hh_real = $fopen("rtl_vectors_conv_Z_Q1_11/hh_real.txt", "r");
    fid_hh_imag = $fopen("rtl_vectors_conv_Z_Q1_11/hh_imag.txt", "r");

    fid_y_real  = $fopen("rtl_vectors_conv_Z_Q1_11/y_real.txt",  "r");
    fid_y_imag  = $fopen("rtl_vectors_conv_Z_Q1_11/y_imag.txt",  "r");

    fid_z_real  = $fopen("rtl_vectors_conv_Z_Q1_11/z_real_golden.txt", "r");
    fid_z_imag  = $fopen("rtl_vectors_conv_Z_Q1_11/z_imag_golden.txt", "r");

    if (!fid_hh_real || !fid_hh_imag ||
        !fid_y_real  || !fid_y_imag  ||
        !fid_z_real  || !fid_z_imag) begin

        $display("ERROR: could not open one or more vector files");
        $finish;

    end

    $display("========================================");
    $display(" FILE-BASED SYSTOLIC ARRAY TESTBENCH");
    $display(" COLS=%0d  ROWS=%0d  K_DEPTH=%0d", COLS, ROWS, K_DEPTH);
    $display(" PIPE_LAT=%0d  NUM_TESTS=%0d", PIPE_LAT, NUM_TESTS);
    $display(" WL_IN=%0d  WL_OUT=%0d", WL_IN, WL_OUT);
    $display(" SCALE_RTL=%.0f (Q5.11)  SCALE_GOLDEN=%.0f (Q5.7)", SCALE_RTL, SCALE_GOLDEN);
    $display("========================================");

    // ------------------------------------------------------------------------
    // RESET
    // ------------------------------------------------------------------------

    apply_reset();

    // ------------------------------------------------------------------------
    // RUN TESTS
    // ------------------------------------------------------------------------

    for (test = 0; test < NUM_TESTS; test = test + 1) begin

        $display("");
        $display("----------------------------------------");
        $display("TEST %0d", test);
        $display("----------------------------------------");

        load_test_vectors();

        fork
            drive_inputs();
            collect_outputs();
        join

        check_results();

        // Reset pipeline state between tests so e_out starts at zero
        apply_reset();

    end

    // ------------------------------------------------------------------------
    // SUMMARY
    // ------------------------------------------------------------------------

    $display("");
    $display("========================================");
    $display("SUMMARY");
    $display("PASS = %0d / %0d", pass_cnt, NUM_TESTS * ROWS);
    $display("FAIL = %0d / %0d", fail_cnt, NUM_TESTS * ROWS);
    $display("========================================");

    if (fail_cnt == 0)
        $display("ALL TESTS PASSED");
    else
        $display("SOME TESTS FAILED");

    $fclose(fid_hh_real);
    $fclose(fid_hh_imag);
    $fclose(fid_y_real);
    $fclose(fid_y_imag);
    $fclose(fid_z_real);
    $fclose(fid_z_imag);

    $finish;

end

////////////////////////////////////////////////////////////////////////////////
// GLOBAL TIMEOUT
////////////////////////////////////////////////////////////////////////////////

initial begin
    #1000000;
    $display("GLOBAL TIMEOUT");
    $finish;
end

endmodule