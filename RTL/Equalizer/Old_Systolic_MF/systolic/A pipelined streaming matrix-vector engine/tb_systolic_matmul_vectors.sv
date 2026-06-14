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
//   Z = H^H * Y
//
// DUT formats:
//   Inputs  : Q1.11  (12-bit)
//   Outputs : Q5.11  (16-bit)
//
// -----------------------------------------------------------------------------
// FILE FORMAT
//
// hh_real / hh_imag:
//   64 values per test
//   ordered as:
//
//      k=0,row=0
//      k=0,row=1
//      ...
//      k=0,row=7
//
//      k=1,row=0
//      ...
//
// y_real / y_imag:
//   8 values per test
//
// z_real_golden / z_imag_golden:
//   8 values per test
//
// -----------------------------------------------------------------------------
// PIPELINE LATENCY
//
// pipe_latency = (ROWS-1) + (COLS-1) + K_DEPTH + 1
//               = 23 cycles
//
// =============================================================================

`timescale 1ns/1ps

module tb_systolic_matmul_vectors;

////////////////////////////////////////////////////////////////////////////////
// PARAMETERS
////////////////////////////////////////////////////////////////////////////////

localparam ROWS    = 8;
localparam COLS    = 8;
localparam K_DEPTH = 8;

localparam WL_IN   = 12;
localparam WL_OUT  = 16;

localparam SCALE_OUT = 2048.0;

localparam PIPE_LAT = (ROWS-1) + (COLS-1) + K_DEPTH + 1;

localparam NUM_TESTS = 100;

localparam MAX_CYCLES = 200;

localparam real TOL = 0.01;

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

integer y_r_mem [0:K_DEPTH-1];
integer y_i_mem [0:K_DEPTH-1];

integer z_r_golden [0:ROWS-1];
integer z_i_golden [0:ROWS-1];

real got_r [0:ROWS-1];
real got_i [0:ROWS-1];

integer valid_seen [0:ROWS-1];
integer status;

////////////////////////////////////////////////////////////////////////////////
// VARIABLES
////////////////////////////////////////////////////////////////////////////////

integer test;
integer row;
integer k;

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
    // HH
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
    // Y
    // ------------------------------------------------------------------------

    for (k = 0; k < K_DEPTH; k = k + 1) begin

        status = $fscanf(fid_y_real, "%d\n", tmp);
        y_r_mem[k] = tmp;

        status = $fscanf(fid_y_imag, "%d\n", tmp);
        y_i_mem[k] = tmp;

    end

    // ------------------------------------------------------------------------
    // GOLDEN Z
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
////////////////////////////////////////////////////////////////////////////////

task drive_inputs;

integer r;

begin

    // ------------------------------------------------------------------------
    // Load constant Y
    // ------------------------------------------------------------------------

    @(negedge clk);

    for (r = 0; r < COLS; r = r + 1) begin

        y_real[r] = y_r_mem[r];
        y_imag[r] = y_i_mem[r];

    end

    // ------------------------------------------------------------------------
    // Stream H^H columns
    // ------------------------------------------------------------------------

    for (k = 0; k < K_DEPTH; k = k + 1) begin

        @(negedge clk);

        start = (k == 0);

        for (r = 0; r < ROWS; r = r + 1) begin

            hh_real[r] = hh_r_mem[r][k];
            hh_imag[r] = hh_i_mem[r][k];

        end

    end

    @(negedge clk);

    start = 0;

    for (r = 0; r < ROWS; r = r + 1) begin

        hh_real[r] = 0;
        hh_imag[r] = 0;
    end

end
endtask

////////////////////////////////////////////////////////////////////////////////
// COLLECT OUTPUTS
////////////////////////////////////////////////////////////////////////////////

task collect_outputs;

begin

    for (row = 0; row < ROWS; row = row + 1) begin

        valid_seen[row] = 0;

        got_r[row] = 0.0;
        got_i[row] = 0.0;

    end

    done_cnt = 0;
    watchdog = 0;

    while ((done_cnt < ROWS) && (watchdog < MAX_CYCLES)) begin

        @(posedge clk);
        #1;

        watchdog = watchdog + 1;

        for (row = 0; row < ROWS; row = row + 1) begin

            if (valid_out[row][COLS-1] && !valid_seen[row]) begin

                valid_seen[row] = 1;

                got_r[row] =
                    $itor($signed(yhat_real[row][COLS-1])) / SCALE_OUT;

                got_i[row] =
                    $itor($signed(yhat_imag[row][COLS-1])) / SCALE_OUT;

                done_cnt = done_cnt + 1;

            end

        end

    end

    if (watchdog >= MAX_CYCLES) begin

        $display("TIMEOUT waiting for outputs");
        fail_cnt = fail_cnt + ROWS;

    end

end
endtask

////////////////////////////////////////////////////////////////////////////////
// CHECK RESULTS
////////////////////////////////////////////////////////////////////////////////

task check_results;

begin

    for (row = 0; row < ROWS; row = row + 1) begin

        exp_r = z_r_golden[row] / SCALE_OUT;
        exp_i = z_i_golden[row] / SCALE_OUT;

        err_r = got_r[row] - exp_r;
        err_i = got_i[row] - exp_i;

        if (err_r < 0) err_r = -err_r;
        if (err_i < 0) err_i = -err_i;

        if ((err_r > TOL) || (err_i > TOL)) begin

            $display(
                "FAIL test=%0d row=%0d  got=(%0.5f,%0.5f) exp=(%0.5f,%0.5f)",
                test,
                row,
                got_r[row],
                got_i[row],
                exp_r,
                exp_i
            );

            fail_cnt = fail_cnt + 1;

        end
        else begin

            $display(
                "PASS test=%0d row=%0d  got=(%0.5f,%0.5f)",
                test,
                row,
                got_r[row],
                got_i[row]
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

    fid_hh_real = $fopen("rtl_vectors_Z_Q1_11/hh_real.txt", "r");
    fid_hh_imag = $fopen("rtl_vectors_Z_Q1_11/hh_imag.txt", "r");

    fid_y_real  = $fopen("rtl_vectors_Z_Q1_11/y_real.txt", "r");
    fid_y_imag  = $fopen("rtl_vectors_Z_Q1_11/y_imag.txt", "r");

    fid_z_real  = $fopen("rtl_vectors_Z_Q1_11/z_real_golden.txt", "r");
    fid_z_imag  = $fopen("rtl_vectors_Z_Q1_11/z_imag_golden.txt", "r");

    if (!fid_hh_real || !fid_hh_imag ||
        !fid_y_real  || !fid_y_imag  ||
        !fid_z_real  || !fid_z_imag) begin

        $display("ERROR opening vector files");
        $finish;

    end

    $display("========================================");
    $display(" FILE-BASED SYSTOLIC ARRAY TESTBENCH");
    $display(" NUM_TESTS = %0d", NUM_TESTS);
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

        apply_reset();

        repeat (PIPE_LAT) @(posedge clk);

    end

    // ------------------------------------------------------------------------
    // SUMMARY
    // ------------------------------------------------------------------------

    $display("");
    $display("========================================");
    $display("SUMMARY");
    $display("PASS = %0d", pass_cnt);
    $display("FAIL = %0d", fail_cnt);
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