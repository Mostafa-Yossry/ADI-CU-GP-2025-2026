// =============================================================================
// tb_hermitian_mf_chain.sv
// -----------------------------------------------------------------------------
// Self-checking integration testbench for hermitian_mf_chain.
//
// Tests the full chain:  H → hermitian_pipe → H^H → MF → g_y = H^H·y
//
// Suite 0 — Identity/diagonal sanity (single shot, H = 0.5·I)
// Suite 1 — All-real diagonal, verifies imag outputs == 0
// Suite 2 — File-based golden burst (100 frames, requires testbench_files2/)
// =============================================================================

`timescale 1ns/1ps

module tb_hermitian_mf_chain;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
localparam int  N          = 8;
localparam int  WL_IN      = 12;
localparam int  FL_IN      = 11;
localparam int  INT_BITS   = 0;
localparam int  MF_WL_W    = 16;
localparam int  MF_FL_W    = 15;
localparam int  MF_WL_PROD = 32;
localparam int  MF_FL_PROD = 30;
localparam int  MF_FL_Q2   = 14;
localparam int  MF_FL_Q3   = 13;
localparam int  MF_FL_Q4   = 12;
localparam int  MF_FL_Q5   = 11;
localparam int  MF_WL_OUT  = 16;
localparam int  MF_FL_OUT  = 11;
localparam bit  HERM_REG   = 1;

localparam int  HERM_LAT   = HERM_REG ? 1 : 0;
localparam int  MF_LAT     = 10;
localparam int  CHAIN_LAT  = HERM_LAT + 2 + MF_LAT; // 13

localparam int  CLK_PERIOD = 10;
localparam int  NUM_FRAMES = 100;

// Suite 0 expected value (0.5 * 0.5 = 0.25 in Q1.11 = 512)
localparam int  S0_EXP     = 512;
// Suite 0 drive value (0.5 in Q1.11 = 1024)
localparam int  S0_HALF    = 1024;

localparam string FILE_DIR = "testbench_files2/";

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------
logic clk;
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---------------------------------------------------------------------------
// DUT ports
// ---------------------------------------------------------------------------
logic                           rst_n;
logic                           en;
logic                           h_valid;
logic signed [WL_IN-1:0]        h_real_arr [0:N-1][0:N-1];
logic signed [WL_IN-1:0]        h_imag_arr [0:N-1][0:N-1];
logic                           y_valid;
logic signed [N*WL_IN-1:0]     y_re_flat;
logic signed [N*WL_IN-1:0]     y_im_flat;
logic                           gy_valid;
logic                           gy_enable;
logic signed [N*MF_WL_OUT-1:0] gy_re_flat;
logic signed [N*MF_WL_OUT-1:0] gy_im_flat;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
hermitian_mf_chain #(
    .N          ( N          ),
    .WL_IN      ( WL_IN      ),
    .FL_IN      ( FL_IN      ),
    .INT_BITS   ( INT_BITS   ),
    .MF_WL_W    ( MF_WL_W    ),
    .MF_FL_W    ( MF_FL_W    ),
    .MF_WL_PROD ( MF_WL_PROD ),
    .MF_FL_PROD ( MF_FL_PROD ),
    .MF_FL_Q2   ( MF_FL_Q2   ),
    .MF_FL_Q3   ( MF_FL_Q3   ),
    .MF_FL_Q4   ( MF_FL_Q4   ),
    .MF_FL_Q5   ( MF_FL_Q5   ),
    .MF_WL_OUT  ( MF_WL_OUT  ),
    .MF_FL_OUT  ( MF_FL_OUT  ),
    .HERM_REG   ( HERM_REG   )
) dut (
    .clk        ( clk        ),
    .rst_n      ( rst_n      ),
    .en         ( en         ),
    .h_valid    ( h_valid    ),
    .h_real     ( h_real_arr ),
    .h_imag     ( h_imag_arr ),
    .y_valid    ( y_valid    ),
    .y_re_flat  ( y_re_flat  ),
    .y_im_flat  ( y_im_flat  ),
    .gy_valid   ( gy_valid   ),
    .gy_enable  ( gy_enable  ),
    .gy_re_flat ( gy_re_flat ),
    .gy_im_flat ( gy_im_flat )
);

// ---------------------------------------------------------------------------
// File-based memory (Suite 2)
// ---------------------------------------------------------------------------
logic [WL_IN-1:0]     mem_hh [0 : NUM_FRAMES*N*N*2 - 1];
logic [WL_IN-1:0]     mem_y  [0 : NUM_FRAMES*N*2   - 1];
logic [MF_WL_OUT-1:0] mem_z  [0 : NUM_FRAMES*N*2   - 1];

// ---------------------------------------------------------------------------
// Scoreboard type:  [row][0=real / 1=imag]
// ---------------------------------------------------------------------------
typedef logic signed [MF_WL_OUT-1:0] gy_vec_t [0:N-1][0:1];

// ===========================================================================
// Tasks — ALL declarations are at top of task body (before any statements)
// ===========================================================================

// Standard reset
task automatic do_reset();
    rst_n   = 1'b0;
    en      = 1'b1;
    h_valid = 1'b0;
    y_valid = 1'b0;
    y_re_flat = '0;
    y_im_flat = '0;
    for (int r = 0; r < N; r++)
        for (int c = 0; c < N; c++) begin
            h_real_arr[r][c] = '0;
            h_imag_arr[r][c] = '0;
        end
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);
endtask

// Load one H matrix for one cycle, wait for the full coefficient load
// sequence to complete.
//
// Timing (HERM_REG=1):
//   Posedge 0 : h_valid sampled by hermitian_pipe
//   Posedge 1 : herm_valid_out fires; coef_hold NBA-updated; hh_load_int
//               registered to fire next cycle
//   Posedge 2 : hh_load_int=1; MF coef registers sample valid coef_hold data
//   Posedge 3 : MF coefs settled; y_valid may now be asserted
//
// So we wait HERM_LAT + 2 extra posedges after the h_valid posedge.
task automatic load_H_and_wait(
    input logic signed [WL_IN-1:0] hr [0:N-1][0:N-1],
    input logic signed [WL_IN-1:0] hi [0:N-1][0:N-1]
);
    for (int r = 0; r < N; r++)
        for (int c = 0; c < N; c++) begin
            h_real_arr[r][c] = hr[r][c];
            h_imag_arr[r][c] = hi[r][c];
        end
    h_valid = 1'b1;
    @(posedge clk);          // posedge 0: h_valid captured
    h_valid = 1'b0;
    repeat(HERM_LAT) @(posedge clk);  // posedge 1: herm_valid_out; coef_hold latched; hh_load_int registered
    @(posedge clk);          // posedge 2: hh_load_int=1; MF coef registers updated
    @(posedge clk);          // posedge 3: guard — MF coefs fully settled
endtask

// Drive flat y buses for one cycle
task automatic drive_y_flat(
    input logic signed [WL_IN-1:0] yr [0:N-1],
    input logic signed [WL_IN-1:0] yi [0:N-1]
);
    for (int k = 0; k < N; k++) begin
        y_re_flat[k*WL_IN +: WL_IN] = yr[k];
        y_im_flat[k*WL_IN +: WL_IN] = yi[k];
    end
    y_valid = 1'b1;
    @(posedge clk);
    y_valid = 1'b0;
endtask

// Wait for one gy_valid; capture output; error if timeout
task automatic collect_one(
    output gy_vec_t got,
    output int      err,
    input  int      timeout
);
    int t;
    t   = 0;
    err = 0;
    forever begin
        @(posedge clk);
        t++;
        if (gy_valid) begin
            for (int k = 0; k < N; k++) begin
                got[k][0] = signed'(gy_re_flat[k*MF_WL_OUT +: MF_WL_OUT]);
                got[k][1] = signed'(gy_im_flat[k*MF_WL_OUT +: MF_WL_OUT]);
            end
            return;
        end
        if (t >= timeout) begin
            $display("    TIMEOUT: no gy_valid after %0d cycles", timeout);
            err = 1;
            return;
        end
    end
endtask

// Compare output against expected; return mismatch count
task automatic check_gy(
    input gy_vec_t got,
    input gy_vec_t exp,
    input int      frame_num,
    output int     mismatches
);
    mismatches = 0;
    for (int k = 0; k < N; k++) begin
        if (got[k][0] !== exp[k][0] || got[k][1] !== exp[k][1]) begin
            $display("    FAIL frame=%0d row=%0d  got(%0d,%0d)  exp(%0d,%0d)",
                     frame_num, k,
                     got[k][0], got[k][1],
                     exp[k][0], exp[k][1]);
            mismatches++;
        end
    end
endtask

// ===========================================================================
// MAIN TEST PROCESS
// ===========================================================================
int total_errors;

initial begin : main_proc

    total_errors = 0;

    $display("=============================================================");
    $display(" tb_hermitian_mf_chain");
    $display(" N=%0d  WL_IN=%0d  MF_WL_OUT=%0d", N, WL_IN, MF_WL_OUT);
    $display(" HERM_LAT=%0d  MF_LAT=%0d  CHAIN_LAT=%0d cycles",
             HERM_LAT, MF_LAT, CHAIN_LAT);
    $display("=============================================================");

    // =========================================================================
    // SUITE 0 — Identity sanity
    // H = 0.5*I (real), y = 0.5*ones (real)
    // H^H = 0.5*I  →  g_y[k] = 0.25  →  in Q1.11 = 512
    // =========================================================================
    $display("");
    $display(">>> SUITE 0: Identity sanity (H=0.5*I, y=0.5*ones)");

    do_reset();

    begin : suite_0
        // Declarations first
        logic signed [WL_IN-1:0] s0_Hr [0:N-1][0:N-1];
        logic signed [WL_IN-1:0] s0_Hi [0:N-1][0:N-1];
        logic signed [WL_IN-1:0] s0_yr [0:N-1];
        logic signed [WL_IN-1:0] s0_yi [0:N-1];
        gy_vec_t s0_got;
        int s0_err;
        int s0_mm;
        int s0_errs;

        // Build inputs
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                s0_Hr[r][c] = (r == c) ? WL_IN'(S0_HALF) : '0;
                s0_Hi[r][c] = '0;
            end
        for (int k = 0; k < N; k++) begin
            s0_yr[k] = WL_IN'(S0_HALF);
            s0_yi[k] = '0;
        end

        load_H_and_wait(s0_Hr, s0_Hi);
        drive_y_flat(s0_yr, s0_yi);

        s0_err  = 0;
        s0_mm   = 0;
        s0_errs = 0;
        collect_one(s0_got, s0_err, MF_LAT + 8);

        if (s0_err) begin
            s0_errs++;
        end else begin
            if (!gy_enable) begin
                $display("    FAIL: gy_enable not asserted on first gy_valid");
                s0_errs++;
            end
            for (int k = 0; k < N; k++) begin
                if (s0_got[k][0] !== MF_WL_OUT'(S0_EXP) ||
                    s0_got[k][1] !== MF_WL_OUT'(0)) begin
                    $display("    FAIL row=%0d  got(%0d,%0d)  exp(%0d,0)",
                             k, s0_got[k][0], s0_got[k][1], S0_EXP);
                    s0_mm++;
                end else
                    $display("    PASS row=%0d  gy=(%0d,%0d)",
                             k, s0_got[k][0], s0_got[k][1]);
            end
            s0_errs += s0_mm;
        end
        total_errors += s0_errs;
        $display(">>> SUITE 0: %s (%0d error(s))",
                 (s0_errs==0) ? "PASSED" : "FAILED", s0_errs);
    end

    // =========================================================================
    // SUITE 1 — All-real diagonal: verify imag outputs are zero
    // H[k][k] = (k+1)*128  in Q1.11 (= (k+1)/16)
    // y[k]    = (k+1)*128  in Q1.11
    // For all-real inputs imag(g_y) must be identically zero.
    // =========================================================================
    $display("");
    $display(">>> SUITE 1: All-real diagonal — verify imag(g_y) == 0");

    do_reset();

    begin : suite_1
        logic signed [WL_IN-1:0] s1_Hr [0:N-1][0:N-1];
        logic signed [WL_IN-1:0] s1_Hi [0:N-1][0:N-1];
        logic signed [WL_IN-1:0] s1_yr [0:N-1];
        logic signed [WL_IN-1:0] s1_yi [0:N-1];
        gy_vec_t s1_got;
        int s1_err;
        int s1_mm;
        int s1_errs;

        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                s1_Hr[r][c] = (r == c) ? WL_IN'((r+1) * 128) : '0;
                s1_Hi[r][c] = '0;
            end
        for (int k = 0; k < N; k++) begin
            s1_yr[k] = WL_IN'((k+1) * 128);
            s1_yi[k] = '0;
        end

        load_H_and_wait(s1_Hr, s1_Hi);
        drive_y_flat(s1_yr, s1_yi);

        s1_err  = 0;
        s1_mm   = 0;
        s1_errs = 0;
        collect_one(s1_got, s1_err, MF_LAT + 8);

        if (s1_err) begin
            s1_errs++;
        end else begin
            $display("    Checking imag(g_y) == 0 for all rows:");
            for (int k = 0; k < N; k++) begin
                if (s1_got[k][1] !== MF_WL_OUT'(0)) begin
                    $display("      FAIL row=%0d imag=%0d (expected 0)", k, s1_got[k][1]);
                    s1_mm++;
                end
            end
            $display("    Real outputs (informational):");
            for (int k = 0; k < N; k++)
                $display("      row=%0d  gy_real=%0d", k, s1_got[k][0]);
            s1_errs += s1_mm;
        end
        total_errors += s1_errs;
        $display(">>> SUITE 1: %s (%0d error(s))",
                 (s1_errs==0) ? "PASSED" : "FAILED", s1_errs);
    end

    // =========================================================================
    // SUITE 2 — File-based golden burst (100 frames)
    //
    // Golden files store HH (H^H), Y, Z = H^H*Y from MATLAB.
    // We reconstruct H = (HH)^H = conj(HH)^T and feed it to the chain;
    // hermitian_pipe regenerates HH and the MF produces Z.
    // =========================================================================
    $display("");
    $display(">>> SUITE 2: File-based golden burst (%0d frames)", NUM_FRAMES);

    begin : suite_2
        int fd_hh;
        int fd_y;
        int fd_z;
        bit files_ok;

        fd_hh    = $fopen({FILE_DIR, "HH_all_Convergent.txt"}, "r");
        fd_y     = $fopen({FILE_DIR, "Y_all_Convergent.txt"},  "r");
        fd_z     = $fopen({FILE_DIR, "Z_all_Convergent.txt"},  "r");
        files_ok = (fd_hh != 0) && (fd_y != 0) && (fd_z != 0);

        if (fd_hh) $fclose(fd_hh);
        if (fd_y)  $fclose(fd_y);
        if (fd_z)  $fclose(fd_z);

        if (!files_ok) begin
            $display("    WARNING: Golden files not found in %s — skipping.", FILE_DIR);
        end else begin
            $readmemb({FILE_DIR, "HH_all_Convergent.txt"}, mem_hh);
            $readmemb({FILE_DIR, "Y_all_Convergent.txt"},  mem_y);
            $readmemb({FILE_DIR, "Z_all_Convergent.txt"},  mem_z);

            do_reset();

            begin : s2_inner
                // All declarations at top of named block
                logic signed [WL_IN-1:0] s2_Hr [0:N-1][0:N-1];
                logic signed [WL_IN-1:0] s2_Hi [0:N-1][0:N-1];
                gy_vec_t s2_sb [$];
                int s2_err_cnt;
                int s2_vec_in;
                int s2_vec_out;
                int s2_gy_checked;
                int s2_mm;
                int s2_idx;

                s2_err_cnt    = 0;
                s2_vec_in     = 0;
                s2_vec_out    = 0;
                s2_gy_checked = 0;

                // Build H = conj(HH[0])^T from frame-0 stored HH
                for (int r = 0; r < N; r++)
                    for (int c = 0; c < N; c++) begin
                        s2_idx = 0*N*N*2 + r*N*2 + c*2;
                        // H[c][r] = conj(HH[r][c])
                        s2_Hr[c][r] =  signed'(mem_hh[s2_idx]);
                        s2_Hi[c][r] = -signed'(mem_hh[s2_idx + 1]);
                    end

                load_H_and_wait(s2_Hr, s2_Hi);

                fork
                    // --- Driver thread ---
                    begin : s2_driver
                        logic signed [WL_IN-1:0] s2_yr [0:N-1];
                        logic signed [WL_IN-1:0] s2_yi [0:N-1];
                        gy_vec_t s2_v;
                        int s2_didx;

                        for (int f = 0; f < NUM_FRAMES; f++) begin
                            // Unpack Y[f]
                            for (int k = 0; k < N; k++) begin
                                s2_didx = f*N*2 + k*2;
                                s2_yr[k] = signed'(mem_y[s2_didx]);
                                s2_yi[k] = signed'(mem_y[s2_didx + 1]);
                                y_re_flat[k*WL_IN +: WL_IN] = s2_yr[k];
                                y_im_flat[k*WL_IN +: WL_IN] = s2_yi[k];
                            end
                            // Push expected Z[f]
                            for (int k = 0; k < N; k++) begin
                                s2_didx = f*N*2 + k*2;
                                s2_v[k][0] = signed'(mem_z[s2_didx]);
                                s2_v[k][1] = signed'(mem_z[s2_didx + 1]);
                            end
                            s2_sb.push_back(s2_v);

                            y_valid = 1'b1;
                            @(posedge clk);
                            s2_vec_in++;
                        end
                        y_valid = 1'b0;
                    end : s2_driver

                    // --- Collector thread ---
                    begin : s2_collector
                        gy_vec_t s2_exp;
                        logic signed [MF_WL_OUT-1:0] s2_gr, s2_gi;
                        int s2_cidx;

                        @(posedge clk); // align with first driver posedge
                        while (s2_vec_out < NUM_FRAMES) begin
                            @(posedge clk);
                            if (gy_valid) begin
                                if (!s2_gy_checked) begin
                                    if (!gy_enable) begin
                                        $display("    FAIL: gy_enable absent on first gy_valid");
                                        s2_err_cnt++;
                                    end else
                                        $display("    gy_enable asserted correctly");
                                    s2_gy_checked = 1;
                                end
                                if (s2_sb.size() == 0) begin
                                    $display("    FAIL: spurious gy_valid");
                                    s2_err_cnt++;
                                end else begin
                                    s2_exp = s2_sb.pop_front();
                                    s2_mm  = 0;
                                    for (int k = 0; k < N; k++) begin
                                        s2_gr = signed'(gy_re_flat[k*MF_WL_OUT +: MF_WL_OUT]);
                                        s2_gi = signed'(gy_im_flat[k*MF_WL_OUT +: MF_WL_OUT]);
                                        if (s2_gr !== s2_exp[k][0] || s2_gi !== s2_exp[k][1]) begin
                                            $display("    FAIL f=%0d row=%0d got(%0d,%0d) exp(%0d,%0d)",
                                                     s2_vec_out, k,
                                                     s2_gr, s2_gi,
                                                     s2_exp[k][0], s2_exp[k][1]);
                                            s2_mm++;
                                        end
                                    end
                                    s2_err_cnt += s2_mm;
                                    s2_vec_out++;
                                end
                            end
                        end
                    end : s2_collector
                join

                $display("    Frames in=%0d  out=%0d", s2_vec_in, s2_vec_out);
                if (s2_err_cnt == 0)
                    $display(">>> SUITE 2: ALL %0d FRAMES PASSED (bit-exact)", NUM_FRAMES);
                else
                    $display(">>> SUITE 2: %0d ERROR(S)", s2_err_cnt);
                total_errors += s2_err_cnt;
            end : s2_inner
        end
    end : suite_2

    // =========================================================================
    // Global summary
    // =========================================================================
    $display("");
    $display("=============================================================");
    $display(" GLOBAL SUMMARY");
    $display("=============================================================");
    if (total_errors == 0) begin
        $display(" SUCCESS: All suites passed.");
        $display(" Chain latency: HERM=%0d + LOAD=1 + MF=%0d = %0d cycles",
                 HERM_LAT, MF_LAT, CHAIN_LAT);
    end else
        $display(" FAILURE: %0d total error(s)", total_errors);
    $display("=============================================================");
    $finish;

end : main_proc

// ---------------------------------------------------------------------------
// Timeout guard
// ---------------------------------------------------------------------------
initial begin : timeout_proc
    #10_000_000;
    $display("TIMEOUT — simulation exceeded 10 ms");
    $finish;
end

endmodule
// =============================================================================
// tb_hermitian_mf_chain.sv — end of file
// =============================================================================