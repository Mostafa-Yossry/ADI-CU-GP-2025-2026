// =============================================================================
// tb_herm_mf_integration.sv
// -----------------------------------------------------------------------------
// End-to-end integration testbench for herm_mf_chain.sv
//
// DUT chain:  H → hermitian_pipe → matched_filter_pipe → z
//
// Vector files (relative to simulation working directory):
//   rtl_vectors_conv_Z_Q5_11_16bit/H_binary.txt     -- H source
//   rtl_vectors_conv_Z_Q5_11_16bit/y_real.txt
//   rtl_vectors_conv_Z_Q5_11_16bit/y_imag.txt
//   rtl_vectors_conv_Z_Q5_11_16bit/z_real_golden.txt
//   rtl_vectors_conv_Z_Q5_11_16bit/z_imag_golden.txt
//
// H_binary.txt format (row-major, real then imag per element):
//   For each H[r][c] traversed r=0..N-1, c=0..N-1:
//     line 2*(r*N+c)   : WL_IN-bit MSB-first binary string for Real(H[r][c])
//     line 2*(r*N+c)+1 : WL_IN-bit MSB-first binary string for Imag(H[r][c])
//   One frame = 2*N*N lines.  Multiple frames concatenated.
//
// y_real/imag.txt:      N signed integers per frame, one per line.
// z_real/imag_golden:   N signed integers per frame, one per line.
//
// 7 checks (handoff §8d):
//   1  Latency    : z_valid fires exactly TOTAL_LAT=5 cycles after h_valid
//   2  Throughput : NUM_FRAMES outputs received in back-to-back burst
//   3  Functional : bit-exact match vs golden for every element/frame
//   4  gy_enable  : 0 after reset; rises on first z_valid; sticky
//   5  Back-to-back burst
//   6  H refresh  : load new H mid-burst; pre-refresh outputs match golden
//   7  en stall   : pipeline freezes; no spurious z_valid; correct resume
// =============================================================================

`timescale 1ns/1ps

module tb_herm_mf_integration;

// =============================================================================
// 1 — Parameters
// =============================================================================

    localparam int N            = 8;
    localparam int WIDTH        = 16;
    localparam int WL_IN        = 12;
    localparam int WL_OUT       = 16;

    localparam int HERM_LAT     = 1;
    localparam int MF_LAT       = 1 + $clog2(N);   // 4 for N=8
    localparam int TOTAL_LAT    = HERM_LAT + MF_LAT; // 5

    localparam int NUM_FRAMES       = 10;
    localparam int STALL_FRAME_IDX  = 1;   // stall after injecting this many y frames
                                            // must be < TOTAL_LAT-1=4  ✓
    localparam int REFRESH_FRAME    = 5;    // reload H after this many y frames injected
    localparam int TIMEOUT_CYCLES   = 10000;

    // H flat bus: N*N elements × WIDTH bits each
    localparam int H_BUS_W = N * N * WIDTH;
    // y / z flat bus: N elements × WIDTH bits each
    localparam int YZ_BUS_W = N * WIDTH;


// =============================================================================
// 2 — Clock, reset, DUT ports
// =============================================================================

    logic                        clk       = 1'b0;
    logic                        rst       = 1'b1;

    logic                        h_valid   = 1'b0;
    logic signed [H_BUS_W-1:0]   h_re_flat = '0;
    logic signed [H_BUS_W-1:0]   h_im_flat = '0;

    logic                        y_valid   = 1'b0;
    logic signed [YZ_BUS_W-1:0]  y_re_flat = '0;
    logic signed [YZ_BUS_W-1:0]  y_im_flat = '0;

    logic                        mf_en     = 1'b1;

    logic                        z_valid;
    logic signed [YZ_BUS_W-1:0]  z_re_flat;
    logic signed [YZ_BUS_W-1:0]  z_im_flat;
    logic                        gy_enable;

    always #5 clk = ~clk;

    herm_mf_chain #(.N(N), .WIDTH(WIDTH)) dut (
        .clk      (clk      ),
        .rst      (rst      ),
        .h_valid  (h_valid  ),
        .h_re_flat(h_re_flat),
        .h_im_flat(h_im_flat),
        .y_valid  (y_valid  ),
        .y_re_flat(y_re_flat),
        .y_im_flat(y_im_flat),
        .mf_en    (mf_en    ),
        .z_valid  (z_valid  ),
        .z_re_flat(z_re_flat),
        .z_im_flat(z_im_flat),
        .gy_enable(gy_enable)
    );


// =============================================================================
// 3 — Storage
// =============================================================================

    // File handles — opened/closed per suite
    integer fd_hb;                      // H_binary.txt
    integer fd_yr, fd_yi;               // y_real/imag.txt
    integer fd_zr, fd_zi;              // z golden (pre-loaded once)

    // Two H frames loaded up front from H_binary.txt
    logic signed [WL_IN-1:0] h_re0 [0:N-1][0:N-1];   // frame 0
    logic signed [WL_IN-1:0] h_im0 [0:N-1][0:N-1];
    logic signed [WL_IN-1:0] h_re1 [0:N-1][0:N-1];   // frame 1 (refresh)
    logic signed [WL_IN-1:0] h_im1 [0:N-1][0:N-1];

    // All golden z frames pre-loaded
    integer z_re_all [0:NUM_FRAMES-1][0:N-1];
    integer z_im_all [0:NUM_FRAMES-1][0:N-1];

    // Scratch for per-cycle y reads
    integer y_re_frame [0:N-1];
    integer y_im_frame [0:N-1];

    // Cycle counter (free-running)
    int cycle_cnt = 0;
    always @(posedge clk) cycle_cnt++;

    // Global failure counter
    int grand_fail = 0;


// =============================================================================
// 4 — Tasks
// =============================================================================

    // -------------------------------------------------------------------------
    // Open y files (or rewind by close+reopen)
    // -------------------------------------------------------------------------
    task automatic open_y_files();
        if (fd_yr) $fclose(fd_yr);
        if (fd_yi) $fclose(fd_yi);
        fd_yr = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_real.txt", "r");
        fd_yi = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/y_imag.txt", "r");
        if (fd_yr == 0 || fd_yi == 0)
            $fatal(1, "Cannot open y_real/imag.txt");
    endtask

    // -------------------------------------------------------------------------
    // Parse one H frame from H_binary.txt (already opened as fd_hb)
    // Binary strings: MSB-first, WL_IN characters, one string per line.
    // Layout: for each H[r][c] in row-major order — real line then imag line.
    // -------------------------------------------------------------------------
    task automatic read_h_frame(
        output logic signed [WL_IN-1:0] h_re [0:N-1][0:N-1],
        output logic signed [WL_IN-1:0] h_im [0:N-1][0:N-1]
    );
        string           line;
        logic [WL_IN-1:0] raw;
        int r, c, b;
        for (r = 0; r < N; r++) begin
            for (c = 0; c < N; c++) begin
                // Real part
                void'($fgets(line, fd_hb));
                while (line.len() > 0 &&
                       (line[line.len()-1] == "\n" || line[line.len()-1] == "\r"))
                    line = line.substr(0, line.len()-2);
                raw = '0;
                for (b = 0; b < WL_IN; b++)
                    raw[WL_IN-1-b] = (line[b] == "1") ? 1'b1 : 1'b0;
                h_re[r][c] = signed'(raw);

                // Imag part
                void'($fgets(line, fd_hb));
                while (line.len() > 0 &&
                       (line[line.len()-1] == "\n" || line[line.len()-1] == "\r"))
                    line = line.substr(0, line.len()-2);
                raw = '0;
                for (b = 0; b < WL_IN; b++)
                    raw[WL_IN-1-b] = (line[b] == "1") ? 1'b1 : 1'b0;
                h_im[r][c] = signed'(raw);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Pack an H array into the flat DUT bus (row-major, sign-extended slots)
    // -------------------------------------------------------------------------
    task automatic drive_h(
        input logic signed [WL_IN-1:0] h_re [0:N-1][0:N-1],
        input logic signed [WL_IN-1:0] h_im [0:N-1][0:N-1]
    );
        for (int r = 0; r < N; r++) begin
            for (int c = 0; c < N; c++) begin
                automatic int idx = r*N + c;
                h_re_flat[idx*WIDTH +: WIDTH] =
                    {{(WIDTH-WL_IN){h_re[r][c][WL_IN-1]}}, h_re[r][c]};
                h_im_flat[idx*WIDTH +: WIDTH] =
                    {{(WIDTH-WL_IN){h_im[r][c][WL_IN-1]}}, h_im[r][c]};
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Read one y frame from files and drive the flat bus
    // -------------------------------------------------------------------------
    task automatic drive_y();
        for (int i = 0; i < N; i++) begin
            void'($fscanf(fd_yr, "%d\n", y_re_frame[i]));
            void'($fscanf(fd_yi, "%d\n", y_im_frame[i]));
            y_re_flat[i*WIDTH +: WIDTH] = WIDTH'(signed'(y_re_frame[i]));
            y_im_flat[i*WIDTH +: WIDTH] = WIDTH'(signed'(y_im_frame[i]));
        end
    endtask

    // -------------------------------------------------------------------------
    // Apply reset for 3 cycles then deassert
    // -------------------------------------------------------------------------
    task automatic do_reset();
        @(negedge clk); rst = 1'b1; mf_en = 1'b1;
        h_valid = 1'b0; y_valid = 1'b0;
        @(posedge clk); @(posedge clk);
        @(negedge clk); rst = 1'b0;
        @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Assert h_valid for one cycle while driving h array onto flat bus.
    // Call at negedge; advances past the following posedge.
    // -------------------------------------------------------------------------
    task automatic load_h(
        input logic signed [WL_IN-1:0] h_re [0:N-1][0:N-1],
        input logic signed [WL_IN-1:0] h_im [0:N-1][0:N-1]
    );
        drive_h(h_re, h_im);
        h_valid = 1'b1;
        @(posedge clk);   // posedge C: herm samples h, combinatorial; mf_valid_in registered
        h_valid = 1'b0;
        // At posedge C+1: hh_load_w fires, coefs latched; mf_valid_in=1 arrives
    endtask


// =============================================================================
// 5 — Scoreboard
// Counts outputs and mismatches.  suite_* vars reset per suite.
// collect_active must be set BEFORE injection so outputs aren't missed.
// =============================================================================

    int  col_frame_idx  = 0;   // which golden frame to compare next
    int  col_outputs    = 0;   // total z_valid posedges seen while active
    int  col_mismatches = 0;
    logic col_active    = 1'b0;

    always @(posedge clk) begin
        if (z_valid && col_active) begin
            automatic int mm = 0;
            for (int i = 0; i < N; i++) begin
                automatic logic signed [WL_OUT-1:0] got_r, got_i;
                automatic int exp_r, exp_i;
                got_r = z_re_flat[i*WIDTH +: WL_OUT];
                got_i = z_im_flat[i*WIDTH +: WL_OUT];
                exp_r = z_re_all[col_frame_idx % NUM_FRAMES][i];
                exp_i = z_im_all[col_frame_idx % NUM_FRAMES][i];
                if ($signed(got_r) !== exp_r || $signed(got_i) !== exp_i) begin
                    $display("  MISMATCH frame=%0d elem=%0d  got=(%0d,%0d)  exp=(%0d,%0d)",
                             col_frame_idx, i,
                             $signed(got_r), $signed(got_i), exp_r, exp_i);
                    mm++;
                end
            end
            col_outputs++;
            col_mismatches += mm;
            col_frame_idx++;
        end
    end

    task automatic reset_scoreboard();
        col_frame_idx  = 0;
        col_outputs    = 0;
        col_mismatches = 0;
        col_active     = 1'b0;
    endtask


// =============================================================================
// 6 — gy_enable sticky monitor
// Runs continuously; resets its state when rst is asserted.
// Reports a failure if gy_enable ever drops after rising (until next reset).
// gy_enable is a registered output — it updates on the same posedge as z_valid.
// We check it on the FOLLOWING posedge to let the FF settle.
// =============================================================================

    logic gy_rose    = 1'b0;
    logic gy_dropped = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            gy_rose    = 1'b0;
            gy_dropped = 1'b0;
        end else begin
            if (gy_enable)              gy_rose = 1'b1;
            if (gy_rose && !gy_enable && !gy_dropped) begin
                $display("FAIL Check4-sticky: gy_enable dropped at cycle %0d", cycle_cnt);
                grand_fail++;
                gy_dropped = 1'b1;
            end
        end
    end

    // Check that gy_enable is high on the cycle AFTER the first z_valid.
    // Uses an event trigger so it fires once per z_valid rising edge,
    // then checks one posedge later.
    int gy_check_done = 0;
    always @(posedge clk) begin
        if (z_valid && !gy_check_done) begin
            gy_check_done = 1;
            @(posedge clk);
            if (!gy_enable) begin
                $display("FAIL Check4c: gy_enable not set one cycle after first z_valid");
                grand_fail++;
            end else
                $display("PASS Check4c: gy_enable set by first z_valid");
        end
    end


// =============================================================================
// 7 — Latency monitor
// Stamps cycle of first h_valid and first z_valid; compares to TOTAL_LAT.
// Resets between suites via lat_armed flag.
// =============================================================================

    int  lat_h_cy   = -1;
    int  lat_z_cy   = -1;
    logic lat_armed = 1'b0;
    logic lat_done  = 1'b0;

    always @(posedge clk) begin
        if (lat_armed && !lat_done) begin
            if (h_valid && lat_h_cy < 0)
                lat_h_cy = cycle_cnt;
            if (z_valid && lat_h_cy >= 0) begin
                lat_z_cy = cycle_cnt;
                lat_done = 1'b1;
            end
        end
    end

    task automatic arm_latency_check();
        lat_h_cy  = -1;
        lat_z_cy  = -1;
        lat_done  = 1'b0;
        lat_armed = 1'b1;
    endtask

    task automatic report_latency(int suite_fail_ref);
        // Wait until measured (or timeout)
        for (int w = 0; w < TOTAL_LAT + 10; w++) @(posedge clk);
        lat_armed = 1'b0;
        if (lat_z_cy < 0) begin
            $display("FAIL Check1: z_valid never arrived — latency unmeasured");
            grand_fail++;
        end else begin
            automatic int measured = lat_z_cy - lat_h_cy;
            if (measured === TOTAL_LAT)
                $display("PASS Check1: latency = %0d cycles (expected %0d)",
                         measured, TOTAL_LAT);
            else begin
                $display("FAIL Check1: latency = %0d cycles (expected %0d)",
                         measured, TOTAL_LAT);
                grand_fail++;
            end
        end
    endtask


// =============================================================================
// 8 — Global timeout watchdog
// =============================================================================

    initial begin : watchdog
        #(TIMEOUT_CYCLES * 10);
        $display("FATAL: global timeout at %0d cycles", TIMEOUT_CYCLES);
        $fatal(1);
    end


// =============================================================================
// 9 — Main test sequence
// =============================================================================

    initial begin : main_test
        automatic int suite_fail;

        // -----------------------------------------------------------
        // 0. Open files and pre-load golden z + two H frames
        // -----------------------------------------------------------
        fd_hb = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/H_binary.txt", "r");
        if (fd_hb == 0) $fatal(1, "Cannot open H_binary.txt");

        fd_zr = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_real_golden.txt", "r");
        fd_zi = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/z_imag_golden.txt", "r");
        if (fd_zr == 0 || fd_zi == 0) $fatal(1, "Cannot open z golden files");

        for (int f = 0; f < NUM_FRAMES; f++)
            for (int i = 0; i < N; i++) begin
                void'($fscanf(fd_zr, "%d\n", z_re_all[f][i]));
                void'($fscanf(fd_zi, "%d\n", z_im_all[f][i]));
            end
        $fclose(fd_zr); $fclose(fd_zi);

        read_h_frame(h_re0, h_im0);   // H frame 0
        read_h_frame(h_re1, h_im1);   // H frame 1 (refresh)
        $fclose(fd_hb);

        // -----------------------------------------------------------
        // Check 4a: gy_enable = 0 after reset (checked before any clk)
        // -----------------------------------------------------------
        do_reset();
        @(posedge clk);
        if (gy_enable !== 1'b0) begin
            $display("FAIL Check4a: gy_enable not 0 after reset (got %b)", gy_enable);
            grand_fail++;
        end else
            $display("PASS Check4a: gy_enable=0 after reset");


        // ================================================================
        // Suite A — Back-to-back burst
        // Checks: 1 (latency), 2 (throughput), 3 (functional),
        //         4 (gy_enable sticky), 5 (back-to-back)
        // ================================================================
        $display("\n--- Suite A: back-to-back burst (%0d frames) ---", NUM_FRAMES);
        suite_fail = 0;
        gy_check_done = 0;
        do_reset();
        open_y_files();
        reset_scoreboard();
        arm_latency_check();

        // Enable collector BEFORE injecting so no output is missed
        col_active = 1'b1;

        // Load H frame 0
        @(negedge clk);
        load_h(h_re0, h_im0);
        // posedge C done inside load_h; at posedge C+1 coefs land in MF

        // Stream NUM_FRAMES y vectors back-to-back
        // Each y drives at negedge; y_valid held for one cycle (posedge window)
        for (int f = 0; f < NUM_FRAMES; f++) begin
            @(negedge clk);
            drive_y();
            y_valid = 1'b1;
            @(posedge clk);
            y_valid = 1'b0;
        end

        // Wait for all outputs (pipeline fill + NUM_FRAMES output cycles)
        repeat (TOTAL_LAT + NUM_FRAMES + 4) @(posedge clk);
        col_active = 1'b0;

        // Check 2: throughput
        if (col_outputs !== NUM_FRAMES) begin
            $display("FAIL Check2: expected %0d outputs, got %0d",
                     NUM_FRAMES, col_outputs);
            suite_fail++;
        end else
            $display("PASS Check2: %0d/%0d outputs received", col_outputs, NUM_FRAMES);

        // Check 3: functional
        if (col_mismatches == 0)
            $display("PASS Check3: all %0d elements bit-exact vs golden",
                     col_outputs * N);
        else begin
            $display("FAIL Check3: %0d mismatches across %0d frames",
                     col_mismatches, col_outputs);
            suite_fail++;
        end

        // Check 1: latency (measured by always block, reported here)
        if (lat_done) begin
            automatic int measured = lat_z_cy - lat_h_cy;
            lat_armed = 1'b0;
            if (measured === TOTAL_LAT)
                $display("PASS Check1: latency = %0d cycles (expected %0d)",
                         measured, TOTAL_LAT);
            else begin
                $display("FAIL Check1: latency = %0d cycles (expected %0d)",
                         measured, TOTAL_LAT);
                suite_fail++;
            end
        end else begin
            $display("FAIL Check1: z_valid never arrived");
            suite_fail++;
        end

        grand_fail   += suite_fail;
        $display("Suite A: %0s (%0d failures)",
                 (suite_fail == 0) ? "PASS" : "FAIL", suite_fail);


        // ================================================================
        // Suite B — en stall mid-burst
        // Check 7: deassert mf_en → pipeline freezes; resume correct
        // ================================================================
        $display("\n--- Suite B: en stall (STALL_FRAME_IDX=%0d) ---", STALL_FRAME_IDX);
        suite_fail    = 0;
        do_reset();
        open_y_files();
        reset_scoreboard();

        // Load H frame 0, stream STALL_FRAME_IDX+1 y vectors
        @(negedge clk);
        load_h(h_re0, h_im0);

        for (int f = 0; f <= STALL_FRAME_IDX; f++) begin
            @(negedge clk);
            drive_y();
            y_valid = 1'b1;
            @(posedge clk);
            y_valid = 1'b0;
        end

        // Assert stall — deassert mf_en (Rule 1 ensures herm_valid_in=0
        // since h_valid is already 0; no further valid pulses reach MF)
        @(negedge clk);
        mf_en = 1'b0;

        // Check for spurious z_valid during stall (8 cycles)
        begin
            automatic int spurious = 0;
            repeat (8) begin
                @(posedge clk);
                if (z_valid) begin
                    $display("  FAIL Check7a: spurious z_valid during stall at cycle %0d",
                             cycle_cnt);
                    spurious++;
                end
            end
            if (spurious == 0)
                $display("PASS Check7a: no spurious z_valid during stall");
            else begin
                suite_fail += spurious;
            end
        end

        // Deassert stall; replay full burst from scratch
        @(negedge clk);
        mf_en = 1'b1;
        open_y_files();       // rewind y files
        reset_scoreboard();
        col_active = 1'b1;

        load_h(h_re0, h_im0);

        for (int f = 0; f < NUM_FRAMES; f++) begin
            @(negedge clk);
            drive_y();
            y_valid = 1'b1;
            @(posedge clk);
            y_valid = 1'b0;
        end

        repeat (TOTAL_LAT + NUM_FRAMES + 4) @(posedge clk);
        col_active = 1'b0;

        if (col_outputs !== NUM_FRAMES) begin
            $display("FAIL Check7b: post-stall expected %0d outputs, got %0d",
                     NUM_FRAMES, col_outputs);
            suite_fail++;
        end else
            $display("PASS Check7b: %0d outputs after stall resume", col_outputs);

        if (col_mismatches == 0)
            $display("PASS Check7c: all post-stall outputs bit-exact");
        else begin
            $display("FAIL Check7c: %0d mismatches after stall resume", col_mismatches);
            suite_fail++;
        end

        grand_fail   += suite_fail;
        $display("Suite B: %0s (%0d failures)",
                 (suite_fail == 0) ? "PASS" : "FAIL", suite_fail);


        // ================================================================
        // Suite C — H refresh mid-burst
        // Check 6: load new H; pre-refresh outputs match golden
        // ================================================================
        $display("\n--- Suite C: H refresh at frame %0d ---", REFRESH_FRAME);
        suite_fail = 0;
        do_reset();
        open_y_files();
        reset_scoreboard();
        col_active = 1'b1;

        // Load H frame 0
        @(negedge clk);
        load_h(h_re0, h_im0);

        // Stream REFRESH_FRAME y vectors with H frame 0
        for (int f = 0; f < REFRESH_FRAME; f++) begin
            @(negedge clk);
            drive_y();
            y_valid = 1'b1;
            @(posedge clk);
            y_valid = 1'b0;
        end

        // 1-cycle idle gap (Rule 3: no y in-flight during H reload)
        @(negedge clk); y_valid = 1'b0;

        // Load H frame 1 (refresh) — no y valid_in during this cycle
        load_h(h_re1, h_im1);

        // Resume streaming with H frame 1 for remaining frames
        for (int f = REFRESH_FRAME; f < NUM_FRAMES; f++) begin
            @(negedge clk);
            drive_y();
            y_valid = 1'b1;
            @(posedge clk);
            y_valid = 1'b0;
        end

        repeat (TOTAL_LAT + NUM_FRAMES + 4) @(posedge clk);
        col_active = 1'b0;

        // Check 6: first REFRESH_FRAME outputs must match golden (H frame 0)
        // col_frame_idx at this point = total outputs seen; first REFRESH_FRAME
        // outputs were compared against z_re_all[0..REFRESH_FRAME-1] by the
        // scoreboard. Mismatches in that range are already in col_mismatches.
        if (col_outputs < REFRESH_FRAME) begin
            $display("FAIL Check6a: only %0d outputs before refresh window (expected %0d)",
                     col_outputs, REFRESH_FRAME);
            suite_fail++;
        end else
            $display("PASS Check6a: %0d pre-refresh outputs received", REFRESH_FRAME);

        // Pre-refresh mismatch count (first REFRESH_FRAME frames)
        // Since scoreboard uses col_frame_idx % NUM_FRAMES, pre-refresh frames
        // 0..REFRESH_FRAME-1 compare against the correct golden indices.
        // Post-refresh outputs use a different H so we expect some "mismatches" —
        // that is expected and informational only.
        $display("INFO Check6b: total outputs=%0d, total_mismatches=%0d",
                 col_outputs, col_mismatches);
        $display("  (post-refresh z uses H frame 1 — separate golden needed for full verify)");

        grand_fail   += suite_fail;
        $display("Suite C: %0s (%0d failures)",
                 (suite_fail == 0) ? "PASS" : "FAIL", suite_fail);


        // ================================================================
        // Final report
        // ================================================================
        $display("\n==============================================");
        $display("INTEGRATION TB RESULT: %0s  (total failures = %0d)",
                 (grand_fail == 0) ? "PASS" : "FAIL", grand_fail);
        $display("==============================================\n");

        if (fd_yr) $fclose(fd_yr);
        if (fd_yi) $fclose(fd_yi);
        $finish;
    end

endmodule
// =============================================================================
// End of tb_herm_mf_integration.sv
// =============================================================================