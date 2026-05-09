// =============================================================================
// tb_matched_filter_pipe_bb.sv
// -----------------------------------------------------------------------------
// Back-to-back pipeline burst testbench for matched_filter_pipe.
//
// Architecture: THREE concurrent initial blocks
//   MAIN      : reset, load vectors, wait for collector, then print report
//   INJECTOR  : fires NUM_TESTS valid_in pulses back-to-back, 1 per cycle
//   COLLECTOR : runs in parallel, captures every valid_out as it arrives
//
// WHY concurrent?
//   With PIPE_LAT=4, valid_out[0] arrives at vin[0]+4 cycles — while the
//   injector is still driving frames 4..19.  A sequential drain-after-burst
//   would miss every early output.  The collector must run simultaneously.
//
// H^H timing correctness:
//   hh_load[N] must be registered ONE cycle BEFORE valid_in[N].
//   Both use non-blocking assignments; the Stage-1 multipliers (combinational
//   wires) see the OLD coef values on the posedge that hh_load fires.
//
//   Fix: "overlap" scheme —
//     P_pre : hh_load[0] only  (no valid_in)   -> coefs[0] into registers
//     P0    : valid_in[0] + hh_load[1]          -> stage1 uses coefs[0] OK
//     P1    : valid_in[1] + hh_load[2]          -> stage1 uses coefs[1] OK
//     ...
//     P19   : valid_in[19] + hh_load=0          -> stage1 uses coefs[19] OK
//
//   All signals are driven on the NEGEDGE preceding each posedge.
//
// Expected results:
//   vin_cycle  = 5,6,7,...,24   (consecutive 1/cycle)
//   vout_cycle = 9,10,...,28    (exactly PIPE_LAT=4 behind each vin)
//   Latency    = 4 for every frame
//   Throughput = 1.00 outputs/cycle
// =============================================================================

`timescale 1ns/1ps

module tb_matched_filter_pipe_bb;

localparam ROWS      = 8;
localparam K         = 8;
localparam WL_IN     = 12;
localparam WL_OUT    = 16;
localparam PIPE_LAT  = 4;
localparam NUM_TESTS = 20;

localparam real SCALE = 2048.0;
localparam real TOL   = 1.0 / 2048.0;

// ---------------------------------------------------------------------------
// Clock and global cycle counter
// ---------------------------------------------------------------------------
reg clk = 0;
always #5 clk = ~clk;

reg     rst_n, en;
integer cycle_counter;
always @(posedge clk or negedge rst_n)
    if (!rst_n) cycle_counter <= 0;
    else        cycle_counter <= cycle_counter + 1;

// ---------------------------------------------------------------------------
// DUT ports
// ---------------------------------------------------------------------------
reg                      hh_load;
reg signed [WL_IN-1:0]  hh_real [0:ROWS-1][0:K-1];
reg signed [WL_IN-1:0]  hh_imag [0:ROWS-1][0:K-1];
reg                      valid_in;
reg signed [WL_IN-1:0]  y_real  [0:K-1];
reg signed [WL_IN-1:0]  y_imag  [0:K-1];

wire                      valid_out;
wire signed [WL_OUT-1:0] yhat_real [0:ROWS-1];
wire signed [WL_OUT-1:0] yhat_imag [0:ROWS-1];

// ---------------------------------------------------------------------------
// DUT
// ---------------------------------------------------------------------------
matched_filter_pipe #(
    .ROWS(ROWS), .K(K), .WL_IN(WL_IN), .WL_INT(16), .WL_OUT(WL_OUT)
) dut (
    .clk(clk), .rst_n(rst_n), .en(en),
    .hh_load(hh_load), .hh_real(hh_real), .hh_imag(hh_imag),
    .valid_in(valid_in), .y_real(y_real), .y_imag(y_imag),
    .valid_out(valid_out), .yhat_real(yhat_real), .yhat_imag(yhat_imag)
);

// ---------------------------------------------------------------------------
// Shared memory
// ---------------------------------------------------------------------------
integer hh_r_mem [0:NUM_TESTS-1][0:ROWS-1][0:K-1];
integer hh_i_mem [0:NUM_TESTS-1][0:ROWS-1][0:K-1];
integer y_r_mem  [0:NUM_TESTS-1][0:K-1];
integer y_i_mem  [0:NUM_TESTS-1][0:K-1];
integer z_r_gold [0:NUM_TESTS-1][0:ROWS-1];
integer z_i_gold [0:NUM_TESTS-1][0:ROWS-1];

integer vin_cycle  [0:NUM_TESTS-1];
integer vout_cycle [0:NUM_TESTS-1];
real    got_r      [0:NUM_TESTS-1][0:ROWS-1];
real    got_i      [0:NUM_TESTS-1][0:ROWS-1];

// Synchronisation flags
reg vectors_ready;
reg collect_done;

// ===========================================================================
// PROCESS 1 — MAIN  (reset, load vectors, report)
// ===========================================================================
integer fid_hh_real, fid_hh_imag, fid_y_real, fid_y_imag, fid_z_real, fid_z_imag;
integer t, row, k, r, tmp, status;
integer pass_cnt, fail_cnt, lat_min, lat_max, lat_sum, lat_count;
real    exp_r, exp_i, err_r, err_i;

initial begin
    vectors_ready = 0;
    collect_done  = 0;
    pass_cnt = 0; fail_cnt = 0;
    lat_min = 32767; lat_max = 0; lat_sum = 0; lat_count = 0;

    fid_hh_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_real.txt","r");
    fid_hh_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_imag.txt","r");
    fid_y_real  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_real.txt", "r");
    fid_y_imag  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_imag.txt", "r");
    fid_z_real  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_real_golden.txt","r");
    fid_z_imag  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_imag_golden.txt","r");

    if (!fid_hh_real || !fid_hh_imag || !fid_y_real ||
        !fid_y_imag  || !fid_z_real  || !fid_z_imag) begin
        $display("ERROR: could not open vector files"); $finish;
    end

    // Reset sequence
    rst_n = 0; en = 1; hh_load = 0; valid_in = 0;
    for (r=0; r<ROWS; r=r+1) begin hh_real[r][0]=0; hh_imag[r][0]=0; end
    for (k=0; k<K; k=k+1)    begin y_real[k]=0; y_imag[k]=0; end
    repeat(2) @(posedge clk);
    rst_n = 1;
    repeat(4) @(posedge clk);   // pipeline settle after reset

    // Load all test vectors
    begin : load_vecs
        integer kk;
        for (t=0; t<NUM_TESTS; t=t+1) begin
            for (kk=0; kk<K; kk=kk+1)
                for (row=0; row<ROWS; row=row+1) begin
                    status=$fscanf(fid_hh_real,"%d\n",tmp); hh_r_mem[t][row][kk]=tmp;
                    status=$fscanf(fid_hh_imag,"%d\n",tmp); hh_i_mem[t][row][kk]=tmp;
                end
            for (kk=0; kk<K; kk=kk+1) begin
                status=$fscanf(fid_y_real,"%d\n",tmp); y_r_mem[t][kk]=tmp;
                status=$fscanf(fid_y_imag,"%d\n",tmp); y_i_mem[t][kk]=tmp;
            end
            for (row=0; row<ROWS; row=row+1) begin
                status=$fscanf(fid_z_real,"%d\n",tmp); z_r_gold[t][row]=tmp;
                status=$fscanf(fid_z_imag,"%d\n",tmp); z_i_gold[t][row]=tmp;
            end
        end
    end
    vectors_ready = 1;   // release injector and collector

    // Wait for collector to finish
    wait(collect_done);

    // =====================================================================
    // REPORT
    // =====================================================================
    $display("");
    $display("========================================================");
    $display(" MATCHED FILTER - BACK-TO-BACK BURST TB");
    $display(" ROWS=%0d  K=%0d  PIPE_LAT=%0d  NUM_TESTS=%0d",
             ROWS, K, PIPE_LAT, NUM_TESTS);
    $display(" TOL=%.6f  (half LSB in Q5.11)", TOL);
    $display("========================================================");
    $display("");
    $display("  PIPELINE TIMING TABLE");
    $display("  %-6s  %-12s  %-12s  %-s",
             "Frame","vin_cycle","vout_cycle","Latency");
    $display("  --------------------------------------------------------");

    for (t=0; t<NUM_TESTS; t=t+1) begin : report_loop
        integer lat;
        lat = vout_cycle[t] - vin_cycle[t];
        $display("  %-6d  %-12d  %-12d  %0d cycles%s",
            t, vin_cycle[t], vout_cycle[t], lat,
            (lat==PIPE_LAT) ? "  OK" : "  *** WRONG ***");
        if (lat<lat_min) lat_min=lat;
        if (lat>lat_max) lat_max=lat;
        lat_sum   = lat_sum + lat;
        lat_count = lat_count + 1;
    end

    $display("");
    $display("  THROUGHPUT");
    $display("  First valid_in  : cycle %0d", vin_cycle[0]);
    $display("  Last valid_out  : cycle %0d", vout_cycle[NUM_TESTS-1]);
    $display("  Outputs/cycle   : %.2f  (ideal=1.00)",
        $itor(NUM_TESTS) /
        $itor(vout_cycle[NUM_TESTS-1] - vin_cycle[0] + 1));

    $display("");
    $display("========================================================");
    $display("  FUNCTIONAL RESULTS");
    $display("========================================================");

    for (t=0; t<NUM_TESTS; t=t+1) begin : func_loop
        integer lat2;
        lat2 = vout_cycle[t] - vin_cycle[t];
        $display("");
        $display("  --- Frame %0d  vin=%0d  vout=%0d  lat=%0d ---",
                 t, vin_cycle[t], vout_cycle[t], lat2);
        $display("  %-5s  %-30s  %-s","Row","Output (real, imag)","Status");

        for (row=0; row<ROWS; row=row+1) begin
            exp_r = $itor(z_r_gold[t][row]) / SCALE;
            exp_i = $itor(z_i_gold[t][row]) / SCALE;
            err_r = got_r[t][row]-exp_r; if(err_r<0.0) err_r=-err_r;
            err_i = got_i[t][row]-exp_i; if(err_i<0.0) err_i=-err_i;
            if ((err_r>TOL)||(err_i>TOL)) begin
                $display("  %-5d  (%9.6f, %9.6f)          FAIL err=(%.4f,%.4f)",
                    row,got_r[t][row],got_i[t][row],err_r,err_i);
                fail_cnt=fail_cnt+1;
            end else begin
                $display("  %-5d  (%9.6f, %9.6f)          PASS",
                    row,got_r[t][row],got_i[t][row]);
                pass_cnt=pass_cnt+1;
            end
        end
    end

    $display("");
    $display("========================================================");
    $display("  GLOBAL LATENCY SUMMARY (%0d frames)", lat_count);
    $display("  Min latency  : %0d cycles", lat_min);
    $display("  Max latency  : %0d cycles", lat_max);
    $display("  Mean latency : %.2f cycles", $itor(lat_sum)/$itor(lat_count));
    $display("  Expected     : %0d cycles (fixed pipeline depth)", PIPE_LAT);
    $display("========================================================");
    $display("  FUNCTIONAL SUMMARY");
    $display("  PASS = %0d / %0d", pass_cnt, NUM_TESTS*ROWS);
    $display("  FAIL = %0d / %0d", fail_cnt, NUM_TESTS*ROWS);
    $display("========================================================");
    if (fail_cnt==0) $display("  ALL TESTS PASSED");
    else             $display("  SOME TESTS FAILED");

    $fclose(fid_hh_real); $fclose(fid_hh_imag);
    $fclose(fid_y_real);  $fclose(fid_y_imag);
    $fclose(fid_z_real);  $fclose(fid_z_imag);
    $finish;
end

// ===========================================================================
// PROCESS 2 — INJECTOR
// ===========================================================================
integer inj_test, inj_row, inj_k;

initial begin
    wait(vectors_ready);

    $display(">>> INJECTOR start  (pre-load frame 0 H^H)");

    // Pre-load cycle: drive frame 0 H^H, no valid_in
    @(negedge clk);
    for (inj_row=0; inj_row<ROWS; inj_row=inj_row+1)
        for (inj_k=0; inj_k<K; inj_k=inj_k+1) begin
            hh_real[inj_row][inj_k] = hh_r_mem[0][inj_row][inj_k];
            hh_imag[inj_row][inj_k] = hh_i_mem[0][inj_row][inj_k];
        end
    hh_load  = 1;
    valid_in = 0;
    @(posedge clk);   // coefs[0] now registered

    $display(">>> INJECTOR firing %0d frames...", NUM_TESTS);
    $display("");
    $display("  %-6s  %-12s  %-s","Frame","vin_cycle","Pipeline occupancy");
    $display("  -------------------------------------------------------");

    for (inj_test=0; inj_test<NUM_TESTS; inj_test=inj_test+1) begin

        // Set up signals on negedge so they are stable at next posedge
        @(negedge clk);

        // Drive y for this frame
        for (inj_k=0; inj_k<K; inj_k=inj_k+1) begin
            y_real[inj_k] = y_r_mem[inj_test][inj_k];
            y_imag[inj_k] = y_i_mem[inj_test][inj_k];
        end
        valid_in = 1;

        // Overlap: pre-load NEXT frame's H^H on this same negedge
        // so it is registered at this posedge, ready for next valid_in
        if (inj_test+1 < NUM_TESTS) begin
            for (inj_row=0; inj_row<ROWS; inj_row=inj_row+1)
                for (inj_k=0; inj_k<K; inj_k=inj_k+1) begin
                    hh_real[inj_row][inj_k] = hh_r_mem[inj_test+1][inj_row][inj_k];
                    hh_imag[inj_row][inj_k] = hh_i_mem[inj_test+1][inj_row][inj_k];
                end
            hh_load = 1;
        end else begin
            hh_load = 0;
        end

        // Posedge: DUT latches y[inj_test] x coefs[inj_test]
        @(posedge clk);
        vin_cycle[inj_test] = cycle_counter;

        // Print fill indicator
        begin : fill_disp
            integer stage, sf;
            sf = (inj_test+1 < PIPE_LAT) ? (inj_test+1) : PIPE_LAT;
            $write("  %-6d  %-12d  [", inj_test, vin_cycle[inj_test]);
            for (stage=0; stage<PIPE_LAT; stage=stage+1) begin
                $write("%s",(stage<sf)?"##":"  ");
                if (stage<PIPE_LAT-1) $write("|");
            end
            if (inj_test+1 >= PIPE_LAT)
                $display("]  PIPELINE FULL - 1 output/cycle");
            else
                $display("]  filling (%0d/%0d)", sf, PIPE_LAT);
        end
    end

    // De-assert after last frame
    @(negedge clk);
    valid_in=0; hh_load=0;
    for (inj_k=0; inj_k<K; inj_k=inj_k+1) begin
        y_real[inj_k]=0; y_imag[inj_k]=0;
    end

    $display("");
    $display(">>> INJECTOR done. vin[0]=%0d  vin[%0d]=%0d",
             vin_cycle[0], NUM_TESTS-1, vin_cycle[NUM_TESTS-1]);
end

// ===========================================================================
// PROCESS 3 — COLLECTOR  (concurrent with injector)
// ===========================================================================
integer col_idx, col_row;

initial begin
    wait(vectors_ready);

    col_idx = 0;
    // Poll every posedge; capture each valid_out immediately
    while (col_idx < NUM_TESTS) begin
        @(posedge clk);
        if (valid_out === 1'b1) begin
            vout_cycle[col_idx] = cycle_counter;
            for (col_row=0; col_row<ROWS; col_row=col_row+1) begin
                got_r[col_idx][col_row] =
                    $itor($signed(yhat_real[col_row])) / SCALE;
                got_i[col_idx][col_row] =
                    $itor($signed(yhat_imag[col_row])) / SCALE;
            end
            col_idx = col_idx + 1;
        end
    end

    $display(">>> COLLECTOR done. vout[0]=%0d  vout[%0d]=%0d",
             vout_cycle[0], NUM_TESTS-1, vout_cycle[NUM_TESTS-1]);
    collect_done = 1;
end

// ===========================================================================
// Global timeout
// ===========================================================================
initial begin
    #10_000_000;
    $display("GLOBAL TIMEOUT"); $finish;
end

endmodule