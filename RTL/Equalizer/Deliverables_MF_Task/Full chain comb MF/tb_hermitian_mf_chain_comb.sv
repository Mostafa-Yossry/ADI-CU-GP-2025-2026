// =============================================================================
// tb_hermitian_mf_chain.sv
// -----------------------------------------------------------------------------
// Self-checking integration testbench for hermitian_mf_chain.
//
// Tests the full chain:  H → hermitian_pipe → H^H → MF → g_y = H^H·y
//
// MF core is pure-combinational (input + output register only).
// MF_LAT  = 2 cycles
// CHAIN_LAT = HERM_LAT(1) + coef_hold_settle(1) + hh_load_reg(1) + MF_LAT(2)
//           = 5 cycles
//
// Suite 0 — Identity/diagonal sanity (single shot, H = 0.5·I)
// Suite 1 — All-real diagonal, verifies imag outputs == 0
// Suite 2 — File-based golden burst (100 frames, requires testbench_files2/)
// =============================================================================

`timescale 1ns/1ps

module tb_hermitian_mf_chain_comb;

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
localparam int  MF_LAT     = 2;    // pure-combinational core: input FF + output FF
localparam int  CHAIN_LAT  = HERM_LAT + 1 + 1 + MF_LAT; // 1+1+1+2 = 5
                                   // ^herm  ^coef_hold_settle  ^hh_load_reg  ^MF

localparam int  CLK_PERIOD = 10;
localparam int  NUM_FRAMES = 100;

// Suite 0 expected value: 0.5 * 0.5 = 0.25  →  Q5.11 → 0.25 * 2^11 = 512
localparam int  S0_EXP     = 512;
// Suite 0 drive value:    0.5  →  Q1.11 → 0.5 * 2^11 = 1024
localparam int  S0_HALF    = 1024;

localparam string FILE_DIR = "testbench_files2/";

// ---------------------------------------------------------------------------
// Clock & Global Cycle Counter
// ---------------------------------------------------------------------------
logic clk;
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

int global_cycle = 0;
always_ff @(posedge clk) global_cycle <= global_cycle + 1;

// ---------------------------------------------------------------------------
// DUT ports  (gy_enable not present — removed from MF and all wrappers)
// ---------------------------------------------------------------------------
logic                           rst_n;
logic                           en;
logic                           h_valid;
logic signed [WL_IN-1:0]        h_real_arr [0:N-1][0:N-1];
logic signed [WL_IN-1:0]        h_imag_arr [0:N-1][0:N-1];
logic                           y_valid;
logic signed [N*WL_IN-1:0]     y_re_flat;
logic signed [N*WL_IN-1:0]     y_im_flat;
logic                           x_valid;
logic signed [N*MF_WL_OUT-1:0] x_re_flat;
logic signed [N*MF_WL_OUT-1:0] x_im_flat;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
hermitian_mf_chain_comb #(
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
    .x_valid    ( x_valid    ),
    .x_re_flat  ( x_re_flat  ),
    .x_im_flat  ( x_im_flat  )
);

// ---------------------------------------------------------------------------
// File-based memory (Suite 2)
// ---------------------------------------------------------------------------
logic [WL_IN-1:0]     mem_h  [0 : NUM_FRAMES*N*N*2 - 1];
logic [WL_IN-1:0]     mem_y  [0 : NUM_FRAMES*N*2   - 1];
logic [MF_WL_OUT-1:0] mem_z  [0 : NUM_FRAMES*N*2   - 1];

// ---------------------------------------------------------------------------
// Scoreboard types
// ---------------------------------------------------------------------------
typedef logic signed [MF_WL_OUT-1:0] gy_vec_t [0:N-1][0:1];

typedef struct {
    gy_vec_t exp;
    int in_cyc;
} s2_item_t;

// ===========================================================================
// Tasks
// ===========================================================================

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

// Load H matrix, wait for coef_hold and hh_load pipeline to settle.
// Timing through the chain from h_valid:
//   +HERM_LAT cycles : herm_valid_out fires → coef_hold NBA begins
//   +1 cycle         : coef_hold settled,  hh_load_int registered by chain
//   +1 cycle         : hh_load_int visible to MF input register
// Total: HERM_LAT + 2 extra posedges before the first y_valid is safe to send.
task automatic load_H_and_wait(
    input logic signed [WL_IN-1:0] hr [0:N-1][0:N-1],
    input logic signed [WL_IN-1:0] hi [0:N-1][0:N-1],
    output int cyc_h_valid
);
    for (int r = 0; r < N; r++)
        for (int c = 0; c < N; c++) begin
            h_real_arr[r][c] = hr[r][c];
            h_imag_arr[r][c] = hi[r][c];
        end
    h_valid = 1'b1;
    cyc_h_valid = global_cycle;
    @(posedge clk);
    h_valid = 1'b0;
    repeat(HERM_LAT) @(posedge clk);   // wait for hermitian output
    @(posedge clk);                     // coef_hold settle
    @(posedge clk);                     // hh_load_int propagates into MF
endtask

task automatic drive_y_flat(
    input logic signed [WL_IN-1:0] yr [0:N-1],
    input logic signed [WL_IN-1:0] yi [0:N-1],
    output int cyc_y_valid
);
    for (int k = 0; k < N; k++) begin
        y_re_flat[k*WL_IN +: WL_IN] = yr[k];
        y_im_flat[k*WL_IN +: WL_IN] = yi[k];
    end
    y_valid = 1'b1;
    cyc_y_valid = global_cycle;
    @(posedge clk);
    y_valid = 1'b0;
endtask

// Wait for one x_valid pulse; capture output.
// timeout: maximum cycles to wait — set generously to CHAIN_LAT + 8.
task automatic collect_one(
    output gy_vec_t got,
    output int      err,
    output int      out_cyc,
    input  int      timeout
);
    int t = 0;
    err = 0;
    forever begin
        @(posedge clk);
        t++;
        if (x_valid) begin
            out_cyc = global_cycle - 1;
            for (int k = 0; k < N; k++) begin
                got[k][0] = signed'(x_re_flat[k*MF_WL_OUT +: MF_WL_OUT]);
                got[k][1] = signed'(x_im_flat[k*MF_WL_OUT +: MF_WL_OUT]);
            end
            return;
        end
        if (t >= timeout) begin
            $display("    TIMEOUT: no x_valid after %0d cycles", timeout);
            err = 1;
            return;
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
    $display(" tb_hermitian_mf_chain_comb  (pure-combinational MF core)");
    $display(" N=%0d  WL_IN=%0d  MF_WL_OUT=%0d", N, WL_IN, MF_WL_OUT);
    $display(" HERM_LAT=%0d  MF_LAT=%0d  CHAIN_LAT=%0d cycles",
             HERM_LAT, MF_LAT, CHAIN_LAT);
    $display("=============================================================");

    // =========================================================================
    // SUITE 0 — Identity sanity (H = 0.5·I, y = 0.5·ones)
    // Expected: g_y[r] = 0.5 * 0.5 = 0.25 → Q5.11 = 512 (real), 0 (imag)
    // =========================================================================
    $display("");
    $display(">>> SUITE 0: Identity sanity (H=0.5*I, y=0.5*ones)");
    do_reset();

    begin : suite_0
        logic signed [WL_IN-1:0] s0_Hr [0:N-1][0:N-1];
        logic signed [WL_IN-1:0] s0_Hi [0:N-1][0:N-1];
        logic signed [WL_IN-1:0] s0_yr [0:N-1];
        logic signed [WL_IN-1:0] s0_yi [0:N-1];
        gy_vec_t s0_got;
        int s0_err, s0_mm, s0_errs;
        int cyc_h, cyc_y, cyc_gy;

        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                s0_Hr[r][c] = (r == c) ? WL_IN'(S0_HALF) : '0;
                s0_Hi[r][c] = '0;
            end
        for (int k = 0; k < N; k++) begin
            s0_yr[k] = WL_IN'(S0_HALF);
            s0_yi[k] = '0;
        end

        load_H_and_wait(s0_Hr, s0_Hi, cyc_h);
        drive_y_flat(s0_yr, s0_yi, cyc_y);

        s0_err = 0; s0_mm = 0; s0_errs = 0;
        collect_one(s0_got, s0_err, cyc_gy, CHAIN_LAT + 8);

        $display("    --- Timing ---");
        $display("    [Cyc %6d] h_valid asserted", cyc_h);
        $display("    [Cyc %6d] herm_valid_out (after HERM_LAT=%0d)", cyc_h + HERM_LAT, HERM_LAT);
        $display("    [Cyc %6d] coef_hold settled", cyc_h + HERM_LAT + 1);
        $display("    [Cyc %6d] hh_load_int fires into MF", cyc_h + HERM_LAT + 2);
        $display("    [Cyc %6d] y_valid asserted", cyc_y);
        $display("    [Cyc %6d] x_valid captured (MF_LAT=%0d)", cyc_gy, MF_LAT);
        $display("    --------------");

        if (s0_err) begin
            s0_errs++;
        end else begin
            $display("    ROW | DUT (re, im)       | GLD (re, im)");
            $display("    -----------------------------------------");
            for (int k = 0; k < N; k++) begin
                if (s0_got[k][0] !== MF_WL_OUT'(S0_EXP) || s0_got[k][1] !== MF_WL_OUT'(0)) begin
                    $display("    %3d | FAIL (%5d, %5d) | (%5d, %5d)",
                             k, s0_got[k][0], s0_got[k][1], S0_EXP, 0);
                    s0_mm++;
                end else begin
                    $display("    %3d | PASS (%5d, %5d) | (%5d, %5d)",
                             k, s0_got[k][0], s0_got[k][1], S0_EXP, 0);
                end
            end
            s0_errs += s0_mm;
        end
        total_errors += s0_errs;
        $display(">>> SUITE 0: %s (%0d error(s))", (s0_errs==0) ? "PASSED" : "FAILED", s0_errs);
    end

    // =========================================================================
    // SUITE 1 — All-real diagonal  (verify imag(g_y) == 0)
    // H[r][r] = (r+1)*128 in Q1.11,  y[k] = (k+1)*128 in Q1.11
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
        int s1_err, s1_mm, s1_errs;
        int cyc_h, cyc_y, cyc_gy;

        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin
                s1_Hr[r][c] = (r == c) ? WL_IN'((r+1) * 128) : '0;
                s1_Hi[r][c] = '0;
            end
        for (int k = 0; k < N; k++) begin
            s1_yr[k] = WL_IN'((k+1) * 128);
            s1_yi[k] = '0;
        end

        load_H_and_wait(s1_Hr, s1_Hi, cyc_h);
        drive_y_flat(s1_yr, s1_yi, cyc_y);

        s1_err = 0; s1_mm = 0; s1_errs = 0;
        collect_one(s1_got, s1_err, cyc_gy, CHAIN_LAT + 8);

        if (s1_err) begin
            s1_errs++;
        end else begin
            $display("    ROW | DUT IMAG | STATUS (Expect 0)");
            $display("    ----------------------------------");
            for (int k = 0; k < N; k++) begin
                if (s1_got[k][1] !== MF_WL_OUT'(0)) begin
                    $display("    %3d | %8d | FAIL!!", k, s1_got[k][1]);
                    s1_mm++;
                end else begin
                    $display("    %3d | %8d | PASS", k, s1_got[k][1]);
                end
            end
            s1_errs += s1_mm;
        end
        total_errors += s1_errs;
        $display(">>> SUITE 1: %s (%0d error(s))", (s1_errs==0) ? "PASSED" : "FAILED", s1_errs);
    end

    // =========================================================================
    // SUITE 2 — File-based golden burst (100 frames, continuous streaming)
    // =========================================================================
    $display("");
    $display(">>> SUITE 2: File-based golden burst (%0d frames) - Vertical Format", NUM_FRAMES);

    begin : suite_2
        int fd_h, fd_y, fd_z;
        bit files_ok;
        int lat_hist [int];

        fd_h     = $fopen({FILE_DIR, "H_all_Convergent.txt"}, "r");
        fd_y     = $fopen({FILE_DIR, "Y_all_Convergent.txt"}, "r");
        fd_z     = $fopen({FILE_DIR, "Z_all_Convergent.txt"}, "r");
        files_ok = (fd_h != 0) && (fd_y != 0) && (fd_z != 0);

        if (fd_h) $fclose(fd_h);
        if (fd_y) $fclose(fd_y);
        if (fd_z) $fclose(fd_z);

        if (!files_ok) begin
            $display("    WARNING: Golden files not found in %s — skipping.", FILE_DIR);
        end else begin
            $readmemb({FILE_DIR, "H_all_Convergent.txt"}, mem_h);
            $readmemb({FILE_DIR, "Y_all_Convergent.txt"}, mem_y);
            $readmemb({FILE_DIR, "Z_all_Convergent.txt"}, mem_z);

            do_reset();

            begin : s2_inner
                logic signed [WL_IN-1:0] s2_Hr [0:N-1][0:N-1];
                logic signed [WL_IN-1:0] s2_Hi [0:N-1][0:N-1];
                s2_item_t s2_sb [$];
                int s2_err_cnt, s2_vec_in, s2_vec_out, s2_mm, s2_idx, cyc_h;

                s2_err_cnt = 0; s2_vec_in = 0; s2_vec_out = 0;

                // Load H^H from frame 0 and wait for it to settle in MF
                for (int r = 0; r < N; r++)
                    for (int c = 0; c < N; c++) begin
                        s2_idx = 0*N*N*2 + r*N*2 + c*2;
                        s2_Hr[r][c] = signed'(mem_h[s2_idx]);
                        s2_Hi[r][c] = signed'(mem_h[s2_idx + 1]);
                    end

                load_H_and_wait(s2_Hr, s2_Hi, cyc_h);

                fork
                    // ---- Driver: stream 100 Y vectors back-to-back ----
                    begin : s2_driver
                        logic signed [WL_IN-1:0] s2_yr [0:N-1];
                        logic signed [WL_IN-1:0] s2_yi [0:N-1];
                        s2_item_t item;
                        int s2_didx;

                        for (int f = 0; f < NUM_FRAMES; f++) begin
                            for (int k = 0; k < N; k++) begin
                                s2_didx = f*N*2 + k*2;
                                s2_yr[k] = signed'(mem_y[s2_didx]);
                                s2_yi[k] = signed'(mem_y[s2_didx + 1]);
                                y_re_flat[k*WL_IN +: WL_IN] = s2_yr[k];
                                y_im_flat[k*WL_IN +: WL_IN] = s2_yi[k];
                            end
                            for (int k = 0; k < N; k++) begin
                                s2_didx = f*N*2 + k*2;
                                item.exp[k][0] = signed'(mem_z[s2_didx]);
                                item.exp[k][1] = signed'(mem_z[s2_didx + 1]);
                            end
                            y_valid = 1'b1;
                            item.in_cyc = global_cycle;
                            s2_sb.push_back(item);
                            @(posedge clk);
                            s2_vec_in++;
                        end
                        y_valid = 1'b0;
                    end : s2_driver

                    // ---- Collector: check outputs as they arrive ----
                    // Skip MF_LAT cycles so the first check posedge aligns
                    // with when the first output is expected.
                    // In back-to-back streaming valid_out should stay
                    // continuously high — a gap is flagged as an error.
                    begin : s2_collector
                        s2_item_t s2_exp_item;
                        logic signed [MF_WL_OUT-1:0] s2_gr, s2_gi;
                        int gld_r, gld_i;
                        string d_sgn, g_sgn;
                        int d_aim, g_aim;
                        int lat;

                        repeat(MF_LAT) @(posedge clk);  // skip pipeline depth

                        while (s2_vec_out < NUM_FRAMES) begin
                            @(posedge clk);
                            if (x_valid) begin
                                if (s2_sb.size() == 0) begin
                                    $display("    FAIL: spurious x_valid");
                                    s2_err_cnt++;
                                end else begin
                                    s2_exp_item = s2_sb.pop_front();
                                    s2_mm = 0;
                                    lat = (global_cycle - 1) - s2_exp_item.in_cyc;

                                    if (lat_hist.exists(lat)) lat_hist[lat]++;
                                    else lat_hist[lat] = 1;

                                    // First pass: count mismatches
                                    for (int k = 0; k < N; k++) begin
                                        s2_gr = signed'(x_re_flat[k*MF_WL_OUT +: MF_WL_OUT]);
                                        s2_gi = signed'(x_im_flat[k*MF_WL_OUT +: MF_WL_OUT]);
                                        if (s2_gr !== s2_exp_item.exp[k][0] ||
                                            s2_gi !== s2_exp_item.exp[k][1])
                                            s2_mm++;
                                    end

                                    // Vertical display block
                                    $display("    ==============================================================================");
                                    $display("    FRAME %3d | IN_CYC: %6d | OUT_CYC: %6d | LAT: %3d | STAT: %s",
                                             s2_vec_out, s2_exp_item.in_cyc, global_cycle - 1,
                                             lat, (s2_mm==0) ? "PASS" : "FAIL");
                                    $display("    ------------------------------------------------------------------------------");
                                    $display("    ROW | DUT (Real + Imag j)        | GLD (Real + Imag j)        | STATUS");
                                    $display("    ------------------------------------------------------------------------------");

                                    for (int k = 0; k < N; k++) begin
                                        s2_gr = signed'(x_re_flat[k*MF_WL_OUT +: MF_WL_OUT]);
                                        s2_gi = signed'(x_im_flat[k*MF_WL_OUT +: MF_WL_OUT]);
                                        gld_r = s2_exp_item.exp[k][0];
                                        gld_i = s2_exp_item.exp[k][1];
                                        d_sgn = (s2_gi < 0) ? "-" : "+";
                                        d_aim = (s2_gi < 0) ? -s2_gi : s2_gi;
                                        g_sgn = (gld_i < 0) ? "-" : "+";
                                        g_aim = (gld_i < 0) ? -gld_i : gld_i;
                                        $display("     %1d  | (%6d %s %5dj)       | (%6d %s %5dj)       | %s",
                                                 k,
                                                 s2_gr, d_sgn, d_aim,
                                                 gld_r, g_sgn, g_aim,
                                                 (s2_gr == gld_r && s2_gi == gld_i) ? "PASS" : "FAIL");
                                    end
                                    $display("    ==============================================================================\n");

                                    s2_err_cnt += s2_mm;
                                    s2_vec_out++;
                                end
                            end else begin
                                // valid_out went low mid-stream — only expected
                                // before the first output or after the last one
                                if (s2_vec_out > 0 && s2_vec_out < NUM_FRAMES) begin
                                    $display("    WARN: x_valid dropped mid-stream (out=%0d cycle=%0d)",
                                             s2_vec_out, global_cycle - 1);
                                    s2_err_cnt++;
                                end
                            end
                        end
                    end : s2_collector
                join

                $display("    Frames in=%0d  out=%0d", s2_vec_in, s2_vec_out);
                $display("");
                $display("    --- Latency Histogram (cycles from y_valid to x_valid) ---");
                foreach (lat_hist[l])
                    $display("    %3d cycles : %5d frames", l, lat_hist[l]);
                $display("    -----------------------------------------------------------");

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
        $display(" Chain latency: HERM=%0d + coef_settle=1 + hh_load_reg=1 + MF=%0d = %0d cycles",
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