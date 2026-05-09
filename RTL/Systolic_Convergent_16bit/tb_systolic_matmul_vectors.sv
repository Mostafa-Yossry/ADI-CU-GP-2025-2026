// =============================================================================
// tb_systolic_matmul_vectors.sv
// -----------------------------------------------------------------------------
// File-based RTL verification testbench for ŷ = H^H · y  (Matched Filter)
//
// MATLAB model reference:
//   T_Z = MULTIPLICATION_TYPES('fixed_point_Z_8x8', 16)   <-- length=16
//   Z_fixed = systolic_matmul_8_8__8_1_mex(HH, Y, T_Z)
//


`timescale 1ns/1ps

module tb_systolic_matmul_vectors;

////////////////////////////////////////////////////////////////////////////////
// PARAMETERS
////////////////////////////////////////////////////////////////////////////////

localparam ROWS    = 8;
localparam COLS    = 1;
localparam K_DEPTH = 8;

localparam WL_IN   = 12;
localparam WL_OUT  = 16;   

// Both RTL output and golden files are Q5.11:  scale = 2^11 = 2048
localparam real SCALE_RTL    = 2048.0;
localparam real SCALE_GOLDEN = 2048.0;

// Pipeline latency
localparam PIPE_LAT = (ROWS-1) + (COLS-1) + K_DEPTH + 1;  // 16

localparam NUM_TESTS  = 100;
localparam MAX_CYCLES = 300;

// TOL = 1 LSB of Q5.11 = 1/2048
localparam real TOL = 1.0 / 2048.0;

////////////////////////////////////////////////////////////////////////////////
// CLOCK / RESET
////////////////////////////////////////////////////////////////////////////////

reg clk = 0;
always #5 clk = ~clk;

reg rst_n;
reg en;
reg start;

integer cycle_counter;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cycle_counter <= 0;
    else
        cycle_counter <= cycle_counter + 1;
end

////////////////////////////////////////////////////////////////////////////////
// DUT INTERFACE
////////////////////////////////////////////////////////////////////////////////

reg signed [WL_IN-1:0]  hh_real [0:ROWS-1];
reg signed [WL_IN-1:0]  hh_imag [0:ROWS-1];
reg signed [WL_IN-1:0]  y_real  [0:COLS-1];
reg signed [WL_IN-1:0]  y_imag  [0:COLS-1];

wire signed [WL_OUT-1:0] yhat_real [0:ROWS-1][0:COLS-1];
wire signed [WL_OUT-1:0] yhat_imag [0:ROWS-1][0:COLS-1];
wire                      valid_out [0:ROWS-1][0:COLS-1];

////////////////////////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////////////////
// FILE HANDLES
////////////////////////////////////////////////////////////////////////////////

integer fid_hh_real, fid_hh_imag;
integer fid_y_real,  fid_y_imag;
integer fid_z_real,  fid_z_imag;

////////////////////////////////////////////////////////////////////////////////
// STORAGE
////////////////////////////////////////////////////////////////////////////////

integer hh_r_mem [0:ROWS-1][0:K_DEPTH-1];
integer hh_i_mem [0:ROWS-1][0:K_DEPTH-1];
integer y_r_mem  [0:K_DEPTH-1];
integer y_i_mem  [0:K_DEPTH-1];
integer z_r_golden [0:ROWS-1];
integer z_i_golden [0:ROWS-1];

real got_r [0:ROWS-1];
real got_i [0:ROWS-1];

integer valid_count [0:ROWS-1];
integer status;

////////////////////////////////////////////////////////////////////////////////
// VARIABLES
////////////////////////////////////////////////////////////////////////////////

integer test, row, k, r, tmp, idle;
integer pass_cnt, fail_cnt;
integer done_cnt, watchdog;
integer start_cycle;
real exp_r, exp_i, err_r, err_i;

////////////////////////////////////////////////////////////////////////////////
// RESET TASK
// Holds reset for 2 posedge clocks (async), then idles (ROWS+K_DEPTH)=16
// cycles after release — ensures all skew chains and valid_sr drain to zero
// before the next transaction's start pulse.
////////////////////////////////////////////////////////////////////////////////

task apply_reset;
begin
    rst_n = 0;
    en    = 1;
    start = 0;

    for (r = 0; r < ROWS; r = r + 1) begin
        hh_real[r] = 0;
        hh_imag[r] = 0;
    end
    y_real[0] = 0;
    y_imag[0] = 0;

    @(posedge clk);
    @(posedge clk);

    rst_n = 1;

    // Extended idle: (ROWS + K_DEPTH) cycles after release
    for (idle = 0; idle < (ROWS + K_DEPTH); idle = idle + 1)
        @(posedge clk);
end
endtask

////////////////////////////////////////////////////////////////////////////////
// LOAD TEST VECTORS
////////////////////////////////////////////////////////////////////////////////

task load_test_vectors;
begin
    // HH: 64 values per test, outer=k inner=row
    for (k = 0; k < K_DEPTH; k = k + 1) begin
        for (row = 0; row < ROWS; row = row + 1) begin
            status = $fscanf(fid_hh_real, "%d\n", tmp);
            hh_r_mem[row][k] = tmp;
            status = $fscanf(fid_hh_imag, "%d\n", tmp);
            hh_i_mem[row][k] = tmp;
        end
    end

    // Y: 8 values per test
    for (k = 0; k < K_DEPTH; k = k + 1) begin
        status = $fscanf(fid_y_real, "%d\n", tmp);
        y_r_mem[k] = tmp;
        status = $fscanf(fid_y_imag, "%d\n", tmp);
        y_i_mem[k] = tmp;
    end

    // Golden Z: 8 values per test (Q5.11 stored integers, 16-bit)
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
////////////////////////////////////////////////////////////////////////////////

task drive_inputs;
begin
    for (k = 0; k < K_DEPTH; k = k + 1) begin
        @(negedge clk);
        start = (k == 0) ? 1'b1 : 1'b0;
        for (r = 0; r < ROWS; r = r + 1) begin
            hh_real[r] = hh_r_mem[r][k];
            hh_imag[r] = hh_i_mem[r][k];
        end
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
// Captures the LAST valid pulse per row (overwrite on every pulse).
// done_cnt increments once per row when valid_count[row] reaches K_DEPTH.
// Each row's counting is gated on cycle_counter >= start_cycle + row so that
// tail pulses from the previous frame (which arrive before the new frame's
// wavefront reaches row gr) are not counted.
////////////////////////////////////////////////////////////////////////////////

task collect_outputs;
begin
    for (row = 0; row < ROWS; row = row + 1) begin
        valid_count[row] = 0;
        got_r[row]       = 0.0;
        got_i[row]       = 0.0;
    end

    done_cnt    = 0;
    watchdog    = 0;
    start_cycle = -1;

    while ((done_cnt < ROWS) && (watchdog < MAX_CYCLES)) begin
        @(posedge clk);
        #1;
        watchdog = watchdog + 1;

        // Capture start_cycle on the posedge after start is driven on negedge
        if (start && (start_cycle == -1))
            start_cycle = cycle_counter - 1;

        for (row = 0; row < ROWS; row = row + 1) begin
            // Gate: ignore valid_out until this row's frame wavefront arrives.
            // Row gr's first valid cannot precede start_cycle + gr (skew depth).
            // This prevents previous-frame tail pulses from being miscounted.
            if (valid_out[row][0] &&
                (start_cycle >= 0) &&
                (cycle_counter >= start_cycle + row)) begin

                got_r[row] = $itor($signed(yhat_real[row][0])) / SCALE_RTL;
                got_i[row] = $itor($signed(yhat_imag[row][0])) / SCALE_RTL;
                valid_count[row] = valid_count[row] + 1;
                if (valid_count[row] == K_DEPTH)
                    done_cnt = done_cnt + 1;
            end
        end
    end

    if (watchdog >= MAX_CYCLES) begin
        $display("TIMEOUT at test %0d (done_cnt=%0d)", test, done_cnt);
        for (row = 0; row < ROWS; row = row + 1)
            if (valid_count[row] < K_DEPTH)
                fail_cnt = fail_cnt + 1;
    end
end
endtask

////////////////////////////////////////////////////////////////////////////////
// CHECK RESULTS
// Golden files contain Q5.11 16-bit stored integers -> divide by SCALE_GOLDEN=2048
////////////////////////////////////////////////////////////////////////////////

task check_results;
begin
    for (row = 0; row < ROWS; row = row + 1) begin
        exp_r = $itor(z_r_golden[row]) / SCALE_GOLDEN;
        exp_i = $itor(z_i_golden[row]) / SCALE_GOLDEN;

        err_r = got_r[row] - exp_r;
        err_i = got_i[row] - exp_i;

        if (err_r < 0.0) err_r = -err_r;
        if (err_i < 0.0) err_i = -err_i;

        if ((err_r > TOL) || (err_i > TOL)) begin
            $display(
                "FAIL test=%0d row=%0d  got=(%0.6f,%0.6f) exp=(%0.6f,%0.6f) err=(%0.6f,%0.6f)",
                test, row,
                got_r[row], got_i[row],
                exp_r, exp_i,
                err_r, err_i
            );
            fail_cnt = fail_cnt + 1;
        end else begin
            $display(
                "PASS test=%0d row=%0d  got=(%0.6f,%0.6f) exp=(%0.6f,%0.6f)",
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

    fid_hh_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_real.txt", "r");
    fid_hh_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_imag.txt", "r");
    fid_y_real  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_real.txt",  "r");
    fid_y_imag  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_imag.txt",  "r");
    fid_z_real  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_real_golden.txt", "r");
    fid_z_imag  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_imag_golden.txt", "r");

    if (!fid_hh_real || !fid_hh_imag ||
        !fid_y_real  || !fid_y_imag  ||
        !fid_z_real  || !fid_z_imag) begin
        $display("ERROR: could not open vector files");
        $finish;
    end

    $display("========================================");
    $display(" FILE-BASED SYSTOLIC ARRAY TESTBENCH");
    $display(" COLS=%0d  ROWS=%0d  K_DEPTH=%0d", COLS, ROWS, K_DEPTH);
    $display(" PIPE_LAT=%0d  NUM_TESTS=%0d", PIPE_LAT, NUM_TESTS);
    $display(" WL_IN=%0d  WL_OUT=%0d  (Q5.11)", WL_IN, WL_OUT);
    $display(" SCALE=%.0f  TOL=%.6f", SCALE_RTL, TOL);
    $display("========================================");

    apply_reset();

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
    end

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

    $fclose(fid_hh_real); $fclose(fid_hh_imag);
    $fclose(fid_y_real);  $fclose(fid_y_imag);
    $fclose(fid_z_real);  $fclose(fid_z_imag);

    $finish;
end

initial begin
    #10000000;
    $display("GLOBAL TIMEOUT");
    $finish;
end

endmodule