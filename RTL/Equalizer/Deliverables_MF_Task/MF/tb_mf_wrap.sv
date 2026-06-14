// =============================================================================
// tb_matched_filter_pipe_wrap.sv
// -----------------------------------------------------------------------------
// Self-checking testbench for matched_filter_pipe_wrap (unrolled core).
//
// Suite A — 100-frame golden burst (bit-exact vs MATLAB reference files)
//   HH from frame 0 held static; Y streamed back-to-back; bit-exact check.


`timescale 1ns/1ps

module tb_matched_filter_pipe_wrap;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
localparam int N        = 8;
localparam int WL_IN    = 12;
localparam int FL_IN    = 11;
localparam int WL_W     = 16;
localparam int FL_W     = 15;
localparam int WL_PROD  = 32;
localparam int FL_PROD  = 30;
localparam int FL_Q2    = 14;
localparam int FL_Q3    = 13;
localparam int FL_Q4    = 12;
localparam int FL_Q5    = 11;
localparam int WL_OUT   = 16;
localparam int FL_OUT   = 11;

localparam int ROWS         = N;
localparam int COLS         = N;
localparam int PIPE_LAT     = 10;   // unrolled core: 10 cycles
localparam int NUM_TESTS    = 100;
localparam int CLK_PERIOD   = 10;   // 100 MHz

// Suite B parameters
localparam int STALL_PRE    = 5;    // frames fired before stall
localparam int STALL_CYCLES = 4;    // cycles en=0
localparam int STALL_POST   = 5;    // frames fired after stall (excluding sentinel)

localparam string DIR = "testbench_files2/";

// Sentinel values
localparam logic signed [WL_IN-1:0]  SENTINEL_COEF  = 12'sh200;  // +512
localparam logic signed [WL_IN-1:0]  SENTINEL_Y     = 12'sh100;  // +256
localparam logic signed [WL_OUT-1:0] SENTINEL_EXP_R = 16'sd512;
localparam logic signed [WL_OUT-1:0] SENTINEL_EXP_I = 16'sd0;

// Widened sentinel coef (Q1.15): used for CHECK 4 register readback
localparam int FRAC_WIDEN = FL_W - FL_IN;  // 4
localparam logic signed [WL_W-1:0] SENTINEL_COEF_W =
    signed'({ {(WL_W - WL_IN - FRAC_WIDEN){SENTINEL_COEF[WL_IN-1]}},
               SENTINEL_COEF,
              {FRAC_WIDEN{1'b0}} });

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------
logic clk;
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---------------------------------------------------------------------------
// DUT ports
// ---------------------------------------------------------------------------
logic                          rst_n;
logic                          en;
logic                          hh_load;
logic signed [N*N*WL_IN-1:0]  hh_re_flat;
logic signed [N*N*WL_IN-1:0]  hh_im_flat;
logic                          y_valid;
logic signed [N*WL_IN-1:0]    y_re_flat;
logic signed [N*WL_IN-1:0]    y_im_flat;
logic                          valid_out;
logic                          gy_enable;
logic signed [N*WL_OUT-1:0]   x_re_flat;
logic signed [N*WL_OUT-1:0]   x_im_flat;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
matched_filter_pipe_wrap #(
    .N          ( N        ),
    .MF_WL_IN   ( WL_IN    ),
    .MF_FL_IN   ( FL_IN    ),
    .MF_WL_W    ( WL_W     ),
    .MF_FL_W    ( FL_W     ),
    .MF_WL_PROD ( WL_PROD  ),
    .MF_FL_PROD ( FL_PROD  ),
    .MF_FL_Q2   ( FL_Q2    ),
    .MF_FL_Q3   ( FL_Q3    ),
    .MF_FL_Q4   ( FL_Q4    ),
    .MF_FL_Q5   ( FL_Q5    ),
    .MF_WL_OUT  ( WL_OUT   ),
    .MF_FL_OUT  ( FL_OUT   )
) dut (
    .clk        ( clk        ),
    .rst_n      ( rst_n      ),
    .en         ( en         ),
    .hh_load    ( hh_load    ),
    .hh_re_flat ( hh_re_flat ),
    .hh_im_flat ( hh_im_flat ),
    .y_valid    ( y_valid    ),
    .y_re_flat  ( y_re_flat  ),
    .y_im_flat  ( y_im_flat  ),
    .valid_out  ( valid_out  ),
    .gy_enable  ( gy_enable  ),
    .x_re_flat  ( x_re_flat  ),
    .x_im_flat  ( x_im_flat  )
);

// ---------------------------------------------------------------------------
// Golden reference memory
// ---------------------------------------------------------------------------
logic [WL_IN-1:0]  mem_hh [0 : NUM_TESTS*ROWS*COLS*2 - 1];
logic [WL_IN-1:0]  mem_y  [0 : NUM_TESTS*COLS*2      - 1];
logic [WL_OUT-1:0] mem_z  [0 : NUM_TESTS*ROWS*2      - 1];

// ---------------------------------------------------------------------------
// Scoreboard queue type  [row][0=real / 1=imag]
// ---------------------------------------------------------------------------
typedef logic signed [WL_OUT-1:0] z_vec_t [0:ROWS-1][0:1];

// ===========================================================================
// Helper tasks
// ===========================================================================

// Load HH flat buses from memory frame f
task automatic set_hh(input int f);
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++) begin
            automatic int idx = f*ROWS*COLS*2 + r*COLS*2 + c*2;
            hh_re_flat[(r*N+c)*WL_IN +: WL_IN] = mem_hh[idx];
            hh_im_flat[(r*N+c)*WL_IN +: WL_IN] = mem_hh[idx+1];
        end
endtask

// Drive Y flat buses from memory frame f
task automatic drive_y(input int f);
    for (int k = 0; k < COLS; k++) begin
        automatic int idx = f*COLS*2 + k*2;
        y_re_flat[k*WL_IN +: WL_IN] = mem_y[idx];
        y_im_flat[k*WL_IN +: WL_IN] = mem_y[idx+1];
    end
endtask

// Push expected Z for frame f onto the scoreboard queue
task automatic push_expected(input int f, inout z_vec_t q[$]);
    z_vec_t v;
    for (int k = 0; k < ROWS; k++) begin
        v[k][0] = signed'(mem_z[f*ROWS*2 + k*2]);
        v[k][1] = signed'(mem_z[f*ROWS*2 + k*2 + 1]);
    end
    q.push_back(v);
endtask

// Check one collected output against expected; return mismatch count
task automatic check_output(
    input  z_vec_t exp,
    input  int     frame_num,
    output int     mismatches
);
    mismatches = 0;
    for (int k = 0; k < ROWS; k++) begin
        logic signed [WL_OUT-1:0] got_r, got_i;
        got_r = signed'(x_re_flat[k*WL_OUT +: WL_OUT]);
        got_i = signed'(x_im_flat[k*WL_OUT +: WL_OUT]);
        if (got_r !== exp[k][0] || got_i !== exp[k][1]) begin
            $display("    FAIL frame=%0d row=%0d  got(%0d,%0d)  exp(%0d,%0d)",
                     frame_num, k, got_r, got_i, exp[k][0], exp[k][1]);
            mismatches++;
        end
    end
endtask

// Fill all HH buses with sentinel coef (real=SENTINEL_COEF, imag=0)
task automatic set_sentinel_hh();
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++) begin
            hh_re_flat[(r*N+c)*WL_IN +: WL_IN] = SENTINEL_COEF;
            hh_im_flat[(r*N+c)*WL_IN +: WL_IN] = '0;
        end
endtask

// Fill all Y buses with sentinel Y (real=SENTINEL_Y, imag=0)
task automatic set_sentinel_y();
    for (int k = 0; k < COLS; k++) begin
        y_re_flat[k*WL_IN +: WL_IN] = SENTINEL_Y;
        y_im_flat[k*WL_IN +: WL_IN] = '0;
    end
endtask

task automatic zero_inputs();
    hh_re_flat = '0; hh_im_flat = '0;
    y_re_flat  = '0; y_im_flat  = '0;
endtask

// Standard reset: rst_n low for 4 cycles, high, 2 idle cycles
task automatic do_reset();
    rst_n   = 1'b0;
    en      = 1'b1;
    hh_load = 1'b0;
    y_valid = 1'b0;
    zero_inputs();
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);
endtask

// Assert hh_load for exactly one posedge; buses must already be set
task automatic load_hh();
    hh_load = 1'b1;
    @(posedge clk);
    hh_load = 1'b0;
endtask

// ===========================================================================
// MAIN TEST PROCESS
// ===========================================================================
int total_errors = 0;

initial begin : main_proc

    $readmemb({DIR, "HH_all_Convergent.txt"}, mem_hh);
    $readmemb({DIR, "Y_all_Convergent.txt"},  mem_y);
    $readmemb({DIR, "Z_all_Convergent.txt"},  mem_z);

    $display("=============================================================");
    $display(" tb_matched_filter_pipe_wrap (unrolled core)");
    $display(" N=%0d  WL_IN=%0d  WL_OUT=%0d  PIPE_LAT=%0d cycles",
             N, WL_IN, WL_OUT, PIPE_LAT);
    $display(" Files: %s  (%0d frames)", DIR, NUM_TESTS);
    $display("=============================================================");

    // =======================================================================
    // SUITE A — 100-frame golden burst
    // =======================================================================
    $display("");
    $display(">>> SUITE A: %0d-frame golden burst (bit-exact, continuous stream)",
             NUM_TESTS);

    do_reset();
    set_hh(0);
    load_hh();

    begin : suite_a
        z_vec_t sb_queue[$];
        int err_cnt       = 0;
        int vectors_in    = 0;
        int vectors_out   = 0;
        int gy_checked    = 0;
        int first_out_cyc = 0;
        int cyc           = 0;
        int mm;

        fork
            // Driver: stream 100 Y vectors back-to-back
            begin
                for (int f = 0; f < NUM_TESTS; f++) begin
                    drive_y(f);
                    push_expected(f, sb_queue);
                    y_valid = 1'b1;
                    @(posedge clk);
                    vectors_in++;
                end
                y_valid = 1'b0;
            end

            // Collector: sample outputs as they arrive
            begin
                @(posedge clk); // align with first driver posedge
                while (vectors_out < NUM_TESTS) begin
                    @(posedge clk);
                    cyc++;
                    if (valid_out) begin
                        if (!gy_checked) begin
                            first_out_cyc = cyc;
                            if (!gy_enable) begin
                                $display("    FAIL: gy_enable not high on first valid_out (cycle %0d)", cyc);
                                err_cnt++;
                            end else
                                $display("    gy_enable asserted correctly at cycle %0d", cyc);
                            gy_checked = 1;
                        end
                        if (sb_queue.size() == 0) begin
                            $display("    FAIL: spurious valid_out at cycle %0d", cyc);
                            err_cnt++;
                        end else begin
                            automatic z_vec_t exp = sb_queue.pop_front();
                            check_output(exp, vectors_out, mm);
                            err_cnt += mm;
                            vectors_out++;
                        end
                    end
                end
            end
        join

        $display("    First valid_out at collector cycle %0d (pipeline latency %0d)",
                 first_out_cyc, PIPE_LAT);
        $display("    Vectors in=%0d  out=%0d", vectors_in, vectors_out);

        if (err_cnt == 0)
            $display(">>> SUITE A: ALL %0d FRAMES PASSED (bit-exact)", NUM_TESTS);
        else
            $display(">>> SUITE A: %0d ERROR(S)", err_cnt);

        total_errors += err_cnt;
    end
/*
    // =======================================================================
    // SUITE B — pipeline stall test
    // =======================================================================
    // Structure:
    //
    //  Part 1 (fork/join): functional stall sequence
    //    Driver: Phase 1 (STALL_PRE frames) → Phase 2 (en=0, STALL_CYCLES) →
    //            Phase 3 (STALL_POST frames)
    //    Collector: runs concurrently, collects STALL_PRE+STALL_POST outputs
    //    HH: frame-0 HH loaded once before fork; NEVER CHANGED during fork.
    //    Spurious: flagged only when valid_out fires while en=0 AND scoreboard
    //              is empty (no pre-stall output is legitimately due).
    //
    //  Part 2 (sequential, after fork): sentinel + CHECK 4
    //    Load sentinel HH while en=0 (1 cycle).  CHECK 4: read back coef regs.
    //    Resume en=1.  Fire sentinel Y.  Wait PIPE_LAT+2 cycles.
    //    CHECK 3: sentinel output.
    //    This ordering guarantees HH changes never contaminate functional frames.
    //
    // =======================================================================
    $display("");
    $display(">>> SUITE B: stall test  STALL_PRE=%0d  STALL_CYCLES=%0d  STALL_POST=%0d",
             STALL_PRE, STALL_CYCLES, STALL_POST);

    do_reset();

    // Load frame-0 HH; this is the ONLY HH load during the functional phase.
    set_hh(0);
    load_hh();

    begin : suite_b
        z_vec_t sb_queue[$];
        int err_cnt       = 0;
        int spurious      = 0;
        int vectors_out   = 0;
        int mm;
        // Total functional outputs expected (sentinel handled separately)
        localparam int FUNC_EXP = STALL_PRE + STALL_POST;

        // ------------------------------------------------------------------
        // PART 1: functional stall — drive and collect concurrently
        // ------------------------------------------------------------------
        fork

            // ---- DRIVER THREAD -------------------------------------------
            begin : b_driver

                // Phase 1: stream STALL_PRE frames
                $display("    Phase 1: streaming %0d pre-stall frames", STALL_PRE);
                for (int f = 0; f < STALL_PRE; f++) begin
                    drive_y(f);
                    push_expected(f, sb_queue);
                    y_valid = 1'b1;
                    @(posedge clk);
                end
                y_valid = 1'b0;

                // Phase 2: stall — assert en=0 on negedge after last Phase-1 posedge
                // HH is NOT changed here; sentinel HH load deferred to Part 2.
                $display("    Phase 2: stalling %0d cycles (en=0)", STALL_CYCLES);
                @(negedge clk);
                en = 1'b0;
                repeat(STALL_CYCLES) @(posedge clk);
                // en=0 for exactly STALL_CYCLES posedges

                // Phase 3: resume — assert en=1 on negedge after last stall posedge
                $display("    Phase 3: resuming — streaming %0d post-stall frames",
                         STALL_POST);
                @(negedge clk);
                en = 1'b1;
                // frame-0 HH is still in coef registers (unchanged); no reload needed
                for (int f = STALL_PRE; f < STALL_PRE + STALL_POST; f++) begin
                    drive_y(f);
                    push_expected(f, sb_queue);
                    y_valid = 1'b1;
                    @(posedge clk);
                end
                y_valid = 1'b0;

            end : b_driver

            // ---- COLLECTOR THREAD ----------------------------------------
            // Runs throughout Phases 1-3 collecting every valid_out pulse.
            // Spurious = valid_out while en=0 AND scoreboard empty.
            begin : b_collector
                int timeout = FUNC_EXP + PIPE_LAT + STALL_CYCLES + 20;
                int t = 0;

                @(posedge clk); // align with first driver posedge (Phase 1, frame 0)

                while (vectors_out < FUNC_EXP && t < timeout) begin
                    @(posedge clk);
                    t++;
                    if (valid_out) begin
                        if (sb_queue.size() == 0) begin
                            // No output was due
                            $display("    SPURIOUS valid_out t=%0d (en=%0b, scoreboard empty)",
                                     t, en);
                            spurious++;
                            err_cnt++;
                        end else begin
                            automatic z_vec_t exp = sb_queue.pop_front();
                            automatic int     fn  = vectors_out;
                            if (!en)
                                $display("    INFO: fn=%0d output arrived during stall (expected)", fn);
                            check_output(exp, fn, mm);
                            err_cnt += mm;
                            vectors_out++;
                        end
                    end
                end

                if (vectors_out < FUNC_EXP) begin
                    $display("    TIMEOUT: only collected %0d/%0d functional outputs",
                             vectors_out, FUNC_EXP);
                    err_cnt++;
                end

            end : b_collector

        join // both driver and collector finish before Part 2

        // ------------------------------------------------------------------
        // PART 2 (sequential): sentinel + CHECK 4
        // All functional outputs are confirmed at this point.
        // Now load sentinel HH while en=0 to exercise hh_load-not-gated-by-en.
        // ------------------------------------------------------------------
        $display("    Part 2: sentinel phase");

        // Drop en, load sentinel HH for one cycle, then CHECK 4
        @(negedge clk);
        en = 1'b0;
        set_sentinel_hh();
        hh_load = 1'b1;
        @(posedge clk);   // sentinel HH latched here
        hh_load = 1'b0;

        // CHECK 4: coef registers must now hold sentinel values
        begin
            int c4_pass = 0, c4_fail = 0;
            $display("    CHECK 4: coef registers == SENTINEL_COEF_W");
            for (int cr = 0; cr < ROWS; cr++)
                for (int cc = 0; cc < COLS; cc++) begin
                    if (dut.u_mf.coef_real[cr][cc] !== SENTINEL_COEF_W ||
                        dut.u_mf.coef_imag[cr][cc] !== '0) begin
                        $display("      FAIL [%0d][%0d]: got=(%0d,%0d) exp=(%0d,0)",
                            cr, cc,
                            dut.u_mf.coef_real[cr][cc],
                            dut.u_mf.coef_imag[cr][cc],
                            SENTINEL_COEF_W);
                        c4_fail++;
                    end else c4_pass++;
                end
            $display("      CHECK 4: PASS=%0d FAIL=%0d  %s",
                     c4_pass, c4_fail, (c4_fail==0) ? "PASS" : "FAIL");
            err_cnt += c4_fail;
        end

        // Resume en, fire sentinel Y with sentinel HH still loaded
        @(negedge clk);
        en = 1'b1;

        set_sentinel_y();
        y_valid = 1'b1;
        @(posedge clk);   // sentinel Y enters pipeline
        y_valid = 1'b0;

        // Wait for sentinel output: PIPE_LAT cycles from entry + 2 guard
        repeat(PIPE_LAT + 1) @(posedge clk);

        // CHECK 3: sentinel output
        $display("    CHECK 3: sentinel frame output (exp: all rows = (%0d,%0d))",
                 SENTINEL_EXP_R, SENTINEL_EXP_I);
        if (!valid_out) begin
            $display("    FAIL: valid_out not asserted on expected sentinel cycle");
            err_cnt++;
        end else begin
            for (int k = 0; k < ROWS; k++) begin
                logic signed [WL_OUT-1:0] got_r, got_i;
                got_r = signed'(x_re_flat[k*WL_OUT +: WL_OUT]);
                got_i = signed'(x_im_flat[k*WL_OUT +: WL_OUT]);
                if (got_r !== SENTINEL_EXP_R || got_i !== SENTINEL_EXP_I) begin
                    $display("    FAIL sentinel row=%0d  got(%0d,%0d)  exp(%0d,%0d)",
                             k, got_r, got_i, SENTINEL_EXP_R, SENTINEL_EXP_I);
                    err_cnt++;
                end else
                    $display("    PASS sentinel row=%0d  (%0d,%0d)", k, got_r, got_i);
            end
        end

        // ------------------------------------------------------------------
        // Suite B report
        // ------------------------------------------------------------------
        $display("");
        $display("=============================================================");
        $display(" SUITE B REPORT");
        $display("=============================================================");

        $display("  CHECK 1: no spurious valid_out during stall (en=0, empty scoreboard)");
        $display("  Spurious: %0d  %s", spurious, (spurious==0) ? "PASS" : "FAIL");

        $display("  CHECK 2: functional frame outputs (%0d frames)", FUNC_EXP);
        $display("  %s", (err_cnt==0) ? "PASS" : "FAIL");

        $display("  CHECK 3: sentinel frame — see per-row output above");
        $display("  CHECK 4: coef register readback — see above");

        total_errors += err_cnt;
        $display("");
        $display("  SUITE B SUMMARY: FAIL=%0d  %s",
                 err_cnt, (err_cnt==0) ? "ALL PASSED" : "FAILURES DETECTED");
    end
*/
    // =======================================================================
    // Global summary
    // =======================================================================
    $display("");
    $display("=============================================================");
    $display(" GLOBAL SUMMARY");
    $display("=============================================================");
    if (total_errors == 0) begin
        $display(" SUCCESS: All tests passed!");
        $display(" matched_filter_pipe_wrap (unrolled) verified");
        $display(" Z = H^H * Y, 8x8 MIMO, %0d-cycle latency, 1 vector/cycle",
                 PIPE_LAT);
    end else
        $display(" FAILURE: %0d total error(s)", total_errors);
    $display("=============================================================");
    $finish;

end

// ---------------------------------------------------------------------------
// Timeout guard
// ---------------------------------------------------------------------------
initial begin : timeout_proc
    #5_000_000;
    $display("TIMEOUT — simulation exceeded 5 ms");
    $finish;
end

endmodule
// =============================================================================
// tb_matched_filter_pipe_wrap.sv — end of file
// =============================================================================
// Suite B — pipeline stall test
//   Functional stall phase: frame-0 HH held throughout; STALL_PRE frames
//   fired, en=0 for STALL_CYCLES, STALL_POST frames resumed.  All functional
//   outputs collected concurrently with driving (fork/join).
//   Sentinel phase: after all functional outputs are confirmed, load sentinel
//   HH while en=0 (CHECK 4 — verifies hh_load is not gated by en), then fire
//   sentinel Y and collect sentinel output (CHECK 3).
//
// WHY fork/join FOR DRIVING AND COLLECTING:
//   Pre-stall outputs enter the pipeline before the stall and emerge from it
//   at various points during or after the stall window, depending on where
//   in the 10-stage pipeline they were frozen.  A sequential structure (drive
//   everything, then collect) misses any valid_out pulses that fired while
//   the driver was still running.  Driving and collecting must be concurrent.
//
// WHY HH DOES NOT CHANGE DURING THE FUNCTIONAL STALL SEQUENCE:
//   Phase 2 (stall) must not alter the HH registers, because the pre-stall
//   frames are still in-flight in the accumulator pipeline.  Although they
//   have already passed the multiply stage (HH only participates there),
//   loading sentinel HH during the stall and then needing to reload frame-0
//   HH before Phase 3 introduces an extra load_hh() posedge inside a forked
//   driver thread.  In practice the two threads' @(posedge clk) advances can
//   de-synchronise, causing the collector to sample valid_out one cycle late
//   and misattribute outputs.  The fix is clean: keep frame-0 HH for the
//   entire functional sequence, then run the sentinel and CHECK 4 in a
//   separate sequential phase after the fork completes.
//
// SPURIOUS DETECTION:
//   valid_out is flagged spurious only when it asserts while en=0 AND the
//   scoreboard is empty (no output is legitimately due from pre-stall frames).
//
// =============================================================================