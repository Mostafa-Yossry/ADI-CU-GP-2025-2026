// =============================================================================
// tb_systolic_matmul_latency.sv
// -----------------------------------------------------------------------------
// FILE-BASED TESTBENCH + AUTOMATIC LATENCY MEASUREMENT
//
// ARCHITECTURE UNDER TEST
// -----------------------
//
//   - H^H streamed temporally
//   - y spatially distributed and held constant
//   - rightward systolic accumulation
//
// Computes:
//
//      yhat = H^H * y
//
// -----------------------------------------------------------------------------
// FEATURES
// -----------------------------------------------------------------------------
//
//   1. Loads MATLAB-generated vectors
//   2. Verifies numerical correctness
//   3. Automatically measures REAL RTL latency
//   4. Reports:
//        - first valid latency
//        - last valid latency
//        - per-row valid timing
//
// =============================================================================

`timescale 1ns/1ps

module tb_systolic_matmul_latency;

////////////////////////////////////////////////////////////////////////////////
// PARAMETERS
////////////////////////////////////////////////////////////////////////////////

localparam ROWS    = 8;
localparam COLS    = 8;
localparam K_DEPTH = 8;

localparam WL_IN   = 12;
localparam WL_INT  = 16;
localparam WL_OUT  = 16;

localparam NUM_TESTS = 1;

localparam SCALE_OUT = 2048.0;

localparam real TOL = 0.01;

localparam MAX_CYCLES = 1000;

////////////////////////////////////////////////////////////////////////////////
// CLOCK
////////////////////////////////////////////////////////////////////////////////

reg clk = 0;

always #5 clk = ~clk;

////////////////////////////////////////////////////////////////////////////////
// DUT CONTROL
////////////////////////////////////////////////////////////////////////////////

reg rst_n;
reg en;
reg start;

////////////////////////////////////////////////////////////////////////////////
// GLOBAL CYCLE COUNTER
////////////////////////////////////////////////////////////////////////////////

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

reg signed [WL_IN-1:0]
    hh_real [0:ROWS-1];

reg signed [WL_IN-1:0]
    hh_imag [0:ROWS-1];

reg signed [WL_IN-1:0]
    y_real [0:COLS-1];

reg signed [WL_IN-1:0]
    y_imag [0:COLS-1];

wire signed [WL_OUT-1:0]
    yhat_real [0:ROWS-1][0:COLS-1];

wire signed [WL_OUT-1:0]
    yhat_imag [0:ROWS-1][0:COLS-1];

wire valid_out [0:ROWS-1][0:COLS-1];

////////////////////////////////////////////////////////////////////////////////
// DUT
////////////////////////////////////////////////////////////////////////////////

systolic_matmul #(
    .ROWS    (ROWS),
    .COLS    (COLS),
    .K_DEPTH (K_DEPTH),
    .WL_IN   (WL_IN),
    .WL_INT  (WL_INT),
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
// VECTOR STORAGE
////////////////////////////////////////////////////////////////////////////////

integer hh_r_mem [0:ROWS-1][0:K_DEPTH-1];
integer hh_i_mem [0:ROWS-1][0:K_DEPTH-1];

integer y_r_mem [0:K_DEPTH-1];
integer y_i_mem [0:K_DEPTH-1];

integer z_r_golden [0:ROWS-1];
integer z_i_golden [0:ROWS-1];

////////////////////////////////////////////////////////////////////////////////
// OUTPUT STORAGE
////////////////////////////////////////////////////////////////////////////////

real got_r [0:ROWS-1];
real got_i [0:ROWS-1];

integer valid_seen [0:ROWS-1];

////////////////////////////////////////////////////////////////////////////////
// LATENCY STORAGE
////////////////////////////////////////////////////////////////////////////////

integer start_cycle;

integer first_valid_cycle;
integer last_valid_cycle;

integer first_latency;
integer total_latency;

integer row_valid_cycle [0:ROWS-1];

integer first_valid_seen;

////////////////////////////////////////////////////////////////////////////////
// VARIABLES
////////////////////////////////////////////////////////////////////////////////

integer test;
integer row;
integer k;
integer r;

integer tmp;
integer status;

integer done_cnt;
integer watchdog;

integer pass_cnt;
integer fail_cnt;

real exp_r;
real exp_i;

real err_r;
real err_i;

////////////////////////////////////////////////////////////////////////////////
// RESET
////////////////////////////////////////////////////////////////////////////////

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

begin

    // ------------------------------------------------------------------------
    // PRELOAD SPATIAL Y
    // ------------------------------------------------------------------------

    @(negedge clk);

    for (r = 0; r < COLS; r = r + 1) begin

        y_real[r] = y_r_mem[r];
        y_imag[r] = y_i_mem[r];

    end

    // ------------------------------------------------------------------------
    // STREAM HH COLUMNS
    // ------------------------------------------------------------------------

    for (k = 0; k < K_DEPTH; k = k + 1) begin

        @(negedge clk);

        start = (k == 0);

        if (k == 0) begin

            start_cycle = cycle_counter;

            $display("");
            $display("START asserted at cycle %0d", start_cycle);

        end

        for (r = 0; r < ROWS; r = r + 1) begin

            hh_real[r] = hh_r_mem[r][k];
            hh_imag[r] = hh_i_mem[r][k];

        end

    end

    // ------------------------------------------------------------------------
    // CLEAR HH
    // ------------------------------------------------------------------------

    @(negedge clk);

    start = 0;

    for (r = 0; r < ROWS; r = r + 1) begin

        hh_real[r] = 0;
        hh_imag[r] = 0;

    end

end

endtask

////////////////////////////////////////////////////////////////////////////////
// COLLECT OUTPUTS + LATENCY
////////////////////////////////////////////////////////////////////////////////

task collect_outputs;

begin

    done_cnt = 0;
    watchdog = 0;

    first_valid_seen = 0;

    first_valid_cycle = -1;
    last_valid_cycle  = -1;

    first_latency = -1;
    total_latency = -1;

    for (row = 0; row < ROWS; row = row + 1) begin

        valid_seen[row] = 0;

        got_r[row] = 0.0;
        got_i[row] = 0.0;

        row_valid_cycle[row] = -1;

    end

    while ((done_cnt < ROWS) && (watchdog < MAX_CYCLES)) begin

        @(posedge clk);
        #1;

        watchdog = watchdog + 1;

        for (row = 0; row < ROWS; row = row + 1) begin

            if (valid_out[row][COLS-1] &&
                !valid_seen[row]) begin

                valid_seen[row] = 1;

                row_valid_cycle[row] = cycle_counter;

                // ------------------------------------------------------------
                // FIRST VALID
                // ------------------------------------------------------------

                if (!first_valid_seen) begin

                    first_valid_seen = 1;

                    first_valid_cycle = cycle_counter;

                    first_latency =
                        first_valid_cycle - start_cycle;

                end

                // ------------------------------------------------------------
                // LAST VALID
                // ------------------------------------------------------------

                last_valid_cycle = cycle_counter;

                total_latency =
                    last_valid_cycle - start_cycle;

                // ------------------------------------------------------------
                // STORE OUTPUT
                // ------------------------------------------------------------

                got_r[row] =
                    $itor(
                        $signed(yhat_real[row][COLS-1])
                    ) / SCALE_OUT;

                got_i[row] =
                    $itor(
                        $signed(yhat_imag[row][COLS-1])
                    ) / SCALE_OUT;

                done_cnt = done_cnt + 1;

                $display(
                    "VALID row=%0d cycle=%0d",
                    row,
                    cycle_counter
                );

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
                "FAIL row=%0d got=(%0.5f,%0.5f) exp=(%0.5f,%0.5f)",
                row,
                got_r[row],
                got_i[row],
                exp_r,
                exp_i
            );

            fail_cnt = fail_cnt + 1;

        end
        else begin

            pass_cnt = pass_cnt + 1;

        end

    end

end

endtask

////////////////////////////////////////////////////////////////////////////////
// PRINT LATENCY REPORT
////////////////////////////////////////////////////////////////////////////////

task print_latency_report;

begin

    $display("");
    $display("================================================");
    $display("LATENCY REPORT");
    $display("================================================");

    $display("Start cycle          : %0d", start_cycle);

    $display("First valid cycle    : %0d",
             first_valid_cycle);

    $display("Last valid cycle     : %0d",
             last_valid_cycle);

    $display("");

    $display("First output latency : %0d cycles",
             first_latency);

    $display("Full frame latency   : %0d cycles",
             total_latency);

    $display("");

    for (row = 0; row < ROWS; row = row + 1) begin

        $display(
            "Row %0d valid cycle   : %0d",
            row,
            row_valid_cycle[row]
        );

    end

    $display("================================================");
    $display("");

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

    fid_hh_real = $fopen(
        "rtl_vectors_Z_Q1_11/hh_real.txt", "r");

    fid_hh_imag = $fopen(
        "rtl_vectors_Z_Q1_11/hh_imag.txt", "r");

    fid_y_real = $fopen(
        "rtl_vectors_Z_Q1_11/y_real.txt", "r");

    fid_y_imag = $fopen(
        "rtl_vectors_Z_Q1_11/y_imag.txt", "r");

    fid_z_real = $fopen(
        "rtl_vectors_Z_Q1_11/z_real_golden.txt", "r");

    fid_z_imag = $fopen(
        "rtl_vectors_Z_Q1_11/z_imag_golden.txt", "r");

    if (!fid_hh_real || !fid_hh_imag ||
        !fid_y_real  || !fid_y_imag  ||
        !fid_z_real  || !fid_z_imag) begin

        $display("ERROR opening vector files");
        $finish;

    end

    $display("");
    $display("========================================");
    $display("AUTOMATIC LATENCY MEASUREMENT TESTBENCH");
    $display("========================================");

    apply_reset();

    // ------------------------------------------------------------------------
    // RUN FIRST TEST ONLY
    // ------------------------------------------------------------------------

    test = 0;

    load_test_vectors();

    fork
        drive_inputs();
        collect_outputs();
    join

    check_results();

    print_latency_report();

    $display("");
    $display("PASS = %0d", pass_cnt);
    $display("FAIL = %0d", fail_cnt);

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