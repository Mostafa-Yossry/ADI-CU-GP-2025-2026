// =============================================================================
// tb_matched_filter_pipe_wrap.sv
// -----------------------------------------------------------------------------
// Self-checking testbench for matched_filter_pipe_wrap (combinational core).
//
// Suite A — 100-frame golden burst (bit-exact vs MATLAB reference files)
//   HH from frame 0 held static; Y streamed back-to-back; bit-exact check.
//
// Core latency: 2 cycles (input register + output register).
// gy_enable has been removed from both core and wrapper.
// =============================================================================

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

// Pure-combinational core: input register + output register = 2 cycles.
localparam int PIPE_LAT     = 2;

localparam int NUM_TESTS    = 100;
localparam int CLK_PERIOD   = 10;   // 100 MHz

localparam string DIR = "testbench_files2/";

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------
logic clk;
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---------------------------------------------------------------------------
// DUT ports  (gy_enable removed — not present in wrapper)
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

task automatic set_hh(input int f);
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++) begin
            automatic int idx = f*ROWS*COLS*2 + r*COLS*2 + c*2;
            hh_re_flat[(r*N+c)*WL_IN +: WL_IN] = mem_hh[idx];
            hh_im_flat[(r*N+c)*WL_IN +: WL_IN] = mem_hh[idx+1];
        end
endtask

task automatic drive_y(input int f);
    for (int k = 0; k < COLS; k++) begin
        automatic int idx = f*COLS*2 + k*2;
        y_re_flat[k*WL_IN +: WL_IN] = mem_y[idx];
        y_im_flat[k*WL_IN +: WL_IN] = mem_y[idx+1];
    end
endtask

task automatic push_expected(input int f, inout z_vec_t q[$]);
    z_vec_t v;
    for (int k = 0; k < ROWS; k++) begin
        v[k][0] = signed'(mem_z[f*ROWS*2 + k*2]);
        v[k][1] = signed'(mem_z[f*ROWS*2 + k*2 + 1]);
    end
    q.push_back(v);
endtask

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

task automatic zero_inputs();
    hh_re_flat = '0; hh_im_flat = '0;
    y_re_flat  = '0; y_im_flat  = '0;
endtask

// Standard reset: 4 cycles low, release, 2 idle cycles
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
    $display(" tb_matched_filter_pipe_wrap (pure-combinational core)");
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
        int first_out_cyc = 0;
        int cyc           = 0;
        int mm;

        fork
            // -----------------------------------------------------------------
            // Driver: stream 100 Y vectors back-to-back at 100% throughput.
            // Each posedge clk here corresponds to the input register capture.
            // The output register holds the result exactly 1 more cycle later,
            // so the collector sees valid_out 2 posedges after valid_in.
            // -----------------------------------------------------------------
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

            // -----------------------------------------------------------------
            // Collector: sample outputs as they arrive.
            //
            // Timing relative to the first driver posedge (cycle 0):
            //   cycle 0 : driver asserts y_valid=1 + Y[0] → input FF captures
            //   cycle 1 : comb path settles, output FF captures → valid_out=1
            //   cycle 2 : collector sees valid_out for frame 0 here
            //
            // We skip 2 posedges before entering the check loop so that the
            // first @(posedge clk) inside the loop lands on cycle 2, exactly
            // when the first output is expected.
            // -----------------------------------------------------------------
            begin
                repeat(PIPE_LAT) @(posedge clk);   // wait out pipeline depth
                while (vectors_out < NUM_TESTS) begin
                    @(posedge clk);
                    cyc++;
                    if (valid_out) begin
                        if (vectors_out == 0)
                            first_out_cyc = cyc;

                        if (sb_queue.size() == 0) begin
                            $display("    FAIL: spurious valid_out at collector cycle %0d", cyc);
                            err_cnt++;
                        end else begin
                            automatic z_vec_t exp = sb_queue.pop_front();
                            check_output(exp, vectors_out, mm);
                            err_cnt += mm;
                            vectors_out++;
                        end
                    end else begin
                        // In back-to-back streaming valid_out should be
                        // continuously high after the first output.
                        // A gap here means a timing regression.
                        if (vectors_out > 0 && vectors_out < NUM_TESTS) begin
                            $display("    WARN: valid_out dropped mid-stream at collector cycle %0d (out=%0d)",
                                     cyc, vectors_out);
                            err_cnt++;
                        end
                    end
                end
            end
        join

        $display("    First valid_out at collector cycle %0d (PIPE_LAT=%0d)",
                 first_out_cyc, PIPE_LAT);
        $display("    Vectors in=%0d  out=%0d", vectors_in, vectors_out);

        if (err_cnt == 0)
            $display(">>> SUITE A: ALL %0d FRAMES PASSED (bit-exact)", NUM_TESTS);
        else
            $display(">>> SUITE A: %0d ERROR(S)", err_cnt);

        total_errors += err_cnt;
    end

    // =======================================================================
    // Global summary
    // =======================================================================
    $display("");
    $display("=============================================================");
    $display(" GLOBAL SUMMARY");
    $display("=============================================================");
    if (total_errors == 0) begin
        $display(" SUCCESS: All tests passed!");
        $display(" matched_filter_pipe_wrap (combinational) verified");
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