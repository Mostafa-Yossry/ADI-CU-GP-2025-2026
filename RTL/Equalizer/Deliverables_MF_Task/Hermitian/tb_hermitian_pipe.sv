// =============================================================================
// tb_hermitian_pipe.sv
// -----------------------------------------------------------------------------
// Self-checking testbench for hermitian_pipe.
//
// Two DUT instances are driven with identical inputs:
//   dut_comb : REGISTER_OUTPUT=0  (Mode 1 -- combinational, 0-cycle latency)
//   dut_reg  : REGISTER_OUTPUT=1  (Mode 2 -- registered,    1-cycle latency)
//
// For every test matrix, the golden model is computed directly in the
// testbench using the same formula the DUT implements:
//
//   exp_real[c][r] =  h_real[r][c]
//   exp_imag[c][r] = -h_imag[r][c]
//
// Because SystemVerilog arithmetic on fixed-width signed vectors is
// implicitly modulo 2^WL, `-h_imag[r][c]` evaluated here in the testbench
// already wraps -2^(WL-1) -> -2^(WL-1), exactly matching both the DUT and
// MATLAB's Wrap-mode ctranspose(). No special-casing is needed in the
// golden model either.
//
// Test matrices:
//   1. All-zero matrix
//   2. "Identity-like" matrix (diagonal = 0.5, off-diagonal = 0, imag = 0)
//   3. Full-scale positive matrix (every element = +2^(WL-1)-1, real & imag)
//   4. Minimum-negative matrix (every imag element = -2^(WL-1)) -- exercises
//      the two's-complement wrap corner case
//   5. N_RAND randomized matrices
//   6. Back-to-back burst of N_BURST randomized matrices, one per cycle,
//      checking the registered DUT sustains 1-cycle latency / 1 matrix/cycle
// =============================================================================

`timescale 1ns/1ps

module tb_hermitian_pipe;

    // -------------------------------------------------------------------
    // Parameters -- must match DUT defaults
    // -------------------------------------------------------------------
    localparam int ROWS      = 8;
    localparam int COLS      = 8;
    localparam int WL        = 12;
    localparam int INT_BITS  =  0;
    localparam int FRAC_BITS = 11;

    localparam int N_RAND  = 5;
    localparam int N_BURST = 6;

    // -------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------
    logic clk;
    initial clk = 0;
    always #5 clk = ~clk;

    logic rst_n;

    // -------------------------------------------------------------------
    // Shared stimulus / golden arrays
    // -------------------------------------------------------------------
    logic                  valid_in;
    logic signed [WL-1:0] h_real  [0:ROWS-1][0:COLS-1];
    logic signed [WL-1:0] h_imag  [0:ROWS-1][0:COLS-1];

    logic                  valid_out_comb;
    logic signed [WL-1:0] hh_real_comb [0:COLS-1][0:ROWS-1];
    logic signed [WL-1:0] hh_imag_comb [0:COLS-1][0:ROWS-1];

    logic                  valid_out_reg;
    logic signed [WL-1:0] hh_real_reg [0:COLS-1][0:ROWS-1];
    logic signed [WL-1:0] hh_imag_reg [0:COLS-1][0:ROWS-1];

    logic signed [WL-1:0] exp_real [0:COLS-1][0:ROWS-1];
    logic signed [WL-1:0] exp_imag [0:COLS-1][0:ROWS-1];

    int pass_cnt, fail_cnt;

    // -------------------------------------------------------------------
    // DUT instances
    // -------------------------------------------------------------------
    hermitian_pipe #(
        .ROWS(ROWS), .COLS(COLS),
        .WL(WL), .INT_BITS(INT_BITS), .FRAC_BITS(FRAC_BITS),
        .REGISTER_OUTPUT(0)
    ) dut_comb (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid_in (valid_in),
        .h_real   (h_real),
        .h_imag   (h_imag),
        .valid_out(valid_out_comb),
        .hh_real  (hh_real_comb),
        .hh_imag  (hh_imag_comb)
    );

    hermitian_pipe #(
        .ROWS(ROWS), .COLS(COLS),
        .WL(WL), .INT_BITS(INT_BITS), .FRAC_BITS(FRAC_BITS),
        .REGISTER_OUTPUT(1)
    ) dut_reg (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid_in (valid_in),
        .h_real   (h_real),
        .h_imag   (h_imag),
        .valid_out(valid_out_reg),
        .hh_real  (hh_real_reg),
        .hh_imag  (hh_imag_reg)
    );

    // -------------------------------------------------------------------
    // Golden model: exp_real/exp_imag = Hermitian transpose of h_real/h_imag
    // -------------------------------------------------------------------
    task automatic compute_golden();
        for (int r = 0; r < ROWS; r++) begin
            for (int c = 0; c < COLS; c++) begin
                exp_real[c][r] =  h_real[r][c];
                exp_imag[c][r] = -h_imag[r][c];   // wraps at -2^(WL-1), as DUT does
            end
        end
    endtask

    // -------------------------------------------------------------------
    // Compare a [COLS][ROWS] output array against the golden array,
    // updating pass/fail counters and printing every mismatch.
    // -------------------------------------------------------------------
    task automatic check_array(string label,
                                logic signed [WL-1:0] got_r [0:COLS-1][0:ROWS-1],
                                logic signed [WL-1:0] got_i [0:COLS-1][0:ROWS-1]);
        for (int c = 0; c < COLS; c++) begin
            for (int r = 0; r < ROWS; r++) begin
                if (got_r[c][r] !== exp_real[c][r] || got_i[c][r] !== exp_imag[c][r]) begin
                    $display("    [%s] MISMATCH at [%0d][%0d]: got=(%0d,%0d) exp=(%0d,%0d)  FAIL",
                        label, c, r, got_r[c][r], got_i[c][r], exp_real[c][r], exp_imag[c][r]);
                    fail_cnt++;
                end else begin
                    pass_cnt++;
                end
            end
        end
    endtask

    // -------------------------------------------------------------------
    // Apply one matrix on h_real/h_imag, pulse valid_in for one cycle,
    // and check both DUT instances:
    //   - dut_comb is checked combinationally (same cycle the inputs are
    //     applied, latency = 0)
    //   - dut_reg  is checked one cycle later (latency = 1)
    // -------------------------------------------------------------------
    task automatic apply_and_check(string name, bit compute_golden_flag = 1'b1);
        if (compute_golden_flag) compute_golden();

        @(negedge clk);
        valid_in = 1'b1;
        // Combinational DUT: sample on the NEXT negedge, after a full half-cycle
        // for all combinational paths to settle.  This avoids any #N delay that
        // would be simulator-dependent (delta-cycle vs real-time resolution).
        @(posedge clk);
        @(negedge clk);

        // Combinational DUT output is stable on this negedge (valid_in is still
        // high from the previous negedge assignment, so hh_*_comb are valid).
        if (valid_out_comb !== 1'b1) begin
            $display("    [%s] dut_comb valid_out FAIL (expected 1, got %0d)", name, valid_out_comb);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
        check_array({name, ".comb"}, hh_real_comb, hh_imag_comb);

        // Registered DUT: result was registered on the posedge above, already
        // stable on this negedge.
        valid_in = 1'b0;

        if (valid_out_reg !== 1'b1) begin
            $display("    [%s] dut_reg valid_out FAIL (expected 1, got %0d)", name, valid_out_reg);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
        check_array({name, ".reg "}, hh_real_reg, hh_imag_reg);

        $display("  %-28s done", name);
    endtask

    // -------------------------------------------------------------------
    // Fill h_real/h_imag with a constant value
    // -------------------------------------------------------------------
    task automatic fill_const(logic signed [WL-1:0] real_val,
                               logic signed [WL-1:0] imag_val);
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++) begin
                h_real[r][c] = real_val;
                h_imag[r][c] = imag_val;
            end
    endtask

    // -------------------------------------------------------------------
    // Fill h_real/h_imag with a pseudo-random matrix
    // -------------------------------------------------------------------
    task automatic fill_random();
        int tmp;
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++) begin
                tmp = $random;
                h_real[r][c] = tmp[WL-1:0];
                tmp = $random;
                h_imag[r][c] = tmp[WL-1:0];
            end
    endtask

    // =====================================================================
    // Main test sequence
    // =====================================================================
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        valid_in = 1'b0;
        $srandom(32'hDEAD_BEEF);   // fixed seed — test vectors reproducible across runs/tools
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++) begin
                h_real[r][c] = '0;
                h_imag[r][c] = '0;
            end

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("========================================================");
        $display(" HERMITIAN PIPE TESTBENCH");
        $display(" ROWS=%0d COLS=%0d  WL=%0d INT_BITS=%0d FRAC_BITS=%0d", ROWS, COLS, WL, INT_BITS, FRAC_BITS);
        $display("========================================================");

        // -----------------------------------------------------------
        // 1. All-zero matrix
        // -----------------------------------------------------------
        fill_const('0, '0);
        apply_and_check("all_zero");

        // -----------------------------------------------------------
        // 2. Identity-like matrix: diagonal = 0.5 (Q1.11 -> 12'sh400),
        //    off-diagonal = 0, imag = 0 everywhere.
        // -----------------------------------------------------------
        for (int r = 0; r < ROWS; r++)
            for (int c = 0; c < COLS; c++) begin
                h_real[r][c] = (r == c) ? 12'sh400 : 12'sh000;
                h_imag[r][c] = 12'sh000;
            end
        apply_and_check("identity_like");

        // -----------------------------------------------------------
        // 3. Full-scale positive matrix: every element = +2^(WL-1)-1
        //    (12'sh7FF = +0.999511719 in Q1.11)
        // -----------------------------------------------------------
        fill_const(12'sh7FF, 12'sh7FF);
        apply_and_check("full_scale_pos");

        // -----------------------------------------------------------
        // 4. Minimum-negative imag: every imag element = -2^(WL-1)
        //    (12'sh800 = -1.0 in Q1.11). Verifies wrap: -(-2^(WL-1))
        //    == -2^(WL-1), NOT saturation to +2^(WL-1)-1.
        // -----------------------------------------------------------
        fill_const(12'sh000, 12'sh800);
        apply_and_check("min_negative_imag");

        // -----------------------------------------------------------
        // 5. Randomized matrices
        // -----------------------------------------------------------
        for (int i = 0; i < N_RAND; i++) begin
            fill_random();
            apply_and_check($sformatf("random_%0d", i));
        end

        // -----------------------------------------------------------
        // 6. Back-to-back burst: N_BURST random matrices, one per cycle.
        //    Confirms 1-cycle latency / 1 matrix-per-cycle throughput
        //    on dut_reg.
        // -----------------------------------------------------------
        $display("");
        $display("  Back-to-back burst (%0d frames, registered DUT)", N_BURST);
        begin
            logic signed [WL-1:0] burst_real [0:N_BURST-1][0:ROWS-1][0:COLS-1];
            logic signed [WL-1:0] burst_imag [0:N_BURST-1][0:ROWS-1][0:COLS-1];
            logic signed [WL-1:0] burst_exp_real [0:N_BURST-1][0:COLS-1][0:ROWS-1];
            logic signed [WL-1:0] burst_exp_imag [0:N_BURST-1][0:COLS-1][0:ROWS-1];

            // Pre-generate all burst matrices and golden results
            for (int i = 0; i < N_BURST; i++) begin
                fill_random();
                for (int r = 0; r < ROWS; r++)
                    for (int c = 0; c < COLS; c++) begin
                        burst_real[i][r][c] = h_real[r][c];
                        burst_imag[i][r][c] = h_imag[r][c];
                        burst_exp_real[i][c][r] =  h_real[r][c];
                        burst_exp_imag[i][c][r] = -h_imag[r][c];
                    end
            end

            for (int i = 0; i < N_BURST; i++) begin
                @(negedge clk);
                for (int r = 0; r < ROWS; r++)
                    for (int c = 0; c < COLS; c++) begin
                        h_real[r][c] = burst_real[i][r][c];
                        h_imag[r][c] = burst_imag[i][r][c];
                    end
                valid_in = 1'b1;

                // Check previous frame's registered output, now stable
                if (i > 0) begin
                    if (valid_out_reg !== 1'b1) begin
                        $display("    [burst_%0d] dut_reg valid_out FAIL", i-1);
                        fail_cnt++;
                    end else begin
                        pass_cnt++;
                    end
                    for (int c = 0; c < COLS; c++)
                        for (int r = 0; r < ROWS; r++) begin
                            if (hh_real_reg[c][r] !== burst_exp_real[i-1][c][r] ||
                                hh_imag_reg[c][r] !== burst_exp_imag[i-1][c][r]) begin
                                $display("    [burst_%0d] MISMATCH at [%0d][%0d]: got=(%0d,%0d) exp=(%0d,%0d)  FAIL",
                                    i-1, c, r, hh_real_reg[c][r], hh_imag_reg[c][r],
                                    burst_exp_real[i-1][c][r], burst_exp_imag[i-1][c][r]);
                                fail_cnt++;
                            end else begin
                                pass_cnt++;
                            end
                        end
                end
            end

            // Drain: deassert valid_in, then check the final frame's output
            @(negedge clk);
            valid_in = 1'b0;
            if (valid_out_reg !== 1'b1) begin
                $display("    [burst_%0d] dut_reg valid_out FAIL", N_BURST-1);
                fail_cnt++;
            end else begin
                pass_cnt++;
            end
            for (int c = 0; c < COLS; c++)
                for (int r = 0; r < ROWS; r++) begin
                    if (hh_real_reg[c][r] !== burst_exp_real[N_BURST-1][c][r] ||
                        hh_imag_reg[c][r] !== burst_exp_imag[N_BURST-1][c][r]) begin
                        $display("    [burst_%0d] MISMATCH at [%0d][%0d]: got=(%0d,%0d) exp=(%0d,%0d)  FAIL",
                            N_BURST-1, c, r, hh_real_reg[c][r], hh_imag_reg[c][r],
                            burst_exp_real[N_BURST-1][c][r], burst_exp_imag[N_BURST-1][c][r]);
                        fail_cnt++;
                    end else begin
                        pass_cnt++;
                    end
                end

            // One more cycle: valid_in has been low for one cycle, so
            // valid_out_reg should now be low (no extra output appears).
            @(negedge clk);
            if (valid_out_reg !== 1'b0) begin
                $display("    [burst_drain] dut_reg valid_out FAIL (expected 0, got %0d)", valid_out_reg);
                fail_cnt++;
            end else begin
                pass_cnt++;
            end
        end

        // -----------------------------------------------------------
        // 7. File-based golden vectors: H_binary.txt / HH_binary.txt
        // -----------------------------------------------------------
        //   H_binary.txt  : one WL-bit binary string per line. Row-major
        //                    over (r,c) for r=0..ROWS-1, c=0..COLS-1; each
        //                    (r,c) contributes 2 consecutive lines:
        //                      real[r][c]
        //                      imag[r][c]
        //                    Total = 2*ROWS*COLS lines per frame.
        //
        //   HH_binary.txt : one WL-bit binary string per line. Row-major
        //                    over (c,r) for c=0..COLS-1, r=0..ROWS-1 (i.e.
        //                    over H^H indices); each (c,r) contributes 2
        //                    consecutive lines:
        //                      real_HH[c][r]
        //                      imag_HH[c][r]
        //                    Total = 2*COLS*ROWS lines per frame.
        //
        //   $fscanf treats newlines as whitespace, so only the sequential
        //   order of values matters, not the exact line breaks.
        //
        //   Reads frames until EOF on either file. If the files are absent,
        //   this section is skipped with a message (no failure recorded).
        // -----------------------------------------------------------
        $display("");
        $display("  File-based golden vectors (H_binary.txt / HH_binary.txt)");
        begin
            integer fid_h, fid_hh, status, frame;
            logic signed [WL-1:0] val;
 
            fid_h  = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/H_binary.txt",  "r");
            fid_hh = $fopen("rtl_vectors_conv_Z_Q5_11_16bit/HH_binary.txt", "r");

            if (!fid_h || !fid_hh) begin
                $display("    (H_binary.txt / HH_binary.txt not found -- skipping)");
            end else begin
                frame = 0;
                forever begin
                    // Read H matrix: row-major (r,c), each element = real then imag
                    status = $fscanf(fid_h, "%b", val);
                    if (status != 1) begin
                        if (frame == 0)
                            $display("    H_binary.txt is empty -- skipping");
                        break;
                    end
                    h_real[0][0] = val;
                    status = $fscanf(fid_h, "%b", val);
                    h_imag[0][0] = val;
                    for (int r = 0; r < ROWS; r++) begin
                        for (int c = (r == 0) ? 1 : 0; c < COLS; c++) begin
                            status = $fscanf(fid_h, "%b", val);
                            h_real[r][c] = val;
                            status = $fscanf(fid_h, "%b", val);
                            h_imag[r][c] = val;
                        end
                    end

                    // Read HH golden matrix: row-major (c,r), each element = real then imag
                    for (int cc = 0; cc < COLS; cc++) begin
                        for (int rr = 0; rr < ROWS; rr++) begin
                            status = $fscanf(fid_hh, "%b", val);
                            exp_real[cc][rr] = val;
                            status = $fscanf(fid_hh, "%b", val);
                            exp_imag[cc][rr] = val;
                        end
                    end

                    apply_and_check($sformatf("file_frame_%0d", frame), 1'b0);
                    frame++;
                end

                $display("    %0d frame(s) checked from file", frame);
                $fclose(fid_h);
                $fclose(fid_hh);
            end
        end


        $display("");
        $display("========================================================");
        $display("  SUMMARY");
        $display("  PASS = %0d", pass_cnt);
        $display("  FAIL = %0d", fail_cnt);
        $display("========================================================");
        if (fail_cnt == 0) $display("  *** ALL TESTS PASSED ***");
        else               $display("  *** SOME TESTS FAILED ***");
        $display("========================================================");

        $finish;
    end

endmodule