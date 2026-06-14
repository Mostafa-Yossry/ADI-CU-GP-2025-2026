// =============================================================================
// tb_matched_filter_pipe_wrap.sv  —  Dimensionally-general version
// -----------------------------------------------------------------------------
// Wrapper testbench for matched_filter_pipe_wrap.
// All five processes (MAIN, Suite-A INJECTOR, Suite-A COLLECTOR,
// Suite-B STALL INJECTOR, Suite-B STALL COLLECTOR) and all five
// checks are preserved verbatim in logic; only the dimension semantics
// and DUT parameter names are updated.
//
// DIMENSION CHANGES vs. previous wrapper testbench
// -------------------------------------------------
//  Old wrapper used a single parameter N with ROWS=COLS=N.
//  New wrapper uses HH_ROWS and HH_COLS separately so the
//  testbench is dimensionally correct for rectangular H.
//
//  For the existing 8×8 configuration HH_ROWS=HH_COLS=8, so
//  all bus widths and array sizes are bit-for-bit identical.
//
// Convenience aliases
// -------------------
//  ROWS = HH_ROWS  (output vector length, rows of H^H)
//  COLS = HH_COLS  (dot-product length K, columns of H^H)
//
// These aliases map directly onto the original ROWS/COLS names
// used throughout the body, so every existing loop, assertion,
// and golden reference computes the same values unchanged.
//
// FLAT BUS PACKING (unchanged packing formula, now uses HH_COLS)
// ---------------------------------------------------------------
//  hh_re_flat / hh_im_flat:
//    flat[(r*HH_COLS + c)*WL_IN +: WL_IN] = hh[r][c]
//    (was: flat[(r*N + c)*WL_IN +: WL_IN])
//  y_re_flat / y_im_flat:
//    flat[k*WL_IN +: WL_IN] = y[k]              (unchanged)
//  x_re_flat / x_im_flat:
//    flat[k*WL_OUT +: WL_OUT] = g[k]            (unchanged)
//
// HIERARCHICAL PATH (unchanged)
// ------------------------------
//  CHECK 4 still uses dut.u_mf.coef_real / dut.u_mf.coef_imag.
//  The wrapper continues to instantiate the core as u_mf.
//
// All other logic, timing, and golden references are unchanged.
// =============================================================================

`timescale 1ns/1ps

module tb_ref_matched_filter_pipe_wrap;

// ---------------------------------------------------------------------------
// Testbench / DUT parameters
// ---------------------------------------------------------------------------
// HH_ROWS = rows of H^H    = COLS of H = output vector length
// HH_COLS = columns of H^H = ROWS of H = dot-product length K
// For the default 8×8 system these are both 8.
localparam int HH_ROWS       = 8;
localparam int HH_COLS       = 8;

localparam int WL_IN         = 12;
localparam int INT_BITS_IN   =  0;
localparam int FRAC_BITS_IN  = 11;
localparam int WL_INT        = 16;
localparam int INT_BITS_INT  =  0;
localparam int FRAC_BITS_INT = 15;
localparam int WL_OUT        = 16;
localparam int INT_BITS_OUT  =  4;
localparam int FRAC_BITS_OUT = 11;

// ---------------------------------------------------------------------------
// Convenience aliases — map to the original ROWS/COLS names used throughout
// the body so every loop, array, and golden reference computes identically.
// ---------------------------------------------------------------------------
localparam int ROWS = HH_ROWS;   // output vector length (rows of H^H)
localparam int COLS = HH_COLS;   // dot-product length K (columns of H^H)

// Pipeline latency: 1 (multiply) + $clog2(HH_COLS) (round+tree)
localparam int LEVELS   = $clog2(HH_COLS);    // 3 for HH_COLS=8
localparam int PIPE_LAT = 1 + LEVELS;          // 4 for HH_COLS=8

// Suite A
localparam int NUM_TESTS = 20;

// Suite B
localparam int STALL_TESTS     = 8;
localparam int STALL_FRAME_IDX = 1;
localparam int STALL_CYCLES    = 3;

// Scaling and tolerance
localparam real SCALE = 2.0 ** FRAC_BITS_OUT;   // 2048.0
localparam real TOL   = 0.5 / SCALE;

// ---------------------------------------------------------------------------
// Clock and cycle counter
// ---------------------------------------------------------------------------
logic clk;
initial clk = 0;
always #5 clk = ~clk;

logic   rst_n, en;
integer cycle_counter;

always @(posedge clk or negedge rst_n)
    if (!rst_n) cycle_counter <= 0;
    else        cycle_counter <= cycle_counter + 1;

// ---------------------------------------------------------------------------
// DUT ports  –  FLAT BUS versions
// Bus widths now use HH_ROWS and HH_COLS independently.
// For HH_ROWS=HH_COLS=8 they are bit-for-bit identical to the old N=8 buses.
// ---------------------------------------------------------------------------
logic                                          hh_load;
logic signed [HH_ROWS*HH_COLS*WL_IN-1:0]      hh_re_flat;   // row-major H^H real
logic signed [HH_ROWS*HH_COLS*WL_IN-1:0]      hh_im_flat;   // row-major H^H imag

logic                                          y_valid;
logic signed [HH_COLS*WL_IN-1:0]              y_re_flat;    // y real  (HH_COLS elements)
logic signed [HH_COLS*WL_IN-1:0]              y_im_flat;    // y imag  (HH_COLS elements)

logic                                          valid_out;
logic                                          gy_enable;
logic signed [HH_ROWS*WL_OUT-1:0]             x_re_flat;    // g real  (HH_ROWS elements)
logic signed [HH_ROWS*WL_OUT-1:0]             x_im_flat;    // g imag  (HH_ROWS elements)

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
ref_matched_filter_pipe_wrap #(
    .HH_ROWS               ( HH_ROWS        ),
    .HH_COLS               ( HH_COLS        ),
    .MF_WL_IN              ( WL_IN          ),
    .MF_INT_BITS_IN        ( INT_BITS_IN    ),
    .MF_FRAC_BITS_IN       ( FRAC_BITS_IN   ),
    .MF_INTERNAL_WL        ( WL_INT         ),
    .MF_INTERNAL_INT_BITS  ( INT_BITS_INT   ),
    .MF_INTERNAL_FRAC_BITS ( FRAC_BITS_INT  ),
    .MF_WL_OUT             ( WL_OUT         ),
    .MF_INT_BITS_OUT       ( INT_BITS_OUT   ),
    .MF_FRAC_BITS_OUT      ( FRAC_BITS_OUT  )
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
// Suite A shared memory
// Indexed as [test][ROWS][COLS] for H^H and [test][COLS] for y,
// matching the golden model computation g = H^H · y.
// ---------------------------------------------------------------------------
integer hh_r_mem [0:NUM_TESTS-1][0:ROWS-1][0:COLS-1];   // H^H real  [HH_ROWS][HH_COLS]
integer hh_i_mem [0:NUM_TESTS-1][0:ROWS-1][0:COLS-1];   // H^H imag  [HH_ROWS][HH_COLS]
integer y_r_mem  [0:NUM_TESTS-1][0:COLS-1];              // y real    [HH_COLS]
integer y_i_mem  [0:NUM_TESTS-1][0:COLS-1];              // y imag    [HH_COLS]
integer z_r_gold [0:NUM_TESTS-1][0:ROWS-1];              // g real    [HH_ROWS]
integer z_i_gold [0:NUM_TESTS-1][0:ROWS-1];              // g imag    [HH_ROWS]

integer vin_cycle  [0:NUM_TESTS+STALL_TESTS-1];
integer vout_cycle [0:NUM_TESTS+STALL_TESTS-1];

real    got_r [0:NUM_TESTS-1][0:ROWS-1];
real    got_i [0:NUM_TESTS-1][0:ROWS-1];

logic vectors_ready;
logic collect_done;

// ---------------------------------------------------------------------------
// Suite B shared memory
// ---------------------------------------------------------------------------
localparam logic signed [WL_IN-1:0] SENTINEL_COEF = 12'sh200;
localparam logic signed [WL_IN-1:0] SENTINEL_Y    = 12'sh100;

localparam int FRAC_WIDEN_TB = FRAC_BITS_INT - FRAC_BITS_IN;   // 4 default
localparam logic signed [WL_INT-1:0] SENTINEL_COEF_W = signed'(
    {{(WL_INT - WL_IN - FRAC_WIDEN_TB){SENTINEL_COEF[WL_IN-1]}},
       SENTINEL_COEF,
     {FRAC_WIDEN_TB{1'b0}}});

integer svout_cycle [0:STALL_TESTS-1];
real    sgot_r      [0:STALL_TESTS-1][0:ROWS-1];
real    sgot_i      [0:STALL_TESTS-1][0:ROWS-1];

real    sentinel_gold_r [0:ROWS-1];
real    sentinel_gold_i [0:ROWS-1];

logic   stall_vectors_ready;
logic   stall_collect_done;
logic   stall_window_active;
integer stall_spurious_vout;

integer check4a_pass, check4a_fail;

// ============================================================================
// PACK / UNPACK HELPER TASKS
// ============================================================================

// ---------------------------------------------------------------------------
// pack_hh_from_mem : load hh_re_flat / hh_im_flat from hh_r_mem / hh_i_mem
//   t    = test-vector index
//   row-major: flat[(r*HH_COLS + c)*WL_IN +: WL_IN] = hh[r][c]
//   (was: (r*N+c) — now uses HH_COLS, same value for square systems)
// ---------------------------------------------------------------------------
task automatic pack_hh_from_mem(input int t);
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++) begin
            hh_re_flat[(r*COLS+c)*WL_IN +: WL_IN] =
                WL_IN'(signed'(hh_r_mem[t][r][c]));
            hh_im_flat[(r*COLS+c)*WL_IN +: WL_IN] =
                WL_IN'(signed'(hh_i_mem[t][r][c]));
        end
endtask

// ---------------------------------------------------------------------------
// pack_y_from_mem : load y_re_flat / y_im_flat from y_r_mem / y_i_mem
//   t = test-vector index
//   flat[k*WL_IN +: WL_IN] = y[k],  k in [0, HH_COLS-1]
// ---------------------------------------------------------------------------
task automatic pack_y_from_mem(input int t);
    for (int k = 0; k < COLS; k++) begin
        y_re_flat[k*WL_IN +: WL_IN] = WL_IN'(signed'(y_r_mem[t][k]));
        y_im_flat[k*WL_IN +: WL_IN] = WL_IN'(signed'(y_i_mem[t][k]));
    end
endtask

// ---------------------------------------------------------------------------
// pack_sentinel_hh : fill hh flat buses with SENTINEL_COEF (real) / 0 (imag)
// ---------------------------------------------------------------------------
task automatic pack_sentinel_hh();
    for (int r = 0; r < ROWS; r++)
        for (int c = 0; c < COLS; c++) begin
            hh_re_flat[(r*COLS+c)*WL_IN +: WL_IN] = SENTINEL_COEF;
            hh_im_flat[(r*COLS+c)*WL_IN +: WL_IN] = '0;
        end
endtask

// ---------------------------------------------------------------------------
// pack_sentinel_y : fill y flat buses with SENTINEL_Y (real) / 0 (imag)
// ---------------------------------------------------------------------------
task automatic pack_sentinel_y();
    for (int k = 0; k < COLS; k++) begin
        y_re_flat[k*WL_IN +: WL_IN] = SENTINEL_Y;
        y_im_flat[k*WL_IN +: WL_IN] = '0;
    end
endtask

// ---------------------------------------------------------------------------
// pack_zero_hh / pack_zero_y : zero all flat input buses
// ---------------------------------------------------------------------------
task automatic pack_zero_hh();
    hh_re_flat = '0;
    hh_im_flat = '0;
endtask

task automatic pack_zero_y();
    y_re_flat = '0;
    y_im_flat = '0;
endtask

// ---------------------------------------------------------------------------
// unpack_x_to_got : capture x_re_flat / x_im_flat into got_r / got_i
//   idx = Suite A frame index
//   Output g has HH_ROWS elements: flat[k*WL_OUT +: WL_OUT] = g[k]
// ---------------------------------------------------------------------------
task automatic unpack_x_to_got(input int idx);
    for (int r = 0; r < ROWS; r++) begin
        got_r[idx][r] =
            $itor($signed(x_re_flat[r*WL_OUT +: WL_OUT])) / SCALE;
        got_i[idx][r] =
            $itor($signed(x_im_flat[r*WL_OUT +: WL_OUT])) / SCALE;
    end
endtask

// ---------------------------------------------------------------------------
// unpack_x_to_sgot : capture x_re_flat / x_im_flat into sgot_r / sgot_i
//   idx = Suite B frame index
// ---------------------------------------------------------------------------
task automatic unpack_x_to_sgot(input int idx);
    for (int r = 0; r < ROWS; r++) begin
        sgot_r[idx][r] =
            $itor($signed(x_re_flat[r*WL_OUT +: WL_OUT])) / SCALE;
        sgot_i[idx][r] =
            $itor($signed(x_im_flat[r*WL_OUT +: WL_OUT])) / SCALE;
    end
endtask


// ===========================================================================
// PROCESS 1 — MAIN  (unchanged logic; uses tasks for flat-bus driving)
// ===========================================================================
integer fid_hh_real, fid_hh_imag, fid_y_real, fid_y_imag,
        fid_z_real,  fid_z_imag;
integer t, row, col_idx_main, r, tmp, status;
integer pass_cnt, fail_cnt, lat_min, lat_max, lat_sum, lat_count;
real    exp_r, exp_i, err_r, err_i;

initial begin : main_proc

    vectors_ready       = 1'b0;
    collect_done        = 1'b0;
    stall_vectors_ready = 1'b0;
    stall_collect_done  = 1'b0;
    stall_window_active = 1'b0;
    stall_spurious_vout = 0;
    check4a_pass        = 0;
    check4a_fail        = 0;

    pass_cnt = 0; fail_cnt = 0;
    lat_min  = 32767; lat_max = 0; lat_sum = 0; lat_count = 0;

    fid_hh_real = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_real.txt", "r");
    fid_hh_imag = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/hh_imag.txt", "r");
    fid_y_real  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_real.txt",  "r");
    fid_y_imag  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_imag.txt",  "r");
    fid_z_real  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_real_golden.txt", "r");
    fid_z_imag  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_imag_golden.txt", "r");

    if (!fid_hh_real || !fid_hh_imag || !fid_y_real ||
        !fid_y_imag  || !fid_z_real  || !fid_z_imag) begin
        $display("ERROR: could not open one or more vector files");
        $finish;
    end

    // Reset sequence
    rst_n   = 1'b0;
    en      = 1'b1;
    hh_load = 1'b0;
    y_valid = 1'b0;
    pack_zero_hh();
    pack_zero_y();

    repeat(2) @(posedge clk);
    rst_n = 1'b1;
    repeat(4) @(posedge clk);

    // -----------------------------------------------------------------------
    // Load test vectors from files
    // Golden model: g = H^H · y
    //   H^H is ROWS×COLS, y is COLS×1, g is ROWS×1
    // File format is unchanged (column-then-row inner ordering).
    // -----------------------------------------------------------------------
    begin : load_vecs
        integer kk;
        for (t = 0; t < NUM_TESTS; t = t + 1) begin
            // H^H: outer loop over COLS (columns of H^H = rows of H)
            //      inner loop over ROWS (rows of H^H = columns of H)
            // Stored as hh_r_mem[t][row][kk] where row in [0,ROWS-1], kk in [0,COLS-1]
            for (kk = 0; kk < COLS; kk = kk + 1)
                for (row = 0; row < ROWS; row = row + 1) begin
                    status = $fscanf(fid_hh_real, "%d\n", tmp);
                    hh_r_mem[t][row][kk] = tmp;
                    status = $fscanf(fid_hh_imag, "%d\n", tmp);
                    hh_i_mem[t][row][kk] = tmp;
                end
            // y: COLS elements
            for (kk = 0; kk < COLS; kk = kk + 1) begin
                status = $fscanf(fid_y_real, "%d\n", tmp);
                y_r_mem[t][kk] = tmp;
                status = $fscanf(fid_y_imag, "%d\n", tmp);
                y_i_mem[t][kk] = tmp;
            end
            // g (golden): ROWS elements
            for (row = 0; row < ROWS; row = row + 1) begin
                status = $fscanf(fid_z_real, "%d\n", tmp);
                z_r_gold[t][row] = tmp;
                status = $fscanf(fid_z_imag, "%d\n", tmp);
                z_i_gold[t][row] = tmp;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Pre-compute sentinel golden values (unchanged)
    // sentinel: all H^H coefficients = SENTINEL_COEF, all y = SENTINEL_Y
    // g[row] = COLS * (SENTINEL_COEF_W * SENTINEL_Y_W) >> (FRAC_INT+FRAC_INT-FRAC_OUT)
    // -----------------------------------------------------------------------
    begin : sentinel_gold_calc
        real coef_fp, y_fp, prod_fp, sum_fp;
        integer frac_widen_lp;
        frac_widen_lp = FRAC_BITS_INT - FRAC_BITS_IN;
        coef_fp = $itor($signed(SENTINEL_COEF)) * (2.0 ** frac_widen_lp);
        y_fp    = $itor($signed(SENTINEL_Y))    * (2.0 ** frac_widen_lp);
        prod_fp = coef_fp * y_fp;
        sum_fp  = COLS * (prod_fp / (2.0 ** (FRAC_BITS_INT + FRAC_BITS_INT
                                             - FRAC_BITS_OUT)));
        for (row = 0; row < ROWS; row = row + 1) begin
            sentinel_gold_r[row] = sum_fp / SCALE;
            sentinel_gold_i[row] = 0.0;
        end
    end

    vectors_ready       = 1'b1;
    stall_vectors_ready = 1'b1;

    wait(collect_done);

    // -----------------------------------------------------------------------
    // SUITE A REPORT
    // -----------------------------------------------------------------------
    $display("");
    $display("========================================================");
    $display(" SUITE A — BACK-TO-BACK GOLDEN BURST");
    $display(" HH_ROWS=%0d  HH_COLS=%0d  PIPE_LAT=%0d  NUM_TESTS=%0d",
             HH_ROWS, HH_COLS, PIPE_LAT, NUM_TESTS);
    $display(" Fixed-point: Q%0d.%0d input, Q%0d.%0d output",
             INT_BITS_IN, FRAC_BITS_IN, INT_BITS_OUT, FRAC_BITS_OUT);
    $display(" TOL=%.6f  (half LSB in Q%0d.%0d output)",
             TOL, INT_BITS_OUT, FRAC_BITS_OUT);
    $display("========================================================");

    $display("");
    $display("  PIPELINE TIMING TABLE");
    $display("  %-6s  %-12s  %-12s  %-s",
             "Frame", "vin_cycle", "vout_cycle", "Latency");
    $display("  --------------------------------------------------------");

    for (t = 0; t < NUM_TESTS; t = t + 1) begin : timing_loop
        integer lat;
        lat = vout_cycle[t] - vin_cycle[t];
        $display("  %-6d  %-12d  %-12d  %0d cycles%s",
            t, vin_cycle[t], vout_cycle[t], lat,
            (lat == PIPE_LAT) ? "  OK" : "  *** WRONG ***");
        if (lat < lat_min) lat_min = lat;
        if (lat > lat_max) lat_max = lat;
        lat_sum   = lat_sum + lat;
        lat_count = lat_count + 1;
    end

    $display("");
    $display("  THROUGHPUT");
    $display("  First valid_in  : cycle %0d", vin_cycle[0]);
    $display("  Last valid_out  : cycle %0d", vout_cycle[NUM_TESTS-1]);
    $display("  Outputs/cycle   : %.2f  (ideal=1.00)",
        $itor(NUM_TESTS) /
        $itor(vout_cycle[NUM_TESTS-1] - vout_cycle[0] + 1));
    $display("  Pipeline latency: %0d cycles measured  (expected %0d)",
        vout_cycle[0] - vin_cycle[0], PIPE_LAT);

    $display("");
    $display("========================================================");
    $display("  FUNCTIONAL RESULTS");
    $display("========================================================");

    for (t = 0; t < NUM_TESTS; t = t + 1) begin : func_loop
        integer lat2;
        lat2 = vout_cycle[t] - vin_cycle[t];
        $display("");
        $display("  --- Frame %0d  vin=%0d  vout=%0d  lat=%0d ---",
                 t, vin_cycle[t], vout_cycle[t], lat2);
        $display("  %-5s  %-30s  %-s", "Row", "Output (real, imag)", "Status");

        for (row = 0; row < ROWS; row = row + 1) begin
            exp_r = $itor(z_r_gold[t][row]) / SCALE;
            exp_i = $itor(z_i_gold[t][row]) / SCALE;
            err_r = got_r[t][row] - exp_r;
            err_i = got_i[t][row] - exp_i;
            if (err_r < 0.0) err_r = -err_r;
            if (err_i < 0.0) err_i = -err_i;
            if ((err_r > TOL) || (err_i > TOL)) begin
                $display("  %-5d  got(%9.6f, %9.6f)  exp(%9.6f, %9.6f)  FAIL err=(%.5f,%.5f)",
                    row, got_r[t][row], got_i[t][row],
                    exp_r, exp_i, err_r, err_i);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("  %-5d  (%9.6f, %9.6f)          PASS",
                    row, got_r[t][row], got_i[t][row]);
                pass_cnt = pass_cnt + 1;
            end
        end
    end

    $display("");
    $display("========================================================");
    $display("  SUITE A — LATENCY SUMMARY (%0d frames)", lat_count);
    $display("  Min latency  : %0d cycles", lat_min);
    $display("  Max latency  : %0d cycles", lat_max);
    $display("  Mean latency : %.2f cycles",
             $itor(lat_sum) / $itor(lat_count));
    $display("  Expected     : %0d cycles (1 + $clog2(%0d))", PIPE_LAT, HH_COLS);
    $display("========================================================");
    $display("  SUITE A — FUNCTIONAL SUMMARY");
    $display("  PASS = %0d / %0d  rows x frames", pass_cnt, NUM_TESTS * ROWS);
    $display("  FAIL = %0d / %0d  rows x frames", fail_cnt, NUM_TESTS * ROWS);
    $display("========================================================");
    if (fail_cnt == 0) $display("  *** SUITE A ALL PASSED ***");
    else               $display("  *** SUITE A FAILURES DETECTED ***");

    wait(stall_collect_done);

    // -----------------------------------------------------------------------
    // SUITE B REPORT
    // -----------------------------------------------------------------------
    $display("");
    $display("========================================================");
    $display(" SUITE B — PIPELINE ENABLE (en) STALL TEST");
    $display(" STALL_TESTS=%0d  STALL_FRAME_IDX=%0d  STALL_CYCLES=%0d",
             STALL_TESTS, STALL_FRAME_IDX, STALL_CYCLES);
    $display("========================================================");

    begin : suite_b_report
        integer sb_pass, sb_fail, sb_t;
        real sb_exp_r, sb_exp_i, sb_err_r, sb_err_i;

        sb_pass = 0;
        sb_fail = 0;

        // CHECK 1
        $display("");
        $display("  CHECK 1: no valid_out during stall window (%0d cycles)",
                 STALL_CYCLES);
        if (stall_spurious_vout == 0) begin
            $display("  Spurious valid_out during stall: 0  PASS");
            sb_pass = sb_pass + 1;
        end else begin
            $display("  Spurious valid_out during stall: %0d  FAIL",
                     stall_spurious_vout);
            sb_fail = sb_fail + 1;
        end

        // CHECK 2
        $display("");
        $display("  CHECK 2: per-frame latency");
        $display("  %-6s  %-12s  %-12s  %-10s  %-s",
                 "Frame", "vin_cycle", "vout_cycle", "Latency", "Expected");
        $display("  -------------------------------------------------------");

        for (sb_t = 0; sb_t < STALL_TESTS; sb_t = sb_t + 1) begin : lat_check
            integer meas_lat, exp_lat;
            meas_lat = svout_cycle[sb_t] - vin_cycle[NUM_TESTS + sb_t];
            exp_lat  = (sb_t <= STALL_FRAME_IDX)
                       ? PIPE_LAT + STALL_CYCLES
                       : PIPE_LAT;
            $display("  %-6d  %-12d  %-12d  %-10d  %0d%s",
                sb_t,
                vin_cycle[NUM_TESTS + sb_t],
                svout_cycle[sb_t],
                meas_lat, exp_lat,
                (meas_lat == exp_lat) ? "  OK" : "  *** WRONG ***");
            if (meas_lat == exp_lat) sb_pass = sb_pass + 1;
            else                     sb_fail = sb_fail + 1;
        end

        // CHECK 3
        $display("");
        $display("  CHECK 3: functional output (non-sentinel frames 0..%0d)",
                 STALL_TESTS - 2);
        $display("  %-5s  %-30s  %-s", "Frame.Row", "Output (real, imag)", "Status");

        for (sb_t = 0; sb_t < STALL_TESTS - 1; sb_t = sb_t + 1) begin
            for (row = 0; row < ROWS; row = row + 1) begin
                sb_exp_r = $itor(z_r_gold[sb_t][row]) / SCALE;
                sb_exp_i = $itor(z_i_gold[sb_t][row]) / SCALE;
                sb_err_r = sgot_r[sb_t][row] - sb_exp_r;
                sb_err_i = sgot_i[sb_t][row] - sb_exp_i;
                if (sb_err_r < 0.0) sb_err_r = -sb_err_r;
                if (sb_err_i < 0.0) sb_err_i = -sb_err_i;
                if ((sb_err_r > TOL) || (sb_err_i > TOL)) begin
                    $display("  %-3d.%-3d  got(%9.6f, %9.6f)  exp(%9.6f, %9.6f)  FAIL",
                        sb_t, row, sgot_r[sb_t][row], sgot_i[sb_t][row],
                        sb_exp_r, sb_exp_i);
                    sb_fail = sb_fail + 1;
                end else begin
                    sb_pass = sb_pass + 1;
                end
            end
        end

        // CHECK 4
        // Hierarchical path: dut.u_mf.coef_real / dut.u_mf.coef_imag
        // Dimensions are now [HH_ROWS][HH_COLS] = [ROWS][COLS]
        $display("");
        $display("  CHECK 4: hh_load during stall (en=0) updates coef_real/coef_imag");
        $display("  (verified via dut.u_mf.coef_real/coef_imag, all %0dx%0d elements)",
                 ROWS, COLS);
        if (check4a_fail == 0)
            $display("  coef register check: PASS=%0d FAIL=%0d  PASS",
                     check4a_pass, check4a_fail);
        else
            $display("  coef register check: PASS=%0d FAIL=%0d  FAIL",
                     check4a_pass, check4a_fail);
        sb_pass = sb_pass + check4a_pass;
        sb_fail = sb_fail + check4a_fail;

        // CHECK 5
        $display("");
        $display("  CHECK 5: sentinel frame (index %0d) -- coef load one cycle ahead",
                 STALL_TESTS - 1);
        $display("  (coef: all rows/cols = SENTINEL_COEF=%0d, y: all cols = SENTINEL_Y=%0d)",
                 $signed(SENTINEL_COEF), $signed(SENTINEL_Y));
        $display("  %-5s  %-30s  %-s", "Row", "Output (real, imag)", "Status");

        begin : sentinel_check
            integer sent_idx;
            sent_idx = STALL_TESTS - 1;
            for (row = 0; row < ROWS; row = row + 1) begin
                sb_err_r = sgot_r[sent_idx][row] - sentinel_gold_r[row];
                sb_err_i = sgot_i[sent_idx][row] - sentinel_gold_i[row];
                if (sb_err_r < 0.0) sb_err_r = -sb_err_r;
                if (sb_err_i < 0.0) sb_err_i = -sb_err_i;
                if ((sb_err_r > TOL) || (sb_err_i > TOL)) begin
                    $display("  %-5d  got(%9.6f, %9.6f)  exp(%9.6f, %9.6f)  FAIL err=(%.5f,%.5f)",
                        row, sgot_r[sent_idx][row], sgot_i[sent_idx][row],
                        sentinel_gold_r[row], sentinel_gold_i[row],
                        sb_err_r, sb_err_i);
                    sb_fail = sb_fail + 1;
                end else begin
                    $display("  %-5d  (%9.6f, %9.6f)          PASS",
                        row, sgot_r[sent_idx][row], sgot_i[sent_idx][row]);
                    sb_pass = sb_pass + 1;
                end
            end
        end

        $display("");
        $display("========================================================");
        $display("  SUITE B — SUMMARY");
        $display("  PASS = %0d", sb_pass);
        $display("  FAIL = %0d", sb_fail);
        $display("========================================================");
        if (sb_fail == 0) $display("  *** SUITE B ALL PASSED ***");
        else              $display("  *** SUITE B FAILURES DETECTED ***");
        fail_cnt = fail_cnt + sb_fail;
    end

    // GLOBAL SUMMARY
    $display("");
    $display("========================================================");
    $display("  GLOBAL SUMMARY (Suite A + Suite B)");
    $display("  PASS = %0d", pass_cnt);
    $display("  FAIL = %0d", fail_cnt);
    $display("========================================================");
    if (fail_cnt == 0) $display("  *** ALL TESTS PASSED ***");
    else               $display("  *** SOME TESTS FAILED ***");
    $display("========================================================");

    $fclose(fid_hh_real); $fclose(fid_hh_imag);
    $fclose(fid_y_real);  $fclose(fid_y_imag);
    $fclose(fid_z_real);  $fclose(fid_z_imag);
    $finish;
end


// ===========================================================================
// PROCESS 2 — SUITE A INJECTOR
// ===========================================================================
integer inj_test;

initial begin : injector_proc
    wait(vectors_ready);

    $display(">>> [SuiteA] INJECTOR start  (pre-load frame 0 H^H)");

    @(negedge clk);
    pack_hh_from_mem(0);
    hh_load = 1'b1;
    y_valid = 1'b0;
    @(posedge clk);

    $display(">>> [SuiteA] INJECTOR firing %0d frames...", NUM_TESTS);
    $display("");
    $display("  %-6s  %-12s  %-s", "Frame", "vin_cycle", "Pipeline occupancy");
    $display("  -------------------------------------------------------");

    for (inj_test = 0; inj_test < NUM_TESTS; inj_test = inj_test + 1) begin
        @(negedge clk);
        pack_y_from_mem(inj_test);
        y_valid = 1'b1;

        if (inj_test + 1 < NUM_TESTS) begin
            pack_hh_from_mem(inj_test + 1);
            hh_load = 1'b1;
        end else begin
            hh_load = 1'b0;
        end

        @(posedge clk);
        vin_cycle[inj_test] = cycle_counter;

        begin : fill_disp
            integer stage, sf;
            sf = (inj_test + 1 < PIPE_LAT) ? (inj_test + 1) : PIPE_LAT;
            $write("  %-6d  %-12d  [", inj_test, vin_cycle[inj_test]);
            for (stage = 0; stage < PIPE_LAT; stage = stage + 1) begin
                $write("%s", (stage < sf) ? "##" : "  ");
                if (stage < PIPE_LAT - 1) $write("|");
            end
            if (inj_test + 1 >= PIPE_LAT)
                $display("]  PIPELINE FULL - 1 output/cycle");
            else
                $display("]  filling (%0d/%0d)", sf, PIPE_LAT);
        end
    end

    @(negedge clk);
    y_valid = 1'b0;
    hh_load = 1'b0;
    pack_zero_y();

    $display("");
    $display(">>> [SuiteA] INJECTOR done. vin[0]=%0d  vin[%0d]=%0d",
             vin_cycle[0], NUM_TESTS-1, vin_cycle[NUM_TESTS-1]);
end


// ===========================================================================
// PROCESS 3 — SUITE A COLLECTOR
// ===========================================================================
integer col_idx;

initial begin : collector_proc
    wait(vectors_ready);
    col_idx = 0;

    while (col_idx < NUM_TESTS) begin
        @(posedge clk);
        if (valid_out === 1'b1) begin
            vout_cycle[col_idx] = cycle_counter;
            unpack_x_to_got(col_idx);
            col_idx = col_idx + 1;
        end
    end

    $display(">>> [SuiteA] COLLECTOR done. vout[0]=%0d  vout[%0d]=%0d",
             vout_cycle[0], NUM_TESTS-1, vout_cycle[NUM_TESTS-1]);
    collect_done = 1'b1;
end


// ===========================================================================
// PROCESS 4 — SUITE B STALL INJECTOR
// Hierarchical reference: dut.u_mf.coef_real/coef_imag [HH_ROWS][HH_COLS]
// ===========================================================================
integer sinj_test, stall_cy;

initial begin : stall_injector_proc
    wait(stall_vectors_ready);
    wait(collect_done);

    $display("");
    $display(">>> [SuiteB] STALL INJECTOR start");
    $display("    Stall after frame %0d, for %0d cycles, then sentinel frame",
             STALL_FRAME_IDX, STALL_CYCLES);

    // Clean DUT state before Suite B
    @(negedge clk);
    en      = 1'b1;
    y_valid = 1'b0;
    hh_load = 1'b0;
    pack_zero_y();
    pack_zero_hh();

    rst_n = 1'b0;
    repeat(2) @(posedge clk);
    rst_n = 1'b1;
    repeat(4) @(posedge clk);

    // ------------------------------------------------------------------
    // Phase 1: pre-stall frames 0 .. STALL_FRAME_IDX
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] Phase 1: pre-loading frame 0 coefs");

    @(negedge clk);
    pack_hh_from_mem(0);
    hh_load = 1'b1;
    y_valid = 1'b0;
    en      = 1'b1;
    @(posedge clk);

    $display(">>> [SuiteB] Phase 1: firing %0d pre-stall frames",
             STALL_FRAME_IDX + 1);

    for (sinj_test = 0; sinj_test <= STALL_FRAME_IDX; sinj_test = sinj_test + 1) begin
        @(negedge clk);
        pack_y_from_mem(sinj_test);
        y_valid = 1'b1;
        en      = 1'b1;

        if (sinj_test + 1 <= STALL_FRAME_IDX) begin
            pack_hh_from_mem(sinj_test + 1);
            hh_load = 1'b1;
        end else begin
            // Last pre-stall frame: sentinel coef comes during stall
            hh_load = 1'b0;
        end

        @(posedge clk);
        vin_cycle[NUM_TESTS + sinj_test] = cycle_counter;
        $display("    [SuiteB] pre-stall frame %0d  vin=%0d",
                 sinj_test, vin_cycle[NUM_TESTS + sinj_test]);
    end

    // ------------------------------------------------------------------
    // Phase 2: stall window (STALL_CYCLES cycles, en=0)
    //   First stall negedge: load SENTINEL coef (hh_load not gated by en)
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] Phase 2: asserting stall (en=0) for %0d cycles",
             STALL_CYCLES);

    stall_window_active = 1'b1;

    for (stall_cy = 0; stall_cy < STALL_CYCLES; stall_cy = stall_cy + 1) begin
        @(negedge clk);
        en      = 1'b0;
        y_valid = 1'b0;

        if (stall_cy == 0) begin
            pack_sentinel_hh();
            hh_load = 1'b1;
            $display("    [SuiteB] stall cycle %0d: hh_load=1 (sentinel coef)",
                     stall_cy);
        end else begin
            hh_load = 1'b0;
            $display("    [SuiteB] stall cycle %0d: en=0 valid_out must be 0",
                     stall_cy);
        end
        @(posedge clk);
    end

    stall_window_active = 1'b0;

    // ------------------------------------------------------------------
    // CHECK 4: verify coef registers via hierarchical reference.
    // Path: dut.u_mf.coef_real / dut.u_mf.coef_imag
    // Arrays are now [HH_ROWS][HH_COLS] = [ROWS][COLS]
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] CHECK 4: verifying dut.u_mf.coef_real/coef_imag == SENTINEL_COEF_W");
    for (int chk_r = 0; chk_r < ROWS; chk_r = chk_r + 1) begin
        for (int chk_c = 0; chk_c < COLS; chk_c = chk_c + 1) begin
            if (dut.u_mf.coef_real[chk_r][chk_c] !== SENTINEL_COEF_W ||
                dut.u_mf.coef_imag[chk_r][chk_c] !== '0) begin
                $display("    CHECK4 MISMATCH at [%0d][%0d]: got=(%0d,%0d) exp=(%0d,0)  FAIL",
                    chk_r, chk_c,
                    dut.u_mf.coef_real[chk_r][chk_c],
                    dut.u_mf.coef_imag[chk_r][chk_c],
                    SENTINEL_COEF_W);
                check4a_fail = check4a_fail + 1;
            end else begin
                check4a_pass = check4a_pass + 1;
            end
        end
    end
    $display("    [SuiteB] CHECK4 coef register check: PASS=%0d FAIL=%0d",
             check4a_pass, check4a_fail);

    // ------------------------------------------------------------------
    // Phase 3: post-stall frames STALL_FRAME_IDX+1 .. STALL_TESTS-2
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] Phase 3: post-stall frames %0d..%0d",
             STALL_FRAME_IDX + 1, STALL_TESTS - 2);

    @(negedge clk);
    en      = 1'b1;
    y_valid = 1'b0;
    hh_load = 1'b0;
    if (STALL_FRAME_IDX + 1 <= STALL_TESTS - 2) begin
        pack_hh_from_mem(STALL_FRAME_IDX + 1);
        hh_load = 1'b1;
    end
    @(posedge clk);

    for (sinj_test = STALL_FRAME_IDX + 1;
         sinj_test <= STALL_TESTS - 2;
         sinj_test = sinj_test + 1) begin

        @(negedge clk);
        en = 1'b1;
        pack_y_from_mem(sinj_test);
        y_valid = 1'b1;

        if (sinj_test + 1 <= STALL_TESTS - 2) begin
            pack_hh_from_mem(sinj_test + 1);
            hh_load = 1'b1;
        end else begin
            // Last post-stall frame: pre-load SENTINEL coef for sentinel frame
            pack_sentinel_hh();
            hh_load = 1'b1;
        end

        @(posedge clk);
        vin_cycle[NUM_TESTS + sinj_test] = cycle_counter;
        $display("    [SuiteB] post-stall frame %0d  vin=%0d",
                 sinj_test, vin_cycle[NUM_TESTS + sinj_test]);
    end

    // ------------------------------------------------------------------
    // Phase 4: sentinel frame (index STALL_TESTS-1)
    // ------------------------------------------------------------------
    $display(">>> [SuiteB] Phase 4: sentinel frame (index %0d)", STALL_TESTS-1);
    @(negedge clk);
    en = 1'b1;
    pack_sentinel_y();
    y_valid = 1'b1;
    hh_load = 1'b0;
    @(posedge clk);
    vin_cycle[NUM_TESTS + STALL_TESTS - 1] = cycle_counter;
    $display("    [SuiteB] sentinel frame  vin=%0d",
             vin_cycle[NUM_TESTS + STALL_TESTS - 1]);

    @(negedge clk);
    y_valid = 1'b0;
    hh_load = 1'b0;
    en      = 1'b1;
    pack_zero_y();

    $display(">>> [SuiteB] STALL INJECTOR done");
end


// ===========================================================================
// PROCESS 5 — SUITE B STALL COLLECTOR
// ===========================================================================
integer sc_idx;

initial begin : stall_collector_proc
    wait(stall_vectors_ready);
    wait(collect_done);

    wait(stall_window_active);
    $display(">>> [SuiteB] COLLECTOR: stall window active, monitoring %0d cycles",
             STALL_CYCLES);

    // Monitor stall window: valid_out must stay 0
    repeat (STALL_CYCLES) begin
        @(posedge clk);
        if (valid_out === 1'b1) begin
            $display("  [SuiteB] SPURIOUS valid_out during stall at cycle %0d  FAIL",
                     cycle_counter);
            stall_spurious_vout = stall_spurious_vout + 1;
        end
    end
    $display(">>> [SuiteB] COLLECTOR: stall window ended, spurious_vout=%0d",
             stall_spurious_vout);

    // Collect STALL_TESTS outputs
    sc_idx = 0;
    while (sc_idx < STALL_TESTS) begin
        @(posedge clk);
        if (valid_out === 1'b1) begin
            svout_cycle[sc_idx] = cycle_counter;
            unpack_x_to_sgot(sc_idx);
            $display("    [SuiteB] collected output frame %0d at cycle %0d",
                     sc_idx, svout_cycle[sc_idx]);
            sc_idx = sc_idx + 1;
        end
    end

    $display(">>> [SuiteB] COLLECTOR done");
    stall_collect_done = 1'b1;
end


// ===========================================================================
// Global timeout guard
// ===========================================================================
initial begin : timeout_proc
    #50_000_000;
    $display("GLOBAL TIMEOUT — simulation exceeded 50 ms wall limit");
    $finish;
end

endmodule
// =============================================================================
// End of tb_matched_filter_pipe_wrap.sv  —  Dimensionally-general version
// =============================================================================